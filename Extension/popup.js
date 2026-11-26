const $ = (id) => document.getElementById(id);
let mode = "video", pageUrl = "";

function setMode(m) {
  mode = m;
  $("m-video").classList.toggle("on", m === "video"); $("m-audio").classList.toggle("on", m === "audio");
  $("quality").hidden = m === "audio";
}

function say(text, kind) { const m = $("msg"); m.hidden = !text; m.textContent = text || ""; m.className = "msg " + (kind || ""); }

function errText(e) { return e === "bad_code" ? t("pop_code") : e === "app_off" ? t("pop_off") : e; }

async function init() {
  $("m-video").textContent = t("pop_video"); $("m-audio").textContent = t("pop_audio");
  $("go").textContent = t("pop_go"); $("opts").textContent = t("pop_options");
  const q = $("quality");
  for (const v of ["best", "2160", "1440", "1080", "720", "480"]) q.add(new Option(v === "best" ? t("pop_best") : v + "p", v));
  const s = await chrome.storage.local.get({ mode: "video", quality: "best" });
  q.value = s.quality; setMode(s.mode);
  $("m-video").onclick = () => setMode("video"); $("m-audio").onclick = () => setMode("audio");
  $("opts").onclick = (e) => { e.preventDefault(); chrome.runtime.openOptionsPage(); };

  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  pageUrl = tab && /^https?:/i.test(tab.url || "") ? tab.url : "";
  $("title").textContent = pageUrl ? (tab.title || pageUrl) : t("pop_nopage");
  $("host").textContent = pageUrl ? new URL(pageUrl).host : "";
  $("go").disabled = !pageUrl;

  $("go").onclick = async () => {
    await chrome.storage.local.set({ mode, quality: q.value });
    $("go").disabled = true;
    const r = await mdown("/add", { url: pageUrl, mode, quality: mode === "video" ? q.value : undefined });
    $("go").disabled = false;
    if (r.ok) { say(t("pop_sent"), "ok"); refresh(); }
    else if (r.error === "app_off") { say(errText(r.error), "err"); chrome.tabs.create({ url: `mdown://download?url=${encodeURIComponent(pageUrl)}&mode=${mode}`, active: false }); }
    else say(errText(r.error || "?"), "err");
  };
  refresh(); setInterval(refresh, 1200);
}

function fmtSpeed(b) { return b ? (b / 1048576).toFixed(1) + " Mo/s" : ""; }

async function refresh() {
  const r = await mdown("/jobs");
  $("dot").className = "dot " + (r.ok ? "on" : "off");
  if (!r.ok) { if (r.error === "bad_code" || r.error === "app_off") say(errText(r.error), "err"); return; }
  const list = $("list"); list.textContent = "";
  for (const j of r.jobs.slice(0, 5)) {
    const d = document.createElement("div"); d.className = "job";
    const n = document.createElement("div"); n.className = "n"; n.textContent = j.title || j.url;
    const s = document.createElement("div"); s.className = "s";
    const a = document.createElement("span"); a.textContent = t("st_" + j.state);
    const b = document.createElement("span"); b.textContent = j.state === "downloading" ? `${Math.round(j.progress * 100)} % · ${fmtSpeed(j.bytes_per_second)}` : "";
    s.append(a, b);
    const bar = document.createElement("div"); bar.className = "bar " + j.state;
    const i = document.createElement("i"); i.style.width = (j.state === "done" || j.state === "failed" ? 1 : j.progress) * 100 + "%"; bar.append(i);
    d.append(n, s, bar); list.append(d);
  }
}
init();
