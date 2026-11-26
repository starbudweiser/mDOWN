const $ = (id) => document.getElementById(id);
(async () => {
  $("help").textContent = t("opt_help"); $("l-code").textContent = t("opt_code"); $("l-port").textContent = t("opt_port"); $("save").textContent = t("opt_save");
  const s = await settings(); $("code").value = s.code; $("port").value = s.port;
  $("save").onclick = async () => {
    await chrome.storage.local.set({ code: $("code").value.trim(), port: Number($("port").value) || DEFAULT_PORT });
    const r = await mdown("/ping");
    $("msg").className = "msg " + (r.ok ? "ok" : "err");
    $("msg").textContent = r.ok ? t("opt_ok", r.version) : (r.error === "bad_code" ? t("pop_code") : t("pop_off"));
  };
})();
