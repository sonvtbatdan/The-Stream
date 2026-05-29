// Cloudflare Worker — AI proxy for The Stream
// Uses Cloudflare Workers AI — no external API key needed.
// Bindings (set in Dashboard → Bindings):
//   AI         = Workers AI (required)
//   RATE_LIMIT = KV namespace (optional)

const AI_MODEL    = "@cf/meta/llama-3.1-8b-instruct";
const MAX_PER_DAY = 200;

export default {
  async fetch(request, env) {
    try {
      return await handleRequest(request, env);
    } catch (e) {
      console.error("Worker exception:", e.message);
      return corsResponse(new Response(
        JSON.stringify({ error: { code: 500, message: "Internal error: " + e.message } }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      ));
    }
  }
};

async function handleRequest(request, env) {
  if (request.method === "OPTIONS") {
    return corsResponse(new Response(null, { status: 204 }));
  }
  if (request.method !== "POST") {
    return corsResponse(new Response("Method not allowed", { status: 405 }));
  }

  if (!env.AI) {
    return corsResponse(new Response(
      JSON.stringify({ error: { code: 500, message: "AI binding not configured" } }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    ));
  }

  // ── Rate limit (per IP) ───────────────────────────────────────────────────
  const ip    = request.headers.get("CF-Connecting-IP") || "unknown";
  const today = new Date().toISOString().slice(0, 10);
  const kvKey = ip + ":" + today;
  let count = 0;

  if (env.RATE_LIMIT) {
    try {
      count = parseInt(await env.RATE_LIMIT.get(kvKey) || "0");
      if (count >= MAX_PER_DAY) {
        return corsResponse(new Response(
          JSON.stringify({ error: { code: 429, message: "Đã đạt giới hạn " + MAX_PER_DAY + " lượt/ngày. Thử lại ngày mai." } }),
          { status: 429, headers: { "Content-Type": "application/json" } }
        ));
      }
    } catch (e) {
      console.error("KV error:", e.message);
    }
  }

  // ── Parse Gemini-format body ──────────────────────────────────────────────
  let geminiBody;
  try {
    geminiBody = JSON.parse(await request.text());
  } catch (e) {
    return corsResponse(new Response(
      JSON.stringify({ error: { code: 400, message: "Invalid JSON" } }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    ));
  }

  const systemText = geminiBody?.systemInstruction?.parts?.[0]?.text || "";
  const contents   = geminiBody?.contents || [];
  const genConfig  = geminiBody?.generationConfig || {};

  const messages = [];
  if (systemText) messages.push({ role: "system", content: systemText });
  for (const c of contents) {
    const role = c.role === "model" ? "assistant" : "user";
    messages.push({ role, content: c.parts?.[0]?.text || "" });
  }

  // ── Call Workers AI ───────────────────────────────────────────────────────
  const aiResp = await env.AI.run(AI_MODEL, {
    messages,
    max_tokens:  genConfig.maxOutputTokens || 1024,
    temperature: genConfig.temperature     || 0.7,
  });
  console.log("AI done, len:", aiResp?.response?.length ?? 0);

  if (env.RATE_LIMIT) {
    try { await env.RATE_LIMIT.put(kvKey, String(count + 1), { expirationTtl: 86400 }); }
    catch (e) { console.error("KV write error:", e.message); }
  }

  const text = aiResp?.response || "";
  const geminiResponse = {
    candidates: [{ content: { parts: [{ text }], role: "model" }, finishReason: "STOP" }]
  };

  return corsResponse(new Response(JSON.stringify(geminiResponse), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  }));
}

function corsResponse(resp) {
  const headers = new Headers(resp.headers);
  headers.set("Access-Control-Allow-Origin", "*");
  headers.set("Access-Control-Allow-Headers", "Content-Type");
  return new Response(resp.body, { status: resp.status, headers });
}
