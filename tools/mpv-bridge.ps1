# mpv-bridge.ps1
# Starts mpv with Windows named-pipe IPC, then bridges TCP → pipe.
param([int]$TcpPort = 12736)

# ── Resolve paths ─────────────────────────────────────────────────────────────
$toolsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $toolsDir) { $toolsDir = Split-Path -Parent $PSCommandPath }

$logFile  = Join-Path $toolsDir "mpv-bridge.log"
$mpvExe   = Join-Path $toolsDir "mpv.exe"
$ytdlpExe = Join-Path $toolsDir "yt-dlp.exe"
$pipeName = "mpv-godot"

function Log($msg) {
    $ts = [DateTime]::Now.ToString("HH:mm:ss.fff")
    Add-Content -Path $logFile -Value "$ts  $msg" -Encoding utf8
}

Set-Content -Path $logFile -Value "" -Encoding utf8   # clear on each run
Log "=== bridge start  port=$TcpPort ==="
Log "toolsDir : $toolsDir"
Log "mpv.exe  : $mpvExe  exists=$([System.IO.File]::Exists($mpvExe))"
Log "yt-dlp   : $ytdlpExe  exists=$([System.IO.File]::Exists($ytdlpExe))"

# ── Launch mpv via ProcessStartInfo (precise argument control) ────────────────
$mpvLog = Join-Path $toolsDir "mpv-ipc.log"
try {
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName       = $mpvExe
    $psi.Arguments      = "--no-video --no-terminal --force-window=no --idle=yes `"--ytdl-path=$ytdlpExe`" --input-ipc-server=$pipeName `"--log-file=$mpvLog`""
    $psi.WindowStyle    = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $psi.CreateNoWindow = $true
    $psi.UseShellExecute = $false
    $mpv = [System.Diagnostics.Process]::Start($psi)
    Log "mpv launched  PID=$($mpv.Id)"
    Log "mpv args: $($psi.Arguments)"
} catch {
    Log "ERROR launching mpv: $_"
    exit 1
}

# ── Check mpv is still alive + log its own IPC messages ──────────────────────
Start-Sleep -Milliseconds 2500
if ($mpv.HasExited) {
    Log "ERROR: mpv exited immediately! ExitCode=$($mpv.ExitCode)"
    if (Test-Path $mpvLog) {
        Get-Content $mpvLog | Select-Object -Last 30 | ForEach-Object { Log "  mpv> $_" }
    }
    exit 1
}
Log "mpv alive after 2.5s"
if (Test-Path $mpvLog) {
    Get-Content $mpvLog | Where-Object { $_ -match "ipc|pipe|socket|error|warn" } |
        ForEach-Object { Log "  mpv> $_" }
}

# ── Connect to mpv named pipe (retry up to 12 s) ──────────────────────────────
$pipe     = $null
$deadline = [DateTime]::Now.AddSeconds(12)
$attempts = 0
while ([DateTime]::Now -lt $deadline) {
    $attempts++
    $p = $null
    try {
        $p = [System.IO.Pipes.NamedPipeClientStream]::new(
            ".", $pipeName, [System.IO.Pipes.PipeDirection]::InOut)
        $p.Connect(500)
        $pipe = $p
        Log "Pipe connected on attempt $attempts"
        break
    } catch {
        if ($null -ne $p) { try { $p.Dispose() } catch {} }
        # Log each failure for first 3 attempts
        if ($attempts -le 3) { Log "  pipe attempt $attempts failed: $($_.Exception.Message)" }
        [System.Threading.Thread]::Sleep(300)
    }
}
if ($null -eq $pipe) {
    Log "ERROR: pipe timeout after $attempts attempts"
    # Dump any new IPC-related lines from mpv log
    if (Test-Path $mpvLog) {
        Get-Content $mpvLog | Where-Object { $_ -match "ipc|pipe|socket|error" } |
            ForEach-Object { Log "  mpv> $_" }
    }
    if (-not $mpv.HasExited) { try { $mpv.Kill() } catch {} }
    exit 1
}

$pipeWriter = [System.IO.StreamWriter]::new($pipe)
$pipeWriter.AutoFlush = $true
Log "Pipe writer ready"

# ── TCP listener ──────────────────────────────────────────────────────────────
try {
    $listener = [System.Net.Sockets.TcpListener]::new(
        [System.Net.IPAddress]::Loopback, $TcpPort)
    $listener.Start()
    Log "TCP listener started on port $TcpPort"
} catch {
    Log "ERROR starting TCP listener: $_"
    $pipeWriter.Close(); $pipe.Close()
    if (-not $mpv.HasExited) { try { $mpv.Kill() } catch {} }
    exit 1
}

# ── Main loop: forward TCP lines → named pipe ─────────────────────────────────
$tcpClient = $null
$tcpStream = $null
$buf = [byte[]]::new(4096)
$sb  = [System.Text.StringBuilder]::new()

try {
    while (-not $mpv.HasExited) {
        if ($null -eq $tcpClient -and $listener.Pending()) {
            $tcpClient = $listener.AcceptTcpClient()
            $tcpStream = $tcpClient.GetStream()
            $sb.Clear()
            Log "TCP client connected"
        }

        if ($null -ne $tcpClient) {
            try {
                if (-not $tcpClient.Connected) { throw [Exception]::new("disconnected") }
                if ($tcpStream.DataAvailable) {
                    $n = $tcpStream.Read($buf, 0, $buf.Length)
                    if ($n -le 0) { throw [Exception]::new("eof") }
                    $sb.Append([System.Text.Encoding]::UTF8.GetString($buf, 0, $n)) | Out-Null
                    $content = $sb.ToString()
                    $nl = $content.IndexOf("`n")
                    while ($nl -ge 0) {
                        $line = $content.Substring(0, $nl).TrimEnd("`r")
                        if ($line.Length -gt 0) {
                            $pipeWriter.WriteLine($line)
                            Log ">> $line"
                        }
                        $content = $content.Substring($nl + 1)
                        $nl = $content.IndexOf("`n")
                    }
                    $sb.Clear(); $sb.Append($content) | Out-Null
                } else {
                    [System.Threading.Thread]::Sleep(5)
                }
            } catch {
                Log "TCP client disconnected: $_"
                if ($null -ne $tcpClient) { try { $tcpClient.Close() } catch {} }
                $tcpClient = $null; $tcpStream = $null
            }
        } else {
            [System.Threading.Thread]::Sleep(10)
        }
    }
    Log "mpv exited"
} finally {
    if ($null -ne $tcpClient) { try { $tcpClient.Close() } catch {} }
    $listener.Stop()
    $pipeWriter.Close()
    $pipe.Close()
    if (-not $mpv.HasExited) { try { $mpv.Kill() } catch {} }
    Log "=== bridge exit ==="
}
