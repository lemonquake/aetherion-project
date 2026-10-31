// Aetherion Project website: live official-server status (/api/status, the stats server), download sizes and
// versions (/downloads/index.json, written by aetherion-admin), and the right download first for this device.
(() => {
  "use strict";

  const STATUS_URL = "/api/status";
  const INDEX_URL = "/downloads/index.json";
  const REFRESH_MS = 15000;

  const MODES = {
    classic: { name: "Classic", map: "Sitio Kalinaw" },
    deathmatch: { name: "Deathmatch", map: "Malasugue Mall" },
  };
  const MAPS = { kalinaw: "Sitio Kalinaw", lawless_sub: "Lawless Sub", malasugue_mall: "Malasugue Mall", freight_delight: "Freight Delight" };
  const STATES = {
    lobby: ["Waiting in the lobby", (n) => n > 0
      ? "Join now: the match starts within a minute."
      : "Empty. The match starts a minute after someone joins."],
    loading: ["Match loading", () => "Join to watch this one, then play the next."],
    match: ["Match in progress", () => "Join to watch this one, then play the next."],
    results: ["Match just ended", () => "The next lobby opens in a moment."],
    offline: ["Not answering", () => "This server is restarting or down. Try again in a few minutes."],
  };

  const $ = (sel, root = document) => root.querySelector(sel);
  const $$ = (sel, root = document) => Array.from(root.querySelectorAll(sel));

  function el(tag, cls, text) {
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text != null) e.textContent = text;
    return e;
  }

  function bytes(n) {
    if (!(n > 0)) return "";
    if (n < 1e6) return Math.round(n / 1e3) + " KB";
    if (n < 1e9) return Math.round(n / 1e6) + " MB";
    return (n / 1e9).toFixed(2) + " GB";
  }

  function fill(key, value) {
    if (!value) return;
    for (const e of $$('[data-fill="' + key + '"]')) e.textContent = value;
  }

  function cleanVersion(v) {
    return String(v || "").replace(/^aetherion-/, "");
  }

  // ---------------------------------------------------------------- this device

  function detectOS() {
    const ua = navigator.userAgent || "";
    if (/Android/i.test(ua)) return "android";
    if (/iPhone|iPad|iPod/i.test(ua) || (/Macintosh/i.test(ua) && navigator.maxTouchPoints > 1)) return "ios";
    if (/Windows/i.test(ua)) return "windows";
    if (/Macintosh|Mac OS X/i.test(ua)) return "mac";
    if (/Linux|X11|CrOS/i.test(ua)) return "linux";
    return "other";
  }

  function setupCTA() {
    const os = detectOS();
    document.documentElement.dataset.os = os;
    const win = $("#cta-windows");
    const android = $("#cta-android");
    const note = $("#cta-note");
    if (!win || !android) return;
    if (os === "android") {
      win.classList.replace("btn-primary", "btn-secondary");
      android.classList.replace("btn-secondary", "btn-primary");
      android.parentNode.insertBefore(android, win);
    }
    const notes = {
      ios: "There is no iPhone or iPad version yet. Open this page on an Android phone or a Windows PC to play.",
      mac: "There is no Mac version yet. Open this page on a Windows PC or an Android phone to play.",
      linux: "There is no Linux version to play yet. Use a Windows PC or an Android phone.",
    };
    if (notes[os] && note) {
      note.textContent = notes[os];
      note.hidden = false;
    }
  }

  // ---------------------------------------------------------------- servers

  function renderServer(card, s) {
    for (const old of $$(".server-state, .server-live, .server-ver", card)) old.remove();
    const live = el("div", "server-live");
    const count = el("div");
    const big = el("div", "count", String(Math.round(s.players || 0)));
    big.append(el("small", null, "/" + Math.round(s.max || 0)));
    count.append(big, el("span", "count-label", "players"));
    const state = STATES[s.state] ? s.state : "match";
    const st = el("div", "state");
    st.dataset.s = state;
    st.append(el("span", "state-name", STATES[state][0]), el("span", "state-text", STATES[state][1](s.players || 0)));
    live.append(count, st);
    card.append(live);
    if (s.version) card.append(el("p", "server-ver", "Server version " + cleanVersion(s.version)));
  }

  function renderOffline(card, why) {
    for (const old of $$(".server-state, .server-live, .server-ver", card)) old.remove();
    const live = el("div", "server-live");
    const st = el("div", "state");
    st.dataset.s = "offline";
    st.append(el("span", "state-name", STATES.offline[0]), el("span", "state-text", why || STATES.offline[1]()));
    live.append(st);
    card.append(live);
  }

  function cardFor(mode) {
    let card = $('.server[data-mode="' + mode + '"]');
    if (card) return card;
    // A mode this page does not know yet: add a plain card for it.
    const info = MODES[mode] || { name: mode, map: "" };
    card = el("article", "server");
    card.dataset.mode = mode;
    const top = el("div", "server-top");
    top.append(el("h3", null, info.name));
    card.append(top);
    $("#server-list").append(card);
    return card;
  }

  function setPill(state, text, prefix = "") {
    // Narrow screens hide the prefix (CSS .pill-long) so the header keeps the full name.
    const pill = $("#pill");
    pill.dataset.state = state;
    $("#pill-long").textContent = prefix;
    $("#pill-text").textContent = text;
  }

  async function refreshStatus() {
    try {
      const r = await fetch(STATUS_URL, { cache: "no-store" });
      if (!r.ok) throw new Error("HTTP " + r.status);
      const d = await r.json();
      const servers = Array.isArray(d.servers) ? d.servers : [];
      const seen = new Set();
      for (const s of servers) {
        const mode = String(s.game_mode || "classic");
        seen.add(mode);
        const card = cardFor(mode);
        const tag = $(".tag", card);
        if (tag && MAPS[s.map]) tag.textContent = MAPS[s.map];
        renderServer(card, s);
      }
      for (const card of $$(".server")) {
        if (!seen.has(card.dataset.mode)) renderOffline(card);
      }
      const playing = servers.reduce((n, s) => n + Math.round(s.players || 0), 0);
      if (servers.length) {
        setPill("up", playing + " playing", servers.length + (servers.length === 1 ? " server" : " servers") + " online · ");
      } else {
        setPill("down", "Servers restarting");
      }
      if (d.version) fill("game-version", cleanVersion(d.version));
    } catch (e) {
      for (const card of $$(".server")) renderOffline(card, "Can't reach the servers from here right now. Check your connection and reload.");
      setPill("down", "Servers unreachable");
    }
  }

  let timer = 0;
  function schedule() {
    clearTimeout(timer);
    if (document.visibilityState === "visible") timer = setTimeout(() => refreshStatus().then(schedule), REFRESH_MS);
  }

  // ---------------------------------------------------------------- downloads

  async function loadIndex() {
    try {
      const r = await fetch(INDEX_URL, { cache: "no-store" });
      if (!r.ok) return;
      const d = await r.json();
      const game = d.game || {};
      const plat = d.platforms || {};
      const lau = d.launchers || {};
      if (game.version) fill("game-version", game.version);
      if (plat.windows) {
        fill("win-download", bytes(plat.windows.download_size));
        fill("win-size", bytes(plat.windows.size));
      }
      if (lau.windows) {
        fill("launcher-size", bytes(lau.windows.size));
        fill("launcher-version", lau.windows.version);
      }
      if (lau.android) {
        fill("apk-size", bytes(lau.android.size));
        fill("apk-version", lau.android.version);
        if (game.version && lau.android.version !== game.version) {
          const alt = $("#get-android .req");
          if (alt) alt.textContent += " · the APK is " + lau.android.version + ", the servers run " + game.version + ": wait for the new APK";
        }
      }
      if (lau["android-opengl"]) fill("apk-gl-size", bytes(lau["android-opengl"].size));
      if (Array.isArray(game.notes) && game.notes.length) {
        const list = $("#notes-list");
        list.replaceChildren(...game.notes.map((n) => el("li", null, n)));
      }
      if (game.published) {
        const when = new Date(game.published);
        if (!isNaN(when)) {
          $("#notes-date").textContent = "Released " + when.toLocaleDateString(undefined, { year: "numeric", month: "long", day: "numeric" });
        }
      }
    } catch (e) {
      // The page already shows this release's sizes and notes; keep them.
    }
  }

  // ---------------------------------------------------------------- copy the log folder path

  function setupCopy() {
    if (!navigator.clipboard) return;
    for (const b of $$("[data-copy]")) {
      const src = document.getElementById(b.dataset.copy);
      if (!src) continue;
      b.hidden = false;
      b.addEventListener("click", async () => {
        try {
          await navigator.clipboard.writeText(src.textContent.trim());
          b.textContent = "Copied";
        } catch (e) {
          b.textContent = "Select and copy";
        }
        setTimeout(() => { b.textContent = "Copy"; }, 2000);
      });
    }
  }

  setupCTA();
  setupCopy();
  loadIndex();
  refreshStatus().then(schedule);
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible") refreshStatus().then(schedule);
    else clearTimeout(timer);
  });
})();
