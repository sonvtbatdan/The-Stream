# Left 200x200 widget: location, weather, clock, elapsed, remaining.
# Weather source: ip-api.com (geolocation) → open-meteo.com (weather).
class_name UserWeatherClock
extends Panel

const PANEL_SIZE       := Vector2(200.0, 200.0)
const WEATHER_INTERVAL := 600.0   # refresh every 10 min
const SAVE_PATH        := "user://session.cfg"

# WMO weather code → human-readable label
const WMO_LABELS: Dictionary = {
	0: "Clear", 1: "Mainly Clear", 2: "Partly Cloudy", 3: "Overcast",
	45: "Foggy", 48: "Icy Fog",
	51: "Light Drizzle", 53: "Drizzle", 55: "Heavy Drizzle",
	61: "Light Rain", 63: "Rain", 65: "Heavy Rain",
	71: "Light Snow", 73: "Snow", 75: "Heavy Snow",
	80: "Showers", 81: "Heavy Showers", 82: "Violent Showers",
	95: "Thunderstorm", 96: "Hail Storm", 99: "Heavy Hail Storm",
}

var _city_lbl:      Label
var _weather_lbl:   Label
var _clock_lbl:     Label
var _elapsed_lbl:   Label
var _remaining_lbl: Label

var _http_geo:     HTTPRequest
var _http_weather: HTTPRequest

var _lat  := 0.0
var _lon  := 0.0
var _weather_timer := 0.0

var _start_time: float  = 0.0
var _session_sec: float = 7200.0  # default 2 h; editable via session_duration property

var session_duration: float:
	get: return _session_sec
	set(v):
		_session_sec = maxf(60.0, v)
		_save_session()

func _ready() -> void:
	custom_minimum_size = PANEL_SIZE
	size = PANEL_SIZE
	_apply_style()
	_build_ui()
	_load_session()
	_fetch_geo()

func _apply_style() -> void:
	var s := StyleBoxFlat.new()
	s.bg_color            = Color(0.07, 0.09, 0.13, 0.95)
	s.border_width_left   = 1
	s.border_width_right  = 1
	s.border_width_top    = 1
	s.border_width_bottom = 1
	s.border_color        = Color(0.35, 0.45, 0.65, 0.9)
	s.corner_radius_top_left     = 6
	s.corner_radius_top_right    = 6
	s.corner_radius_bottom_left  = 6
	s.corner_radius_bottom_right = 6
	add_theme_stylebox_override("panel", s)

func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left   = 10
	vbox.offset_top    = 10
	vbox.offset_right  = -10
	vbox.offset_bottom = -10
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)

	_city_lbl    = _make_label("---", 11, Color(0.75, 0.85, 1.0))
	_weather_lbl = _make_label("---", 11, Color(0.85, 0.95, 0.75))
	_clock_lbl   = _make_label("--:--", 32, Color(1.0, 1.0, 1.0))
	_elapsed_lbl   = _make_label("ELAPSED: --:--", 10, Color(0.65, 0.75, 0.65))
	_remaining_lbl = _make_label("REMAINING: --:--", 10, Color(0.75, 0.65, 0.65))

	vbox.add_child(_city_lbl)
	vbox.add_child(_weather_lbl)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	vbox.add_child(_clock_lbl)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	vbox.add_child(_elapsed_lbl)
	vbox.add_child(_remaining_lbl)

	_http_geo     = HTTPRequest.new()
	_http_weather = HTTPRequest.new()
	add_child(_http_geo)
	add_child(_http_weather)
	_http_geo.request_completed.connect(_on_geo_done)
	_http_weather.request_completed.connect(_on_weather_done)

func _make_label(txt: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l

func _process(delta: float) -> void:
	_update_clock()
	_weather_timer += delta
	if _weather_timer >= WEATHER_INTERVAL and _lat != 0.0:
		_weather_timer = 0.0
		_fetch_weather()

func _update_clock() -> void:
	var t := Time.get_time_dict_from_system()
	_clock_lbl.text = "%02d:%02d" % [t["hour"], t["minute"]]

	var elapsed := Time.get_unix_time_from_system() - _start_time
	_elapsed_lbl.text   = "ELAPSED: "   + _fmt_duration(elapsed)
	var remaining := maxf(0.0, _session_sec - elapsed)
	_remaining_lbl.text = "REMAINING: " + _fmt_duration(remaining)

func _fmt_duration(sec: float) -> String:
	var s := int(sec)
	if s >= 3600:
		return "%02d:%02d" % [s / 3600, (s % 3600) / 60]
	return "%02d:%02d" % [s / 60, s % 60]

func _fetch_geo() -> void:
	_http_geo.request("http://ip-api.com/json?fields=city,regionName,lat,lon")

func _on_geo_done(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if code != 200:
		return
	var j: Variant = JSON.parse_string(body.get_string_from_utf8())
	if j is Dictionary:
		_lat = float(j.get("lat", 0.0))
		_lon = float(j.get("lon", 0.0))
		var city: String   = j.get("city", "")
		var region: String = j.get("regionName", "")
		_city_lbl.text = ("%s, %s" % [city, region]).strip_edges()
		_fetch_weather()

func _fetch_weather() -> void:
	var url := ("https://api.open-meteo.com/v1/forecast"
		+ "?latitude=%.4f&longitude=%.4f" % [_lat, _lon]
		+ "&current=temperature_2m,weathercode&temperature_unit=celsius")
	_http_weather.request(url)

func _on_weather_done(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if code != 200:
		return
	var j: Variant = JSON.parse_string(body.get_string_from_utf8())
	if j is Dictionary and j.has("current"):
		var cur: Dictionary = j["current"]
		var temp: float = float(cur.get("temperature_2m", 0.0))
		var wcode: int  = int(cur.get("weathercode", 0))
		var label: String = WMO_LABELS.get(wcode, "Unknown")
		_weather_lbl.text = "%s — %.0f°C" % [label, temp]

func _save_session() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("session", "start_time", _start_time)
	cfg.set_value("session", "duration",   _session_sec)
	cfg.save(SAVE_PATH)

func _load_session() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		_start_time  = cfg.get_value("session", "start_time", Time.get_unix_time_from_system())
		_session_sec = cfg.get_value("session", "duration",   7200.0)
	else:
		_start_time = Time.get_unix_time_from_system()
		_save_session()

func reset_session() -> void:
	_start_time = Time.get_unix_time_from_system()
	_save_session()
