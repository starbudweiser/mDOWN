// mDOWN — échanges avec l'appli (boucle locale uniquement). Le code d'association vient des réglages de mDOWN.
const DEFAULT_PORT = 47615;

async function settings() {
  const s = await chrome.storage.local.get({ code: "", port: DEFAULT_PORT });
  return { code: (s.code || "").trim(), port: Number(s.port) || DEFAULT_PORT };
}

// Rend {ok:true,…} ou {ok:false, error:"app_off" | "bad_code" | …}
async function mdown(path, body) {
  const { code, port } = await settings();
  if (!code) return { ok: false, error: "bad_code" };
  try {
    const r = await fetch(`http://127.0.0.1:${port}${path}`, {
      method: body === undefined ? "GET" : "POST",
      headers: { "Content-Type": "application/json", "X-mDOWN-Token": code },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    if (r.status === 401) return { ok: false, error: "bad_code" };
    return await r.json();
  } catch (e) {
    return { ok: false, error: "app_off" };
  }
}

function t(key, ...subs) { return chrome.i18n.getMessage(key, subs) || key; }
