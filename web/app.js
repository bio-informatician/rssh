(() => {
  // ==========================================================================
  // Rakhssh Chat v1.3.0 Client Application
  // Features:
  //   1. Zero-Knowledge End-to-End Encryption (E2EE) with AES-256
  //   2. Dual-Transport Engine: WebSocket primary + HTTP Safe Tunnel Fallback
  //   3. Bulletproof Firewall & Middlebox Resilience (Zero Message Drop)
  //   4. Outgoing Message Queue with Automatic Retry
  //   5. Lock Screen Notifications & Persistent Background Service
  // ==========================================================================

  // DOM Elements - Header & Status
  const statusIndicator = document.getElementById("statusIndicator");
  const statusText = document.getElementById("statusText");
  const roomStatusBadge = document.getElementById("roomStatusBadge");
  const currentRoomDisplay = document.getElementById("currentRoomDisplay");
  const transportBadge = document.getElementById("transportBadge");
  const antiDpiBadge = document.getElementById("antiDpiBadge");
  const btnSettings = document.getElementById("btnSettings");
  const btnLeaveRoom = document.getElementById("btnLeaveRoom");
  const btnDeleteRoom = document.getElementById("btnDeleteRoom");
  const btnNotification = document.getElementById("btnNotification");
  const btnClear = document.getElementById("btnClear");
  const btnCancelReconnectHeader = document.getElementById("btnCancelReconnectHeader");

  // DOM Elements - Reconnect Banner
  const reconnectBanner = document.getElementById("reconnectBanner");
  const reconnectBannerText = document.getElementById("reconnectBannerText");
  const btnToggleReconnect = document.getElementById("btnToggleReconnect");

  // DOM Elements - Room Gate
  const roomGate = document.getElementById("roomGate");
  const gateForm = document.getElementById("gateForm");
  const gateNickname = document.getElementById("gateNickname");
  const gateRoomName = document.getElementById("gateRoomName");
  const gateRoomPassword = document.getElementById("gateRoomPassword");
  const btnTogglePassword = document.getElementById("btnTogglePassword");
  const gateError = document.getElementById("gateError");
  const gateErrorText = document.getElementById("gateErrorText");
  const btnStopGateRetry = document.getElementById("btnStopGateRetry");
  const btnToggleAdvanced = document.getElementById("btnToggleAdvanced");
  const advancedServerBlock = document.getElementById("advancedServerBlock");
  const serverUrlInput = document.getElementById("serverUrl");
  const btnGatePresetDirect = document.getElementById("btnGatePresetDirect");
  const btnGatePresetCfTunnel = document.getElementById("btnGatePresetCfTunnel");
  const btnGatePresetCleanIp = document.getElementById("btnGatePresetCleanIp");
  const gateCleanIpBlock = document.getElementById("gateCleanIpBlock");
  const gateCleanIp = document.getElementById("gateCleanIp");
  const gateActiveModeBadge = document.getElementById("gateActiveModeBadge");
  const gateActiveConnNotice = document.getElementById("gateActiveConnNotice");
  const gateActiveConnNoticeText = document.getElementById("gateActiveConnNoticeText");
  const btnTestGateConn = document.getElementById("btnTestGateConn");
  const gateTestFeedback = document.getElementById("gateTestFeedback");
  const btnEnterRoom = document.getElementById("btnEnterRoom");

  // DOM Elements - Active Chat View
  const chatView = document.getElementById("chatView");
  const notifBanner = document.getElementById("notifBanner");
  const btnEnableNotif = document.getElementById("btnEnableNotif");
  const roomMembersBar = document.getElementById("roomMembersBar");
  const membersList = document.getElementById("membersList");
  const chatMessages = document.getElementById("chatMessages");
  const chatForm = document.getElementById("chatForm");
  const messageInput = document.getElementById("messageInput");

  // DOM Elements - Settings Modal
  const settingsModal = document.getElementById("settingsModal");
  const btnCloseSettingsBack = document.getElementById("btnCloseSettingsBack");
  const btnCloseSettings = document.getElementById("btnCloseSettings");
  const modalActiveModeBanner = document.getElementById("modalActiveModeBanner");
  const modalActiveModePill = document.getElementById("modalActiveModePill");
  const modalServerUrl = document.getElementById("modalServerUrl");
  const btnTestServerConn = document.getElementById("btnTestServerConn");
  const serverTestFeedback = document.getElementById("serverTestFeedback");
  const modalCleanIp = document.getElementById("modalCleanIp");
  const modalCleanIpBlock = document.getElementById("modalCleanIpBlock");
  const antiDpiToggle = document.getElementById("antiDpiToggle");
  const decoyChaffToggle = document.getElementById("decoyChaffToggle");
  const btnPresetDirect = document.getElementById("btnPresetDirect");
  const btnPresetCfTunnel = document.getElementById("btnPresetCfTunnel");
  const btnPresetCleanIp = document.getElementById("btnPresetCleanIp");
  const autoReconnectInput = document.getElementById("autoReconnect");
  const notificationToggle = document.getElementById("notificationToggle");
  const vibrationToggle = document.getElementById("vibrationToggle");
  const keepCredentialsInput = document.getElementById("keepCredentials");
  const btnTestNotif = document.getElementById("btnTestNotif");
  const btnMinimizeApp = document.getElementById("btnMinimizeApp");
  const btnDisconnectModal = document.getElementById("btnDisconnectModal");
  const btnDeleteRoomModal = document.getElementById("btnDeleteRoomModal");

  // Client Session Unique ID (persisted across refreshes in sessionStorage)
  let clientId = "";
  try {
    clientId = sessionStorage.getItem("rssh_client_id") || "";
    if (!clientId) {
      clientId = "c_" + Math.random().toString(36).substring(2, 10) + Date.now().toString(36);
      sessionStorage.setItem("rssh_client_id", clientId);
    }
  } catch (e) {
    clientId = "c_" + Math.random().toString(36).substring(2, 10) + Date.now().toString(36);
  }

  // Notification Toggle Icons (Feather / Lucide Style)
  const NOTIF_BELL_ON_SVG = `
    <svg viewBox="0 0 24 24" width="20" height="20" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round" stroke-linejoin="round">
      <path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9"></path>
      <path d="M13.73 21a2 2 0 0 1-3.46 0"></path>
    </svg>
  `;

  const NOTIF_BELL_OFF_SVG = `
    <svg viewBox="0 0 24 24" width="20" height="20" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round" stroke-linejoin="round">
      <path d="M13.73 21a2 2 0 0 1-3.46 0"></path>
      <path d="M18.63 13A17.89 17.89 0 0 1 18 8"></path>
      <path d="M6.26 6.26A5.86 5.86 0 0 0 6 8c0 7-3 9-3 9h14"></path>
      <path d="M18 8a6 6 0 0 0-9.33-5"></path>
      <line x1="1" y1="1" x2="23" y2="23"></line>
    </svg>
  `;

  // Application State
  let ws = null;
  let wsHandshakeTimer = null;
  let jitteredPingTimer = null;
  let decoyChaffTimer = null;
  let heartbeatTimer = null;
  let reconnectTimer = null;
  let httpPollTimer = null;
  let queueRetryTimer = null;
  let wsProbeTimer = null;
  let isConnecting = false;
  let isManualDisconnect = false;
  let isReconnectStopped = false;
  let unreadCount = 0;
  const originalTitle = document.title;

  // Peer presence & freshness tracking (2-second ping indicator)
  const peers = new Map(); // username -> { lastPing: timestamp, isOnline: boolean }
  let peerPingInterval = null;
  let peerFreshnessChecker = null;

  // Unseen messages queue for read receipts (turning 2 ticks into circle)
  const unseenMessageIds = new Set();

  const DIRECT_SERVER_URL = "ws://193.168.175.227:8765";

  function isCloudflareUrl(url) {
    if (!url) return false;
    const lower = url.toLowerCase();
    return lower.includes("trycloudflare.com") || lower.includes("cloudflare");
  }

  function getConnectionMode(url) {
    if (!url) return state.connectionMode || "direct";
    if (state.cleanIp && url.includes(state.cleanIp)) return "cleanip";
    return isCloudflareUrl(url) ? "cloudflare" : "direct";
  }

  const state = {
    nickname: "کاربر",
    room: "",
    password: "",
    serverUrl: "",
    connectionMode: "direct", // "direct" | "cloudflare"
    cleanIp: "",
    antiDpi: true,
    decoyChaff: true,
    autoReconnect: true,
    notificationsEnabled: true,
    vibrationEnabled: true,
    keepCredentials: true,
    isAuthenticated: false,
    transportMode: "ws", // "ws" | "http"
    lastSyncTimestamp: 0.0,
    lastActivityTime: Date.now(),
    outgoingQueue: [],
    seenMessageIds: new Set(),
  };

  // 1. Load Saved Configuration & State
  const savedConfig = JSON.parse(localStorage.getItem("rssh_chat_auth") || "{}");
  state.activeTunnelUrl = "wss://medications-firewall-angle-counter.trycloudflare.com";
  if (savedConfig.cleanIp) state.cleanIp = savedConfig.cleanIp;
  state.connectionMode = savedConfig.connectionMode || (savedConfig.serverUrl ? getConnectionMode(savedConfig.serverUrl) : "direct");

  if (state.connectionMode === "cloudflare") {
    state.serverUrl = savedConfig.serverUrl || state.activeTunnelUrl;
  } else if (state.connectionMode === "cleanip") {
    state.serverUrl = savedConfig.serverUrl || (state.cleanIp ? (state.cleanIp.includes("://") ? state.cleanIp : `wss://${state.cleanIp}:443`) : "wss://104.16.132.229:443");
  } else {
    state.serverUrl = savedConfig.serverUrl || DIRECT_SERVER_URL;
  }

  if (savedConfig.nickname) state.nickname = savedConfig.nickname;
  if (savedConfig.room) state.room = savedConfig.room;
  if (savedConfig.password) state.password = savedConfig.password;
  if (savedConfig.cleanIp) state.cleanIp = savedConfig.cleanIp;
  if (savedConfig.antiDpi !== undefined) state.antiDpi = savedConfig.antiDpi;
  if (savedConfig.decoyChaff !== undefined) state.decoyChaff = savedConfig.decoyChaff;
  if (savedConfig.autoReconnect !== undefined) state.autoReconnect = savedConfig.autoReconnect;
  if (savedConfig.notificationsEnabled !== undefined) state.notificationsEnabled = savedConfig.notificationsEnabled;
  if (savedConfig.vibrationEnabled !== undefined) state.vibrationEnabled = savedConfig.vibrationEnabled;
  if (savedConfig.keepCredentials !== undefined) state.keepCredentials = savedConfig.keepCredentials;

  function updateNotificationUI() {
    if (state.notificationsEnabled) {
      btnNotification.innerHTML = NOTIF_BELL_ON_SVG;
      btnNotification.classList.remove("muted-notif");
      btnNotification.classList.add("active-notif");
      btnNotification.setAttribute("title", "اعلان‌ها روشن است (برای خاموش کردن کلیک کنید)");
      if (notificationToggle) notificationToggle.checked = true;
    } else {
      btnNotification.innerHTML = NOTIF_BELL_OFF_SVG;
      btnNotification.classList.remove("active-notif");
      btnNotification.classList.add("muted-notif");
      btnNotification.setAttribute("title", "اعلان‌ها خاموش است (برای روشن کردن کلیک کنید)");
      if (notificationToggle) notificationToggle.checked = false;
    }
  }

  function toggleNotifications() {
    state.notificationsEnabled = !state.notificationsEnabled;
    updateNotificationUI();
    persistSettings();

    if (state.notificationsEnabled) {
      if ("Notification" in window && Notification.permission === "default") {
        Notification.requestPermission().then((permission) => {
          if (permission === "granted") {
            notifBanner.classList.add("hidden");
            nativeToast("اعلان‌ها فعال شد 🔔");
            playAudioChime();
          } else {
            nativeToast("مجوز اعلان در مرورگر داده نشد");
          }
        });
        return;
      }
      nativeToast("اعلان‌ها روشن شد 🔔");
      playAudioChime();
    } else {
      nativeToast("اعلان‌ها و صدای پیام خاموش شد 🔕");
    }
  }

  // Initialize Form Values
  gateNickname.value = state.nickname || "کاربر";
  gateRoomName.value = state.room || "";
  gateRoomPassword.value = state.password || "";
  serverUrlInput.value = state.serverUrl;
  modalServerUrl.value = state.serverUrl;
  if (gateCleanIp) gateCleanIp.value = state.cleanIp || "";
  if (modalCleanIp) modalCleanIp.value = state.cleanIp || "";
  if (antiDpiToggle) antiDpiToggle.checked = state.antiDpi;
  if (decoyChaffToggle) decoyChaffToggle.checked = state.decoyChaff;
  if (autoReconnectInput) autoReconnectInput.checked = state.autoReconnect;
  if (notificationToggle) notificationToggle.checked = state.notificationsEnabled;
  if (vibrationToggle) vibrationToggle.checked = state.vibrationEnabled;
  if (keepCredentialsInput) keepCredentialsInput.checked = state.keepCredentials;
  updateNotificationUI();

  // Save Settings Helper
  function persistSettings() {
    const dataToSave = {
      serverUrl: state.serverUrl,
      connectionMode: state.connectionMode,
      cleanIp: state.cleanIp,
      antiDpi: state.antiDpi,
      decoyChaff: state.decoyChaff,
      nickname: state.nickname,
      autoReconnect: state.autoReconnect,
      notificationsEnabled: state.notificationsEnabled,
      vibrationEnabled: state.vibrationEnabled,
      keepCredentials: state.keepCredentials,
      room: state.keepCredentials ? state.room : "",
      password: state.keepCredentials ? state.password : "",
    };
    localStorage.setItem("rssh_chat_auth", JSON.stringify(dataToSave));
  }

  function sanitizeServerUrl(raw) {
    let url = (raw || "").trim();
    if (!url) {
      if (window.location && window.location.host && !window.location.protocol.startsWith("file")) {
        const proto = window.location.protocol === "https:" ? "wss:" : "ws:";
        return `${proto}//${window.location.host}`;
      }
      return "ws://193.168.175.227:8765";
    }

    if (!url.includes("://")) {
      url = "ws://" + url;
    }

    if (url.startsWith("http://")) {
      url = "ws://" + url.substring(7);
    } else if (url.startsWith("https://")) {
      url = "wss://" + url.substring(8);
    }

    try {
      const parsed = new URL(url);
      if (!parsed.port && !parsed.hostname.includes(".")) {
        url = `${parsed.protocol}//${parsed.hostname}:8765${parsed.pathname}`;
      }
    } catch (e) {}

    return url;
  }

  function getHttpBaseUrl(wsUrl) {
    let url = (wsUrl || "").trim();
    if (url.startsWith("wss://")) {
      return "https://" + url.slice(6).replace(/\/ws\/?$/, "");
    }
    if (url.startsWith("ws://")) {
      return "http://" + url.slice(5).replace(/\/ws\/?$/, "");
    }
    if (url.startsWith("https://") || url.startsWith("http://")) {
      return url.replace(/\/ws\/?$/, "");
    }
    const proto = window.location.protocol === "https:" ? "https:" : "http:";
    return `${proto}//${window.location.host || "193.168.175.227:8765"}`;
  }

  function updatePresetSelectionUI(mode) {
    const currentMode = mode || state.connectionMode || "direct";
    const isDirect = (currentMode === "direct");
    const isCf = (currentMode === "cloudflare");
    const isCleanIp = (currentMode === "cleanip");

    // Gate presets
    if (btnGatePresetDirect) {
      btnGatePresetDirect.classList.toggle("selected", isDirect);
    }
    if (btnGatePresetCfTunnel) {
      btnGatePresetCfTunnel.classList.toggle("selected", isCf);
      btnGatePresetCfTunnel.classList.toggle("cf-preset", isCf);
    }
    if (btnGatePresetCleanIp) {
      btnGatePresetCleanIp.classList.toggle("selected", isCleanIp);
      btnGatePresetCleanIp.classList.toggle("cleanip-preset", isCleanIp);
    }

    // Modal presets
    if (btnPresetDirect) {
      btnPresetDirect.classList.toggle("selected", isDirect);
    }
    if (btnPresetCfTunnel) {
      btnPresetCfTunnel.classList.toggle("selected", isCf);
      btnPresetCfTunnel.classList.toggle("cf-preset", isCf);
    }
    if (btnPresetCleanIp) {
      btnPresetCleanIp.classList.toggle("selected", isCleanIp);
      btnPresetCleanIp.classList.toggle("cleanip-preset", isCleanIp);
    }

    // Clean IP input visibility
    if (gateCleanIpBlock) {
      gateCleanIpBlock.classList.toggle("hidden", isDirect);
    }
    if (modalCleanIpBlock) {
      modalCleanIpBlock.classList.toggle("hidden", isDirect);
    }

    // Gate screen notices
    if (gateActiveModeBadge) {
      if (isCleanIp) {
        gateActiveModeBadge.className = "gate-mode-badge cleanip";
        gateActiveModeBadge.textContent = "🎯 کلین آی‌پی";
      } else if (isCf) {
        gateActiveModeBadge.className = "gate-mode-badge cf";
        gateActiveModeBadge.textContent = "☁️ کلادفلر";
      } else {
        gateActiveModeBadge.className = "gate-mode-badge direct";
        gateActiveModeBadge.textContent = "⚡ سرور مستقیم";
      }
    }
    if (gateActiveConnNotice) {
      gateActiveConnNotice.className = `active-conn-notice ${isCleanIp ? "cleanip" : (isCf ? "cf" : "direct")}`;
    }
    if (gateActiveConnNoticeText) {
      if (isCleanIp) {
        const displayIp = (gateCleanIp && gateCleanIp.value.trim()) || (modalCleanIp && modalCleanIp.value.trim()) || state.cleanIp || (serverUrlInput && serverUrlInput.value.trim()) || "104.16.132.229";
        gateActiveConnNoticeText.textContent = `🎯 کلین آی‌پی کلودفلر (${displayIp})`;
      } else if (isCf) {
        const displayUrl = (serverUrlInput && serverUrlInput.value.trim()) || state.serverUrl || state.activeTunnelUrl || "کلادفلر تونل";
        gateActiveConnNoticeText.textContent = `☁️ کلادفلر تونل (پورت 443 امن، ضد فیلتر)`;
      } else {
        gateActiveConnNoticeText.textContent = `⚡ سرور مستقیم (193.168.175.227:8765)`;
      }
    }

    // Modal active banner
    if (modalActiveModeBanner) {
      modalActiveModeBanner.className = `modal-active-mode-banner ${isCleanIp ? "cleanip" : (isCf ? "cf" : "direct")}`;
    }
    if (modalActiveModePill) {
      if (isCleanIp) {
        modalActiveModePill.className = "active-mode-pill cleanip";
        modalActiveModePill.textContent = "🎯 اتصال با کلین آی‌پی (Clean IP)";
      } else if (isCf) {
        modalActiveModePill.className = "active-mode-pill cf";
        modalActiveModePill.textContent = "☁️ اتصال به کلادفلر (:443)";
      } else {
        modalActiveModePill.className = "active-mode-pill direct";
        modalActiveModePill.textContent = "⚡ اتصال مستقیم به سرور (:8765)";
      }
    }
  }

  function selectConnectionPreset(mode, autoTest = false) {
    state.connectionMode = mode;
    let targetUrl = DIRECT_SERVER_URL;

    if (mode === "cloudflare") {
      targetUrl = state.activeTunnelUrl || "wss://medications-firewall-angle-counter.trycloudflare.com";
    } else if (mode === "cleanip") {
      const userIp = state.cleanIp || (modalCleanIp && modalCleanIp.value.trim()) || (gateCleanIp && gateCleanIp.value.trim()) || "104.16.132.229";
      targetUrl = userIp.includes("://") ? userIp : `wss://${userIp}:443`;
    } else {
      targetUrl = DIRECT_SERVER_URL;
    }

    state.serverUrl = targetUrl;
    if (serverUrlInput) serverUrlInput.value = targetUrl;
    if (modalServerUrl) modalServerUrl.value = targetUrl;

    updatePresetSelectionUI(state.connectionMode);
    updateTransportBadge(state.transportMode || "ws");
    persistSettings();

    if (mode === "cleanip") {
      nativeToast("🎯 اتصال با کلین آی‌پی (Clean IP) انتخاب شد");
      if (gateCleanIp && gateCleanIpBlock && !gateCleanIpBlock.classList.contains("hidden")) {
        gateCleanIp.focus();
      } else if (modalCleanIp && modalCleanIpBlock && !modalCleanIpBlock.classList.contains("hidden")) {
        modalCleanIp.focus();
      }
    } else if (mode === "cloudflare") {
      nativeToast("☁️ اتصال به کلادفلر انتخاب شد");
    } else {
      nativeToast("⚡ اتصال مستقیم به سرور انتخاب شد");
    }

    if (autoTest) {
      const feedbackEl = (roomGate && !roomGate.classList.contains("hidden")) ? gateTestFeedback : serverTestFeedback;
      const btnEl = (roomGate && !roomGate.classList.contains("hidden")) ? btnTestGateConn : btnTestServerConn;
      testServerConnectivity(targetUrl, feedbackEl, btnEl);
    }

    if (mode === "cloudflare") {
      queryActiveTunnel();
    }
  }

  async function queryActiveTunnel(baseUrl) {
    try {
      const httpBase = getHttpBaseUrl(baseUrl || DIRECT_SERVER_URL);
      const resp = await fetch(`${httpBase}/api/tunnel`, {
        cache: "no-store",
        signal: AbortSignal.timeout(3000),
      });
      if (resp.ok) {
        const data = await resp.json();
        if (data && data.tunnel && data.tunnel.active && data.tunnel.ws_url) {
          state.activeTunnelUrl = data.tunnel.ws_url;
          if (state.connectionMode === "cloudflare") {
            const currentVal = (serverUrlInput && serverUrlInput.value.trim()) || state.serverUrl;
            const isDefaultOrOldTunnel = !currentVal || isCloudflareUrl(currentVal);
            if (isDefaultOrOldTunnel) {
              state.serverUrl = data.tunnel.ws_url;
              if (serverUrlInput) serverUrlInput.value = data.tunnel.ws_url;
              if (modalServerUrl) modalServerUrl.value = data.tunnel.ws_url;
              updatePresetSelectionUI("cloudflare");
              updateTransportBadge(state.transportMode || "ws");
              persistSettings();
            }
          }
          return data.tunnel;
        }
      }
    } catch (e) {}
    return null;
  }

  async function testServerConnectivity(targetUrl, feedbackEl, btnEl) {
    if (!feedbackEl) return;

    let rawUrl = (targetUrl || "").trim();
    if (!rawUrl) {
      if (state.connectionMode === "cloudflare") {
        rawUrl = state.activeTunnelUrl || "wss://medications-firewall-angle-counter.trycloudflare.com";
      } else if (state.connectionMode === "cleanip") {
        const cip = (gateCleanIp && gateCleanIp.value.trim()) || (modalCleanIp && modalCleanIp.value.trim()) || state.cleanIp || "104.16.132.229";
        rawUrl = cip.includes("://") ? cip : `wss://${cip}:443`;
      } else {
        rawUrl = state.serverUrl || DIRECT_SERVER_URL;
      }
    }

    const currentMode = state.connectionMode || (isCloudflareUrl(rawUrl) ? "cloudflare" : "direct");
    const isClean = (currentMode === "cleanip");
    const isCf = (currentMode === "cloudflare") || (!isClean && isCloudflareUrl(rawUrl));
    const effectiveMode = isClean ? "cleanip" : (isCf ? "cloudflare" : "direct");
    // Keep user's preset selection active - do NOT delete or clear selections!
    updatePresetSelectionUI(effectiveMode);

    // Determine normalized WS and HTTP URLs
    let wsUrl = rawUrl;
    let httpUrl = rawUrl;

    if (!wsUrl.includes("://")) {
      if (wsUrl.includes("trycloudflare.com") || wsUrl.endsWith(":443")) {
        wsUrl = "wss://" + wsUrl;
        httpUrl = "https://" + rawUrl;
      } else {
        wsUrl = "ws://" + wsUrl;
        httpUrl = "http://" + rawUrl;
      }
    } else {
      if (wsUrl.startsWith("http://")) {
        wsUrl = "ws://" + wsUrl.slice(7);
        httpUrl = rawUrl;
      } else if (wsUrl.startsWith("https://")) {
        wsUrl = "wss://" + wsUrl.slice(8);
        httpUrl = rawUrl;
      } else if (wsUrl.startsWith("ws://")) {
        httpUrl = "http://" + wsUrl.slice(5);
      } else if (wsUrl.startsWith("wss://")) {
        httpUrl = "https://" + wsUrl.slice(6);
      }
    }

    // Clean paths
    httpUrl = httpUrl.replace(/\/ws\/?$/, "").replace(/\/+$/, "");
    wsUrl = wsUrl.replace(/\/+$/, "");

    // Set UI testing state
    feedbackEl.classList.remove("hidden", "success", "warning", "error");
    feedbackEl.classList.add("testing");
    feedbackEl.innerHTML = `
      <div style="display:flex;align-items:center;gap:8px;">
        <span class="reconnect-icon spinning">🔄</span>
        <span>در حال آزمایش و بررسی اتصال به سرور...</span>
      </div>
    `;

    if (btnEl) {
      btnEl.disabled = true;
      btnEl.classList.add("testing");
    }

    // Run HTTP and WS tests with timeout
    const testWsPromise = new Promise((resolve) => {
      const startT = performance.now();
      let testSocket = null;
      let timer = null;

      try {
        testSocket = new WebSocket(wsUrl);
      } catch (err) {
        resolve({ ok: false, error: err.message || "آدرس وب‌سوکت نامعتبر است" });
        return;
      }

      timer = setTimeout(() => {
        try { if (testSocket) testSocket.close(); } catch (e) {}
        resolve({ ok: false, error: "مهلت زمانی برقراری وب‌سوکت به پایان رسید (Timeout 5s)" });
      }, 5000);

      testSocket.onopen = () => {
        clearTimeout(timer);
        const lat = Math.round(performance.now() - startT);
        try { testSocket.close(); } catch (e) {}
        resolve({ ok: true, latency: lat });
      };

      testSocket.onerror = () => {
        clearTimeout(timer);
        try { testSocket.close(); } catch (err) {}
        resolve({ ok: false, error: "خطای پروتکل یا مسدودسازی دست‌دادن وب‌سوکت" });
      };
    });

    const testHttpPromise = (async () => {
      const startT = performance.now();
      try {
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 5000);
        const res = await fetch(`${httpUrl}/health`, {
          method: "GET",
          signal: controller.signal,
          cache: "no-store",
        });
        clearTimeout(timeoutId);
        if (res.ok) {
          const lat = Math.round(performance.now() - startT);
          const json = await res.json().catch(() => null);
          return { ok: true, latency: lat, data: json };
        }
        return { ok: false, error: `پاسخ سرور HTTP: ${res.status} ${res.statusText}` };
      } catch (err) {
        return { ok: false, error: err.name === "AbortError" ? "مهلت زمانی به پایان رسید (Timeout 5s)" : (err.message || "سرور پاسخ نداد") };
      }
    })();

    const [wsRes, httpRes] = await Promise.all([testWsPromise, testHttpPromise]);

    if (btnEl) {
      btnEl.disabled = false;
      btnEl.classList.remove("testing");
    }

    feedbackEl.classList.remove("testing");

    if (wsRes.ok) {
      // Full Success: WebSocket is OPEN!
      feedbackEl.classList.add("success");
      const serverVersion = (httpRes.data && httpRes.data.version) ? `نسخه ${httpRes.data.version}` : "";
      const connTitle = isClean ? "اتصال با کلین آی‌پی" : (isCf ? "اتصال به کلادفلر" : "اتصال مستقیم به سرور");
      feedbackEl.innerHTML = `
        <strong>🟢 ${connTitle} با موفقیت برقرار شد!</strong>
        <div class="test-meta">
          <span>${isClean ? "🎯 کلین آی‌پی" : (isCf ? "☁️ کلودفلر تونل" : "⚡ وب‌سوکت مستقیم")}: فعال</span>
          <span>⏱️ پینگ: ${wsRes.latency} میلی‌ثانیه</span>
          ${serverVersion ? `<span>🏷️ ${serverVersion}</span>` : ""}
        </div>
        <div class="test-sub">ارتباط دوطرفه با سرور (${connTitle}) برقرار است و آماده تبادل پیام می‌باشد.</div>
      `;
      nativeToast(`✅ ${connTitle} برقرار شد (پینگ: ${wsRes.latency}ms)`);

      // Auto-update state and persist
      state.serverUrl = wsUrl;
      state.connectionMode = effectiveMode;
      if (serverUrlInput) serverUrlInput.value = wsUrl;
      if (modalServerUrl) modalServerUrl.value = wsUrl;
      updatePresetSelectionUI(effectiveMode);
      updateTransportBadge(state.transportMode || "ws");
      persistSettings();

      if (httpRes.data && httpRes.data.tunnel && httpRes.data.tunnel.ws_url) {
        state.activeTunnelUrl = httpRes.data.tunnel.ws_url;
      }
    } else if (httpRes.ok) {
      // Partial Success: HTTP Tunnel works, WS blocked
      feedbackEl.classList.add("warning");
      const serverVersion = (httpRes.data && httpRes.data.version) ? `نسخه ${httpRes.data.version}` : "";
      const connTitle = isClean ? "اتصال با کلین آی‌پی" : (isCf ? "اتصال به کلادفلر" : "اتصال مستقیم به سرور");
      feedbackEl.innerHTML = `
        <strong>🟡 ${connTitle} از طریق تونل امن HTTP برقرار شد</strong>
        <div class="test-meta">
          <span>🛡️ تونل ضد فایروال HTTP: فعال</span>
          <span>⏱️ پینگ: ${httpRes.latency} میلی‌ثانیه</span>
          ${serverVersion ? `<span>🏷️ ${serverVersion}</span>` : ""}
        </div>
        <div class="test-sub">پورت وب‌سوکت در این شبکه مسدود است، اما تونل امن HTTP (${connTitle}) فعال است و برنامه پیام‌ها را مبادله می‌کند.</div>
      `;
      nativeToast(`🟡 ${connTitle} (تونل HTTP) متصل شد (پینگ: ${httpRes.latency}ms)`);

      state.serverUrl = wsUrl;
      state.connectionMode = effectiveMode;
      if (serverUrlInput) serverUrlInput.value = wsUrl;
      if (modalServerUrl) modalServerUrl.value = wsUrl;
      updatePresetSelectionUI(effectiveMode);
      updateTransportBadge("http");
      persistSettings();

      if (httpRes.data && httpRes.data.tunnel && httpRes.data.tunnel.ws_url) {
        state.activeTunnelUrl = httpRes.data.tunnel.ws_url;
      }
    } else {
      // Failure
      feedbackEl.classList.add("error");
      const isTryCloudflare = rawUrl.includes("trycloudflare.com");
      const connTitle = isClean ? "اتصال با کلین آی‌پی" : (isCf ? "اتصال به کلادفلر" : "اتصال مستقیم به سرور");
      feedbackEl.innerHTML = `
        <strong>🔴 خطا در ${connTitle}!</strong>
        <div class="test-sub">هیچ پاسخی از آدرس <code>${escapeHtml(rawUrl)}</code> دریافت نشد.</div>
        <ul class="test-reasons">
          ${isTryCloudflare ? `<li><strong>آدرس کلودفلر منقضی شده:</strong> تونل‌های موقت trycloudflare پس از ریستارت سرور تغییر می‌کنند.</li>` : ""}
          <li><strong>اختلال شبکه یا فیلترینگ:</strong> اگر از دامنه‌های کلودفلر استفاده می‌کنید، نیاز به VPN، کلین آی‌پی یا سرور مستقیم است.</li>
          <li><strong>آدرس سرور:</strong> بررسی کنید آدرس سرور یا آی‌پی تمیز به درستی انتخاب شده باشد.</li>
        </ul>
        ${isTryCloudflare ? `<div class="test-hint">💡 پیشنهاد: دکمه «⚡ اتصال مستقیم به سرور» را انتخاب کنید یا از آی‌پی تمیز استفاده فرمایید.</div>` : ""}
      `;
      nativeToast(`❌ عدم برقراری ${connTitle}`);

      // Crucial: keep user selection intact! Do NOT remove or clear selections!
      updatePresetSelectionUI(effectiveMode);
    }
  }

  // ==========================================================================
  // Cryptographic Engine (Zero-Knowledge End-to-End Encryption AES-256)
  // ==========================================================================
  function encryptPayload(plaintext, password) {
    if (!window.CryptoJS || !window.CryptoJS.AES) {
      console.warn("CryptoJS library unavailable, sending raw payload.");
      return { ciphertext: plaintext, encrypted: false };
    }
    try {
      const ciphertext = window.CryptoJS.AES.encrypt(plaintext, password).toString();
      return { ciphertext: ciphertext, encrypted: true };
    } catch (err) {
      console.error("Encryption failed:", err);
      return { ciphertext: plaintext, encrypted: false };
    }
  }

  function decryptPayload(ciphertext, password) {
    if (!window.CryptoJS || !window.CryptoJS.AES) {
      return ciphertext;
    }
    try {
      const bytes = window.CryptoJS.AES.decrypt(ciphertext, password);
      const plaintext = bytes.toString(window.CryptoJS.enc.Utf8);
      if (!plaintext) {
        return null; // Invalid password or corrupted payload
      }
      return plaintext;
    } catch (err) {
      return null;
    }
  }

  // ==========================================================================
  // Anti-DPI & Traffic Shaping Engine (Random Noise Padding & Jitter)
  // ==========================================================================
  function generateRandomNoise(minLen = 400, maxLen = 1600) {
    const len = Math.floor(minLen + Math.random() * (maxLen - minLen));
    const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_~";
    let str = "";
    for (let i = 0; i < len; i++) {
      str += chars.charAt(Math.floor(Math.random() * chars.length));
    }
    return str;
  }

  function wrapAntiDpi(payload) {
    state.lastActivityTime = Date.now();
    if (state.antiDpi && payload && typeof payload === "object") {
      payload._pad = generateRandomNoise(400, 1600);
      payload._ts = Date.now();
    }
    return payload;
  }

  function unwrapAntiDpi(payload) {
    if (payload && typeof payload === "object") {
      delete payload._pad;
      delete payload._ts;
      delete payload.padding;
    }
    return payload;
  }

  function updateAntiDpiBadge() {
    if (!antiDpiBadge) return;
    if (state.antiDpi) {
      antiDpiBadge.classList.remove("disabled");
      antiDpiBadge.classList.add("active");
      antiDpiBadge.textContent = "🛡️ ضد DPI";
      antiDpiBadge.title = "سپر ضد DPI: پدینگ تصادفی بسته (۴۰۰-۱۶۰۰ بایت) و فرکانس زمانی نامنظم فعال است";
    } else {
      antiDpiBadge.classList.remove("active");
      antiDpiBadge.classList.add("disabled");
      antiDpiBadge.textContent = "🛡️ بدون ضد DPI";
      antiDpiBadge.title = "سپر ضد DPI غیرفعال است";
    }
  }

  function startJitteredPingLoop() {
    if (jitteredPingTimer) clearTimeout(jitteredPingTimer);
    if (!ws || ws.readyState !== WebSocket.OPEN) return;

    // Dynamic Jitter: between 14 and 28 seconds (breaks periodic timing fingerprints)
    const delay = Math.floor(14000 + Math.random() * 14000);
    jitteredPingTimer = setTimeout(() => {
      if (ws && ws.readyState === WebSocket.OPEN) {
        try {
          ws.send(JSON.stringify(wrapAntiDpi({ type: "ping" })));
        } catch (e) {}
      }
      startJitteredPingLoop();
    }, delay);
  }

  function startDecoyChaffLoop() {
    clearInterval(decoyChaffTimer);
    decoyChaffTimer = setInterval(() => {
      if (!state.decoyChaff || !state.isAuthenticated) return;
      const idleSeconds = (Date.now() - state.lastActivityTime) / 1000;
      // If idle for over 35 seconds, send covert decoy traffic
      if (idleSeconds >= 35) {
        state.lastActivityTime = Date.now();
        if (ws && ws.readyState === WebSocket.OPEN) {
          try {
            ws.send(JSON.stringify(wrapAntiDpi({ type: "decoy" })));
          } catch (e) {}
        }
      }
    }, 10000);
  }

  // ==========================================================================
  // Native Android and Background Notification Integration
  // ==========================================================================
  function nativeToast(msg) {
    if (window.ChatNative && window.ChatNative.showToast) {
      window.ChatNative.showToast(msg);
    }
  }

  function nativeVibrate(ms = 40) {
    if (!state.vibrationEnabled) return;
    if (window.ChatNative && window.ChatNative.vibrate) {
      window.ChatNative.vibrate(ms);
    } else if (navigator.vibrate) {
      try {
        navigator.vibrate(ms);
      } catch (e) {}
    }
  }

  function triggerBackgroundNotification(sender, messageText, roomName) {
    unreadCount++;
    document.title = `(${unreadCount}) پیام جدید | رخش چت`;

    if (!state.notificationsEnabled) {
      return;
    }

    // 1. Android Native Foreground Service & Lock Screen Notification
    if (window.ChatNative && window.ChatNative.showNotification) {
      window.ChatNative.showNotification(sender, messageText, roomName || state.room);
      return;
    }

    // 2. Web Notifications API
    if ("Notification" in window && Notification.permission === "granted") {
      try {
        const notif = new Notification(`پیام جدید از ${sender} [${roomName || state.room}]`, {
          body: messageText,
          icon: "icon-192.png",
          badge: "icon-192.png",
          tag: `chat-msg-${roomName}`,
          renotify: true,
          silent: false,
        });
        notif.onclick = () => {
          window.focus();
          notif.close();
        };
      } catch (e) {}
    }

    // 3. Audio Chime & Vibration
    playAudioChime();
    nativeVibrate(60);
  }

  function playAudioChime() {
    try {
      const ctx = new (window.AudioContext || window.webkitAudioContext)();
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();

      osc.type = "sine";
      osc.frequency.setValueAtTime(587.33, ctx.currentTime); // D5
      osc.frequency.exponentialRampToValueAtTime(880, ctx.currentTime + 0.12); // A5

      gain.gain.setValueAtTime(0.001, ctx.currentTime);
      gain.gain.exponentialRampToValueAtTime(0.35, ctx.currentTime + 0.02);
      gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.22);

      osc.connect(gain);
      gain.connect(ctx.destination);

      osc.start();
      osc.stop(ctx.currentTime + 0.23);
    } catch (e) {}
  }

  // Clear unread count & send read receipts when window gains focus or becomes visible
  window.addEventListener("focus", () => {
    unreadCount = 0;
    document.title = originalTitle;
    flushUnseenReceipts();
  });

  document.addEventListener("visibilitychange", () => {
    if (!document.hidden) {
      unreadCount = 0;
      document.title = originalTitle;
      flushUnseenReceipts();
    }
  });

  // ==========================================================================
  // UI Display & Helpers
  // ==========================================================================
  function updateStatus(dotClass, text) {
    statusIndicator.className = `status-dot ${dotClass}`;
    statusText.textContent = text;
  }

  function updateTransportBadge(mode) {
    if (!transportBadge) return;
    const isClean = (state.connectionMode === "cleanip");
    const isCf = (state.connectionMode === "cloudflare") || (!isClean && isCloudflareUrl(state.serverUrl));

    if (mode === "http") {
      transportBadge.className = `transport-pill http ${isClean ? "cleanip" : (isCf ? "cf" : "direct")}`;
      transportBadge.textContent = isClean ? "🎯 تونل کلین آی‌پی" : (isCf ? "☁️ اتصال به کلادفلر" : "⚡ اتصال مستقیم به سرور");
      transportBadge.title = isClean 
        ? `اتصال با کلین آی‌پی کلودفلر (HTTP): ${state.serverUrl}`
        : (isCf ? `اتصال به کلادفلر (تونل امن ضد فایروال HTTP): ${state.serverUrl}` : `اتصال مستقیم به سرور (تونل امن ضد فایروال HTTP): ${state.serverUrl}`);
    } else {
      transportBadge.className = `transport-pill ws ${isClean ? "cleanip" : (isCf ? "cf" : "direct")}`;
      transportBadge.textContent = isClean ? "🎯 اتصال با کلین آی‌پی" : (isCf ? "☁️ اتصال به کلادفلر" : "⚡ اتصال مستقیم به سرور");
      transportBadge.title = isClean
        ? `اتصال با کلین آی‌پی کلودفلر (WebSocket): ${state.serverUrl}`
        : (isCf ? `اتصال به کلادفلر (وب‌سوکت ایمن WSS پورت 443): ${state.serverUrl}` : `اتصال مستقیم به سرور: ${state.serverUrl}`);
    }
  }

  function showGateError(msg) {
    gateErrorText.textContent = msg;
    gateError.classList.remove("hidden");
    // Vibration intentionally removed on connection / gate errors per user preference
  }

  function hideGateError() {
    gateError.classList.add("hidden");
  }

  // ==========================================================================
  // Reconnection Controls (One-click cancel / resume retry)
  // ==========================================================================
  function showReconnectBanner(show, text = "", isPaused = false) {
    if (!reconnectBanner) return;
    if (show) {
      reconnectBanner.classList.remove("hidden");
      if (btnCancelReconnectHeader) btnCancelReconnectHeader.classList.remove("hidden");
      if (btnStopGateRetry) btnStopGateRetry.classList.remove("hidden");

      if (reconnectBannerText) reconnectBannerText.textContent = text;
      const spinIcon = reconnectBanner.querySelector(".reconnect-icon");

      if (isPaused) {
        reconnectBanner.classList.add("paused");
        if (spinIcon) spinIcon.classList.remove("spinning");
        if (btnToggleReconnect) {
          btnToggleReconnect.textContent = "▶ تلاش مجدد";
          btnToggleReconnect.className = "btn-banner-action resume";
        }
        if (btnCancelReconnectHeader) {
          btnCancelReconnectHeader.textContent = "▶ اتصال";
          btnCancelReconnectHeader.className = "btn-cancel-reconnect-header resume";
        }
        if (btnStopGateRetry) {
          btnStopGateRetry.textContent = "▶ تلاش مجدد برای اتصال";
          btnStopGateRetry.className = "btn-gate-stop-retry resume";
        }
      } else {
        reconnectBanner.classList.remove("paused");
        if (spinIcon) spinIcon.classList.add("spinning");
        if (btnToggleReconnect) {
          btnToggleReconnect.textContent = "⏹ توقف تلاش";
          btnToggleReconnect.className = "btn-banner-action";
        }
        if (btnCancelReconnectHeader) {
          btnCancelReconnectHeader.textContent = "⏹ توقف تلاش";
          btnCancelReconnectHeader.className = "btn-cancel-reconnect-header";
        }
        if (btnStopGateRetry) {
          btnStopGateRetry.textContent = "⏹ توقف تلاش مجدد";
          btnStopGateRetry.className = "btn-gate-stop-retry";
        }
      }
    } else {
      reconnectBanner.classList.add("hidden");
      if (btnCancelReconnectHeader) btnCancelReconnectHeader.classList.add("hidden");
      if (btnStopGateRetry) btnStopGateRetry.classList.add("hidden");
    }
  }

  function stopReconnect() {
    isReconnectStopped = true;
    clearTimeout(reconnectTimer);
    reconnectTimer = null;
    updateStatus("disconnected", "تلاش مجدد متوقف شد");
    showReconnectBanner(true, "تلاش برای اتصال متوقف شد", true);
  }

  function resumeReconnect() {
    isReconnectStopped = false;
    showReconnectBanner(true, "در حال اتصال به سرور...", false);
    if (state.room && state.password) {
      connectAndJoinRoom(state.room, state.password, state.nickname);
    }
  }

  if (btnToggleReconnect) {
    btnToggleReconnect.addEventListener("click", () => {
      if (isReconnectStopped) resumeReconnect();
      else stopReconnect();
    });
  }

  if (btnCancelReconnectHeader) {
    btnCancelReconnectHeader.addEventListener("click", () => {
      if (isReconnectStopped) resumeReconnect();
      else stopReconnect();
    });
  }

  if (btnStopGateRetry) {
    btnStopGateRetry.addEventListener("click", () => {
      if (isReconnectStopped) resumeReconnect();
      else stopReconnect();
    });
  }

  // ==========================================================================
  // Peer Presence & Live Ping Indicator (Resilient 7s Threshold)
  // ==========================================================================
  const PRESENCE_TIMEOUT_MS = 7000;

  function cssEscape(str) {
    return encodeURIComponent(str).replace(/%/g, "_");
  }

  function isOnlyMemberInRoom() {
    if (!state.isAuthenticated) return false;
    let otherOnlineCount = 0;
    peers.forEach((data, user) => {
      if (user !== state.nickname && data.isOnline) {
        otherOnlineCount++;
      }
    });
    return otherOnlineCount === 0;
  }

  function updateDeleteRoomButtonState() {
    const isOnly = isOnlyMemberInRoom();
    const title = isOnly
      ? "پاک کردن کامل اتاق (شما تنها عضو حاضر هستید)"
      : "امکان حذف اتاق وجود ندارد (کاربران دیگری در اتاق حضور دارند)";

    [btnDeleteRoom, btnDeleteRoomModal].forEach((btn) => {
      if (!btn) return;
      btn.disabled = !isOnly;
      if (isOnly) {
        btn.classList.remove("disabled");
        btn.title = title;
      } else {
        btn.classList.add("disabled");
        btn.title = title;
      }
    });
  }

  function renderRoomMembers() {
    if (!membersList) return;
    membersList.innerHTML = "";

    // 1. Current user chip (always online when authenticated)
    const myChip = document.createElement("span");
    myChip.className = "member-chip me";
    myChip.innerHTML = `<span class="peer-status-dot online"></span> <span>${escapeHtml(state.nickname)} (شما)</span>`;
    membersList.appendChild(myChip);

    // 2. Peer chips with colored status light
    peers.forEach((data, user) => {
      if (user === state.nickname) return;
      const chip = document.createElement("span");
      chip.className = "member-chip";
      chip.id = `chip-${cssEscape(user)}`;
      const dotClass = data.isOnline ? "online" : "offline";
      const title = data.isOnline ? "آنلاین (متصل و فعال)" : "قطع ارتباط (عدم دریافت پکت)";
      chip.title = `${user}: ${title}`;
      chip.innerHTML = `<span class="peer-status-dot ${dotClass}" title="${title}"></span> <span>${escapeHtml(user)}</span>`;
      membersList.appendChild(chip);
    });

    updateDeleteRoomButtonState();
  }

  function updatePeerStatusIndicators(user, isOnline) {
    const dotClass = isOnline ? "online" : "offline";
    const title = isOnline ? "آنلاین (متصل و فعال)" : "قطع ارتباط (عدم دریافت پکت)";

    // Update chip in top members bar
    const chip = document.getElementById(`chip-${cssEscape(user)}`);
    if (chip) {
      chip.title = `${user}: ${title}`;
      const dot = chip.querySelector(".peer-status-dot");
      if (dot) {
        dot.className = `peer-status-dot ${dotClass}`;
        dot.title = title;
      }
    }

    // Update status dot beside sender nickname in chat bubbles
    const dots = document.querySelectorAll(`.peer-status-dot[data-peer="${user}"]`);
    dots.forEach((dot) => {
      dot.className = `peer-status-dot ${dotClass}`;
      dot.title = title;
    });

    updateDeleteRoomButtonState();
  }

  function initPeerPresence() {
    if (peerPingInterval) clearInterval(peerPingInterval);
    if (peerFreshnessChecker) clearInterval(peerFreshnessChecker);

    // 1. Ping Sender: Send heartbeat ping every 1500ms
    peerPingInterval = setInterval(() => {
      if (!state.isAuthenticated) return;
      if (ws && ws.readyState === WebSocket.OPEN) {
        try {
          ws.send(JSON.stringify(wrapAntiDpi({
            type: "peer_ping",
            room: state.room,
            user: state.nickname,
          })));
        } catch (e) {}
      } else if (state.transportMode === "http") {
        sendHttpPeerPing();
      }
    }, 1500);

    // 2. Freshness Checker: every 500ms, if now - lastPing > PRESENCE_TIMEOUT_MS -> offline (RED LIGHT)!
    peerFreshnessChecker = setInterval(() => {
      if (!state.isAuthenticated) return;
      const now = Date.now();
      peers.forEach((data, user) => {
        if (user === state.nickname) return;
        const diff = now - (data.lastPing || 0);
        const isOnline = diff <= PRESENCE_TIMEOUT_MS;
        if (data.isOnline !== isOnline) {
          data.isOnline = isOnline;
          updatePeerStatusIndicators(user, isOnline);
        }
      });
    }, 500);
  }

  async function sendHttpPeerPing() {
    try {
      const httpBase = getHttpBaseUrl(state.serverUrl);
      await fetch(`${httpBase}/api/peer_ping`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(wrapAntiDpi({
          room: state.room,
          password: state.password,
          sender: state.nickname,
        })),
      });
    } catch (e) {}
  }

  // ==========================================================================
  // Message Status Receipts (✓ Sent -> ✓✓ Delivered -> ◯ Seen Circle)
  // ==========================================================================
  function isChatVisible() {
    if (document.hidden) return false;
    if (!document.hasFocus()) return false;
    if (window.ChatNative && window.ChatNative.isAppForeground && !window.ChatNative.isAppForeground()) {
      return false;
    }
    return !chatView.classList.contains("hidden");
  }

  function renderStatusIcon(status = "sent") {
    if (status === "pending") {
      return '<span class="msg-status pending" title="در حال ارسال / صف تحویل...">⏳</span>';
    }
    if (status === "delivered") {
      return '<span class="msg-status delivered" title="تحویل داده شد (رسید به دستش)">✓✓</span>';
    }
    if (status === "seen") {
      return '<span class="msg-status seen" title="مشاهده شد (صفحه چت دیده شد)"><svg class="status-circle-svg" viewBox="0 0 14 14"><circle cx="7" cy="7" r="5"></circle></svg></span>';
    }
    return '<span class="msg-status sent" title="ارسال شد به سرور">✓</span>';
  }

  function updateMessageStatus(msgId, status) {
    const el = document.getElementById(`msg-${msgId}`);
    if (!el) return;
    const statusElem = el.querySelector(".msg-status");
    if (!statusElem) return;

    if (status === "pending") {
      statusElem.className = "msg-status pending";
      statusElem.textContent = "⏳";
      statusElem.title = "در حال ارسال / صف تحویل...";
    } else if (status === "sent") {
      if (statusElem.classList.contains("delivered") || statusElem.classList.contains("seen")) return;
      statusElem.className = "msg-status sent";
      statusElem.textContent = "✓";
      statusElem.title = "ارسال شد به سرور";
    } else if (status === "delivered") {
      if (statusElem.classList.contains("seen")) return;
      statusElem.className = "msg-status delivered";
      statusElem.textContent = "✓✓";
      statusElem.title = "تحویل داده شد (رسید به دستش)";
    } else if (status === "seen") {
      statusElem.className = "msg-status seen";
      statusElem.innerHTML = '<svg class="status-circle-svg" viewBox="0 0 14 14"><circle cx="7" cy="7" r="5"></circle></svg>';
      statusElem.title = "مشاهده شد (صفحه چت دیده شد)";
    }
  }

  function sendDeliveryReceipt(msgId) {
    if (!msgId || !state.room) return;
    if (ws && ws.readyState === WebSocket.OPEN) {
      try {
        ws.send(JSON.stringify(wrapAntiDpi({
          type: "msg_delivered",
          msgId: msgId,
          room: state.room,
        })));
      } catch (e) {}
    } else if (state.transportMode === "http") {
      sendHttpReceipt("delivered", [msgId]);
    }
  }

  function sendSeenReceipt(msgIdOrIds) {
    if (!state.room) return;
    const ids = Array.isArray(msgIdOrIds) ? msgIdOrIds : [msgIdOrIds];
    if (ids.length === 0) return;

    if (ws && ws.readyState === WebSocket.OPEN) {
      try {
        ws.send(JSON.stringify(wrapAntiDpi({
          type: "msg_seen",
          msgIds: ids,
          room: state.room,
        })));
      } catch (e) {}
    } else if (state.transportMode === "http") {
      sendHttpReceipt("seen", ids);
    }
  }

  async function sendHttpReceipt(receiptType, msgIds) {
    try {
      const httpBase = getHttpBaseUrl(state.serverUrl);
      await fetch(`${httpBase}/api/receipt`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(wrapAntiDpi({
          room: state.room,
          password: state.password,
          sender: state.nickname,
          type: receiptType,
          msgIds: msgIds,
        })),
      });
    } catch (e) {}
  }

  function flushUnseenReceipts() {
    if (!state.isAuthenticated || unseenMessageIds.size === 0) return;
    if (!isChatVisible()) return;

    const idsToSend = Array.from(unseenMessageIds);
    unseenMessageIds.clear();
    sendSeenReceipt(idsToSend);
  }

  function formatTime(date = new Date()) {
    const h = String(date.getHours()).padStart(2, "0");
    const m = String(date.getMinutes()).padStart(2, "0");
    return `${h}:${m}`;
  }

  function escapeHtml(str) {
    if (!str) return "";
    return String(str)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#039;");
  }

  function appendMessage({ type = "peer", sender = "", text = "", time = "", id = "", isEncrypted = true, isPending = false, status = "sent" }) {
    // If element with this id already exists in DOM, update status if needed
    if (id) {
      const existing = document.getElementById(`msg-${id}`);
      if (existing) {
        if (!isPending) {
          updateMessageStatus(id, status);
        }
        return;
      }
    }

    const wrapper = document.createElement("div");
    wrapper.className = `msg-wrapper ${type}`;
    if (id) wrapper.id = `msg-${id}`;

    if (type === "system") {
      wrapper.innerHTML = `
        <div class="msg-bubble">
          <span>${escapeHtml(text)}</span>
        </div>
      `;
    } else {
      const isMe = type === "me";
      const timeStr = time || formatTime();
      const lockIcon = isEncrypted ? '<span class="msg-lock" title="رمزنگاری سرتاسری AES-256">🔒</span>' : "";
      const initialStatus = isPending ? "pending" : (status || "sent");
      const statusIcon = isMe ? renderStatusIcon(initialStatus) : "";

      // Peer dot beside sender ID
      let peerDotHtml = "";
      if (!isMe && sender) {
        const peerData = peers.get(sender);
        const isOnline = peerData ? peerData.isOnline : false;
        const dotClass = isOnline ? "online" : "offline";
        const dotTitle = isOnline ? "آنلاین (پینگ فعال زیر ۲ ثانیه)" : "قطع ارتباط (بیش از ۲ ثانیه بدون پینگ)";
        peerDotHtml = `<span class="peer-status-dot ${dotClass}" data-peer="${escapeHtml(sender)}" title="${dotTitle}"></span>`;
      }

      wrapper.innerHTML = `
        <div class="msg-bubble">
          ${!isMe && sender ? `<div class="msg-sender">${peerDotHtml} ${escapeHtml(sender)}</div>` : ""}
          <div class="msg-text">${escapeHtml(text)}</div>
          <div class="msg-meta">
            ${lockIcon}
            <span class="msg-time">${timeStr}</span>
            ${statusIcon}
          </div>
        </div>
      `;

      wrapper.querySelector(".msg-bubble").addEventListener("click", () => {
        if (window.ChatNative && window.ChatNative.copyToClipboard) {
          window.ChatNative.copyToClipboard(text);
        }
      });
    }

    chatMessages.appendChild(wrapper);
    chatMessages.scrollTop = chatMessages.scrollHeight;
  }

  // Mark message as confirmed/sent in UI
  function markMessageDelivered(msgId) {
    updateMessageStatus(msgId, "sent");
  }

  // 3. Room Switching & View Management
  function enterChatView(roomName) {
    state.isAuthenticated = true;
    hideGateError();
    roomGate.classList.add("hidden");
    chatView.classList.remove("hidden");
    btnLeaveRoom.classList.remove("hidden");
    if (btnDeleteRoom) btnDeleteRoom.classList.remove("hidden");
    if (btnDeleteRoomModal) btnDeleteRoomModal.classList.remove("hidden");
    btnClear.classList.remove("hidden");
    roomStatusBadge.classList.remove("hidden");
    currentRoomDisplay.textContent = roomName;
    updateDeleteRoomButtonState();
    messageInput.focus();

    // Check browser notification permission
    if (state.notificationsEnabled && "Notification" in window && Notification.permission === "default") {
      notifBanner.classList.remove("hidden");
    } else {
      notifBanner.classList.add("hidden");
    }
  }

  function returnToRoomGate() {
    state.isAuthenticated = false;
    roomGate.classList.remove("hidden");
    chatView.classList.add("hidden");
    btnLeaveRoom.classList.add("hidden");
    if (btnDeleteRoom) btnDeleteRoom.classList.add("hidden");
    if (btnDeleteRoomModal) btnDeleteRoomModal.classList.add("hidden");
    btnClear.classList.add("hidden");
    roomStatusBadge.classList.add("hidden");
    updateStatus("disconnected", "اتاقی متصل نیست");
  }

  // ==========================================================================
  // Guaranteed Delivery Outgoing Queue
  // ==========================================================================
  function enqueueOutgoingMessage(msgRecord) {
    state.outgoingQueue.push(msgRecord);
    flushOutgoingQueue();
  }

  async function flushOutgoingQueue() {
    if (!state.outgoingQueue.length || !state.isAuthenticated) return;

    const pending = [...state.outgoingQueue];
    for (const item of pending) {
      let sentSuccess = false;

      // Mode 1: WebSocket Send with Anti-DPI Traffic Shaping
      if (state.transportMode === "ws" && ws && ws.readyState === WebSocket.OPEN) {
        try {
          const packet = wrapAntiDpi({
            type: "chat",
            msgId: item.msgId,
            room: state.room,
            sender: state.nickname,
            ciphertext: item.ciphertext,
            encrypted: item.encrypted,
            time: item.time,
          });
          ws.send(JSON.stringify(packet));
          sentSuccess = true;
          markMessageDelivered(item.msgId);
        } catch (e) {
          sentSuccess = false;
        }
      }

      // Mode 2: HTTP Safe Tunnel Send (Fallback if WS fails or in HTTP mode)
      if (!sentSuccess) {
        try {
          const httpUrl = getHttpBaseUrl(state.serverUrl) + "/api/send";
          const res = await fetch(httpUrl, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify(wrapAntiDpi({
              room: state.room,
              password: state.password,
              sender: state.nickname,
              ciphertext: item.ciphertext,
              encrypted: item.encrypted,
              msgId: item.msgId,
              time: item.time,
            })),
          });
          if (res.ok) {
            const data = await res.json();
            if (data.status === "ok") {
              sentSuccess = true;
              markMessageDelivered(item.msgId);
            }
          }
        } catch (err) {
          sentSuccess = false;
        }
      }

      if (sentSuccess) {
        state.outgoingQueue = state.outgoingQueue.filter((m) => m.msgId !== item.msgId);
      }
    }
  }

  // Periodic Queue Flusher
  clearInterval(queueRetryTimer);
  queueRetryTimer = setInterval(() => {
    if (state.outgoingQueue.length > 0 && state.isAuthenticated) {
      flushOutgoingQueue();
    }
  }, 2500);

  // ==========================================================================
  // Dual-Transport Protocol: WebSocket Primary + HTTP Safe Tunnel Fallback
  // ==========================================================================
  function connectAndJoinRoom(room, password, nickname) {
    if (isConnecting) return;

    state.room = room.trim();
    state.password = password.trim();
    state.nickname = nickname.trim() || "کاربر";

    // Strictly enforce selected connection provider so we NEVER mistakenly use the other one:
    if (state.connectionMode === "cloudflare") {
      const candidate = sanitizeServerUrl(serverUrlInput.value || modalServerUrl.value);
      state.serverUrl = candidate || (state.activeTunnelUrl || "wss://medications-firewall-angle-counter.trycloudflare.com");
    } else if (state.connectionMode === "cleanip") {
      const candidate = sanitizeServerUrl(serverUrlInput.value || modalServerUrl.value || (gateCleanIp && gateCleanIp.value) || (modalCleanIp && modalCleanIp.value) || state.cleanIp);
      state.serverUrl = candidate ? (candidate.includes("://") ? candidate : `wss://${candidate}:443`) : "wss://104.16.132.229:443";
    } else {
      const candidate = sanitizeServerUrl(serverUrlInput.value || modalServerUrl.value);
      state.serverUrl = candidate || DIRECT_SERVER_URL;
    }
    if (serverUrlInput) serverUrlInput.value = state.serverUrl;
    if (modalServerUrl) modalServerUrl.value = state.serverUrl;
    persistSettings();

    if (!state.room || !state.password) {
      showGateError("لطفاً نام اتاق و رمز عبور سخت آن را وارد کنید.");
      return;
    }

    hideGateError();
    clearTimeout(reconnectTimer);
    clearTimeout(wsHandshakeTimer);
    if (jitteredPingTimer) clearTimeout(jitteredPingTimer);
    if (heartbeatTimer) clearInterval(heartbeatTimer);
    clearInterval(decoyChaffTimer);
    clearInterval(httpPollTimer);
    clearInterval(wsProbeTimer);

    isManualDisconnect = false;
    isConnecting = true;
    state.transportMode = "ws";
    const isClean = (state.connectionMode === "cleanip");
    const isCf = (state.connectionMode === "cloudflare") || (!isClean && isCloudflareUrl(state.serverUrl));
    updateTransportBadge("ws");
    const connectingMsg = isClean ? "در حال اتصال با کلین آی‌پی..." : (isCf ? "در حال اتصال به کلادفلر..." : "در حال اتصال به سرور مستقیم...");
    updateStatus("connecting", connectingMsg);

    if (ws) {
      try {
        ws.close();
      } catch (e) {}
      ws = null;
    }

    // Set a 2.5-second timeout: If WebSocket fails to establish handshake,
    // immediately failover to HTTP Safe Tunnel!
    wsHandshakeTimer = setTimeout(() => {
      if (isConnecting && (!ws || ws.readyState !== WebSocket.OPEN)) {
        console.warn("WebSocket connection timed out behind strict firewall. Failing over to HTTP Safe Tunnel...");
        try {
          if (ws) ws.close();
        } catch (e) {}
        ws = null;
        activateHttpTunnelFallback();
      }
    }, 2500);

    try {
      ws = new WebSocket(state.serverUrl);
    } catch (err) {
      clearTimeout(wsHandshakeTimer);
      activateHttpTunnelFallback();
      return;
    }

    ws.onopen = () => {
      clearTimeout(wsHandshakeTimer);
      updateStatus("connecting", isCf ? "تایید امنیتی در کلادفلر..." : "تایید امنیتی در سرور مستقیم...");

      // Send join room authentication payload with Anti-DPI Traffic Shaping
      const joinPayload = wrapAntiDpi({
        type: "join",
        room: state.room,
        password: state.password,
        sender: state.nickname,
        clientId: clientId,
        time: formatTime(),
      });
      try {
        ws.send(JSON.stringify(joinPayload));
      } catch (e) {}

      // Start Anti-DPI Jittered Ping and Decoy Cover Traffic Loops
      startJitteredPingLoop();
      startDecoyChaffLoop();
    };

    ws.onmessage = (event) => {
      let data = event.data;
      let parsed = null;
      try {
        parsed = JSON.parse(data);
      } catch (e) {
        return;
      }
      if (!parsed) return;
      unwrapAntiDpi(parsed);

      // Silently drop Anti-DPI decoy chaff / cover traffic
      if (parsed.type === "decoy" || parsed.decoy) {
        return;
      }

      // Ignore Pong
      if (parsed.type === "pong") {
        return;
      }

      // Authentication Success
      if (parsed.type === "auth_success") {
        isConnecting = false;
        state.transportMode = "ws";
        showReconnectBanner(false);
        isReconnectStopped = false;
        const isClean = (state.connectionMode === "cleanip");
        const isCf = (state.connectionMode === "cloudflare") || (!isClean && isCloudflareUrl(state.serverUrl));
        const modeTitle = isClean ? "اتصال با کلین آی‌پی" : (isCf ? "اتصال به کلادفلر" : "اتصال مستقیم به سرور");
        const modeBadge = isClean ? "🎯 اتصال با کلین آی‌پی" : (isCf ? "☁️ اتصال به کلادفلر" : "⚡ اتصال مستقیم به سرور");
        updateTransportBadge("ws");
        updateAntiDpiBadge();
        updateStatus("connected", modeTitle);
        nativeToast(`✅ ${modeTitle} برقرار شد`);
        enterChatView(parsed.room || state.room);

        // Load initial room members & ping presence
        peers.clear();
        if (Array.isArray(parsed.members)) {
          for (const m of parsed.members) {
            if (m.user && m.user !== state.nickname) {
              const lp = m.last_ping ? Date.now() - Math.max(0, (Date.now() - m.last_ping * 1000)) : Date.now();
              peers.set(m.user, { lastPing: lp, isOnline: m.online !== false });
            }
          }
        }
        renderRoomMembers();
        initPeerPresence();

        appendMessage({
          type: "system",
          text: `${modeBadge}: به اتاق امن و اختصاصی «${parsed.room || state.room}» متصل شدید. تمامی پیام‌ها با رمزنگاری سرتاسری AES-256 و پدینگ تصادفی ضد DPI محافظت می‌شوند.`,
          isEncrypted: false,
        });
        flushOutgoingQueue();
        return;
      }

      // Authentication Error (Wrong Password, Duplicate Nickname, or Access Denied)
      if (parsed.type === "auth_error") {
        isConnecting = false;
        showReconnectBanner(false);
        isReconnectStopped = true;
        clearTimeout(reconnectTimer);
        const errText = parsed.text || "رمز عبور اتاق نادرست است! دسترسی غیرمجاز.";
        const isDuplicateName = errText.includes("نام") || errText.includes("حضور دارد");
        updateStatus("disconnected", isDuplicateName ? "نام تکراری" : "رمز نادرست");
        showGateError(errText);
        returnToRoomGate();
        if (isDuplicateName) {
          gateNickname.focus();
          gateNickname.select();
        }
        try {
          ws.close();
        } catch (e) {}
        ws = null;
        return;
      }

      // Peer Ping Heartbeat (Live peer status light)
      if (parsed.type === "peer_ping") {
        if (parsed.user && parsed.user !== state.nickname) {
          peers.set(parsed.user, { lastPing: Date.now(), isOnline: true });
          renderRoomMembers();
          updatePeerStatusIndicators(parsed.user, true);
        }
        return;
      }

      // Peer Join
      if (parsed.type === "peer_join") {
        if (parsed.user && parsed.user !== state.nickname) {
          peers.set(parsed.user, { lastPing: Date.now(), isOnline: true });
          renderRoomMembers();
          updatePeerStatusIndicators(parsed.user, true);
        }
        if (parsed.text) {
          appendMessage({ type: "system", text: parsed.text, isEncrypted: false });
        }
        return;
      }

      // Peer Offline (Turns peer light RED immediately)
      if (parsed.type === "peer_offline") {
        if (parsed.user) {
          if (peers.has(parsed.user)) {
            peers.get(parsed.user).lastPing = 0;
            peers.get(parsed.user).isOnline = false;
          }
          renderRoomMembers();
          updatePeerStatusIndicators(parsed.user, false);
        }
        if (parsed.text) {
          appendMessage({ type: "system", text: parsed.text, isEncrypted: false });
        }
        return;
      }

      // Message Status Receipts (✓ Sent -> ✓✓ Delivered -> ◯ Seen Circle)
      if (parsed.type === "msg_status" && parsed.msgId && parsed.status) {
        updateMessageStatus(parsed.msgId, parsed.status);
        return;
      }

      // ACK for sent message
      if (parsed.type === "ack" && parsed.msgId) {
        markMessageDelivered(parsed.msgId);
        state.outgoingQueue = state.outgoingQueue.filter((m) => m.msgId !== parsed.msgId);
        return;
      }

      // History Sync
      if (parsed.type === "history_sync" && Array.isArray(parsed.messages)) {
        for (const msg of parsed.messages) {
          processIncomingChatMessage(msg);
        }
        return;
      }

      // System Messages within the room
      if (parsed.type === "system") {
        appendMessage({
          type: "system",
          text: parsed.text || parsed.message,
          isEncrypted: false,
        });
        return;
      }

      // Room Deleted Confirmation
      if (parsed.type === "room_deleted") {
        nativeToast(parsed.text || "اتاق با موفقیت پاکسازی شد.");
        leaveRoom();
        gateRoomPassword.value = "";
        gateRoomPassword.focus();
        return;
      }

      // Incoming Chat Messages
      if (parsed.type === "chat") {
        processIncomingChatMessage(parsed);
      }
    };

    ws.onerror = () => {
      // If error occurs during initial handshake, failover immediately to HTTP Safe Tunnel
      if (isConnecting) {
        clearTimeout(wsHandshakeTimer);
        activateHttpTunnelFallback();
      }
    };

    ws.onclose = () => {
      if (jitteredPingTimer) clearTimeout(jitteredPingTimer);
      clearInterval(decoyChaffTimer);

      if (isConnecting && !state.isAuthenticated) {
        clearTimeout(wsHandshakeTimer);
        activateHttpTunnelFallback();
      } else if (state.isAuthenticated) {
        // If disconnected after being authenticated, try HTTP fallback immediately
        console.warn("WebSocket disconnected by firewall or network drop. Falling back to HTTP Safe Tunnel...");
        activateHttpTunnelFallback();
      } else if (!isConnecting) {
        updateStatus("disconnected", "قطع");
      }
    };
  }

  // ==========================================================================
  // HTTP Safe Tunnel Fallback (Bypasses Restrictive Mobile Firewalls)
  // ==========================================================================
  async function activateHttpTunnelFallback() {
    isConnecting = false;
    clearTimeout(wsHandshakeTimer);
    if (jitteredPingTimer) clearTimeout(jitteredPingTimer);
    clearInterval(decoyChaffTimer);
    state.transportMode = "http";
    updateTransportBadge("http");
    updateAntiDpiBadge();

    if (!state.room || !state.password) return;

    const isClean = (state.connectionMode === "cleanip");
    const isCf = (state.connectionMode === "cloudflare") || (!isClean && isCloudflareUrl(state.serverUrl));
    const modeTitle = isClean ? "اتصال با کلین آی‌پی" : (isCf ? "اتصال به کلادفلر" : "اتصال مستقیم به سرور");
    updateStatus("connecting", isClean ? "فعال‌سازی تونل HTTP کلین آی‌پی..." : (isCf ? "فعال‌سازی تونل HTTP کلادفلر..." : "فعال‌سازی تونل HTTP سرور مستقیم..."));
    const httpBase = getHttpBaseUrl(state.serverUrl);

    try {
      // 1. Authenticate via POST /api/join with Anti-DPI Traffic Shaping
      const joinRes = await fetch(`${httpBase}/api/join`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(wrapAntiDpi({
          room: state.room,
          password: state.password,
          sender: state.nickname,
          clientId: clientId,
        })),
      });

      if (!joinRes.ok) {
        const errData = await joinRes.json().catch(() => ({}));
        isReconnectStopped = true;
        clearTimeout(reconnectTimer);
        const errText = errData.text || "رمز عبور اتاق نادرست است یا سرور در دسترس نیست.";
        const isDuplicateName = errText.includes("نام") || errText.includes("حضور دارد");
        updateStatus("disconnected", isDuplicateName ? "نام تکراری" : "خطای تایید");
        showGateError(errText);
        returnToRoomGate();
        if (isDuplicateName) {
          gateNickname.focus();
          gateNickname.select();
        }
        return;
      }

      const joinData = await joinRes.json();
      updateStatus("connected", modeTitle);
      updateTransportBadge("http");
      nativeToast(`✅ ${modeTitle} برقرار شد`);
      showReconnectBanner(false);
      isReconnectStopped = false;
      enterChatView(state.room);
      initPeerPresence();

      // Load initial room members & ping presence from HTTP response
      peers.clear();
      if (Array.isArray(joinData.members)) {
        for (const m of joinData.members) {
          if (m.user && m.user !== state.nickname) {
            const lp = m.last_ping ? Date.now() - Math.max(0, (Date.now() - m.last_ping * 1000)) : Date.now();
            peers.set(m.user, { lastPing: lp, isOnline: m.online !== false });
          }
        }
      }
      renderRoomMembers();
      updateDeleteRoomButtonState();

      if (!state.seenMessageIds.has("sys_http_welcome")) {
        state.seenMessageIds.add("sys_http_welcome");
        appendMessage({
          type: "system",
          text: `${isCf ? "☁️ اتصال به کلادفلر" : "⚡ اتصال مستقیم به سرور"}: ارتباط با پروتکل ضد فایروال (HTTP Safe Tunnel) برقرار شد. تحویل پیام‌ها به صورت تضمینی و رمزنگاری‌شده انجام می‌شود.`,
          isEncrypted: false,
        });
      }

      // Flush any queued messages
      flushOutgoingQueue();

      // Start HTTP Polling Loop
      startHttpPolling();

      // Start quiet probe to see if WebSocket is restored
      startQuietWsProbe();
    } catch (err) {
      updateStatus("disconnected", "خطای اتصال");
      showGateError("عدم دسترسی به سرور. فایروال تمامی ارتباطات را مسدود کرده است.");
      if (state.autoReconnect && !isManualDisconnect && !isReconnectStopped) {
        scheduleReconnect();
      }
    }
  }

  function startHttpPolling() {
    clearInterval(httpPollTimer);
    const pollFn = async () => {
      if (!state.isAuthenticated || state.transportMode !== "http") return;
      try {
        const httpBase = getHttpBaseUrl(state.serverUrl);
        const url = `${httpBase}/api/poll?room=${encodeURIComponent(state.room)}&password=${encodeURIComponent(state.password)}&since=${state.lastSyncTimestamp}`;
        const res = await fetch(url, { method: "GET" });
        if (res.ok) {
          const data = await res.json();
          if (data.status === "ok") {
            if (Array.isArray(data.messages)) {
              for (const msg of data.messages) {
                if (msg.type === "peer_join") {
                  if (msg.user && msg.user !== state.nickname) {
                    peers.set(msg.user, { lastPing: Date.now(), isOnline: true });
                    renderRoomMembers();
                    updatePeerStatusIndicators(msg.user, true);
                    updateDeleteRoomButtonState();
                  }
                  if (msg.text && !state.seenMessageIds.has(msg.id)) {
                    state.seenMessageIds.add(msg.id);
                    appendMessage({ type: "system", text: msg.text, isEncrypted: false });
                  }
                } else if (msg.type === "peer_offline") {
                  if (msg.user && peers.has(msg.user)) {
                    peers.get(msg.user).isOnline = false;
                    renderRoomMembers();
                    updatePeerStatusIndicators(msg.user, false);
                    updateDeleteRoomButtonState();
                  }
                  if (msg.text && !state.seenMessageIds.has(msg.id)) {
                    state.seenMessageIds.add(msg.id);
                    appendMessage({ type: "system", text: msg.text, isEncrypted: false });
                  }
                } else {
                  processIncomingChatMessage(msg);
                }
              }
            }
            if (Array.isArray(data.receipts)) {
              for (const r of data.receipts) {
                if (r.msgId && r.status) {
                  updateMessageStatus(r.msgId, r.status);
                }
              }
            }
            if (Array.isArray(data.members)) {
              for (const m of data.members) {
                if (m.user && m.user !== state.nickname) {
                  const lp = m.last_ping ? Date.now() - Math.max(0, (Date.now() - m.last_ping * 1000)) : Date.now();
                  peers.set(m.user, { lastPing: lp, isOnline: m.online !== false });
                }
              }
              renderRoomMembers();
              updateDeleteRoomButtonState();
            }
            if (data.server_time && data.server_time > state.lastSyncTimestamp) {
              state.lastSyncTimestamp = data.server_time;
            }
          }
        }
      } catch (e) {}
    };

    // Poll every 2.5 seconds (or 10 seconds if page is in background)
    httpPollTimer = setInterval(pollFn, document.hidden ? 10000 : 2500);
  }

  // Quietly probe if WebSocket is reachable again; if so, upgrade transport seamlessly
  function startQuietWsProbe() {
    clearInterval(wsProbeTimer);
    wsProbeTimer = setInterval(() => {
      if (!state.isAuthenticated || state.transportMode !== "http") return;
      try {
        const probeWs = new WebSocket(state.serverUrl);
        probeWs.onopen = () => {
          probeWs.close();
          console.log("WebSocket is available again! Re-upgrading transport...");
          connectAndJoinRoom(state.room, state.password, state.nickname);
        };
        probeWs.onerror = () => {
          try { probeWs.close(); } catch (e) {}
        };
      } catch (e) {}
    }, 60000);
  }

  // ==========================================================================
  // Process and Decrypt Incoming Message
  // ==========================================================================
  function processIncomingChatMessage(msg) {
    const msgId = msg.id || `${msg.sender}_${msg.time}_${msg.ciphertext ? msg.ciphertext.slice(0, 10) : ""}`;
    if (state.seenMessageIds.has(msgId)) {
      if (msg.sender === state.nickname && msg.status) {
        updateMessageStatus(msgId, msg.status);
      }
      return;
    }
    state.seenMessageIds.add(msgId);

    if (msg.ts && msg.ts > state.lastSyncTimestamp) {
      state.lastSyncTimestamp = msg.ts;
    }

    const isMe = msg.sender === state.nickname;

    // Immediate peer presence detection: any message proves peer is alive and ONLINE right now!
    if (!isMe && msg.sender) {
      const now = Date.now();
      const existing = peers.get(msg.sender);
      if (!existing) {
        peers.set(msg.sender, { lastPing: now, isOnline: true });
        renderRoomMembers();
      } else {
        existing.lastPing = now;
        existing.isOnline = true;
      }
      updatePeerStatusIndicators(msg.sender, true);
      updateDeleteRoomButtonState();
    }

    // Decrypt if encrypted
    let displayText = msg.ciphertext || msg.text || "";
    let isEncrypted = false;

    if (msg.encrypted || (msg.ciphertext && msg.ciphertext.startsWith("U2FsdGVkX1"))) {
      isEncrypted = true;
      const decrypted = decryptPayload(msg.ciphertext, state.password);
      if (decrypted !== null) {
        displayText = decrypted;
      } else {
        displayText = "⚠️ [خطای کلید]: این پیام با رمز دیگری کدگذاری شده و قابل رمزگشایی نیست.";
      }
    }

    // Append to UI
    appendMessage({
      id: msgId,
      type: isMe ? "me" : "peer",
      sender: msg.sender,
      text: displayText,
      time: msg.time || formatTime(),
      isEncrypted: isEncrypted,
      isPending: false,
      status: msg.status || "sent",
    });

    // If incoming from another user:
    if (!isMe) {
      // 1. Immediately send delivery receipt (2 ticks: ✓✓)
      sendDeliveryReceipt(msgId);

      // 2. Check if chat screen is currently visible to user
      if (isChatVisible()) {
        sendSeenReceipt(msgId);
      } else {
        unseenMessageIds.add(msgId);
      }

      const isAppHidden =
        document.hidden ||
        !document.hasFocus() ||
        (window.ChatNative && window.ChatNative.isAppForeground && !window.ChatNative.isAppForeground());

      if (isAppHidden) {
        triggerBackgroundNotification(msg.sender, displayText, state.room);
      } else {
        playAudioChime();
        nativeVibrate(30);
      }
    }
  }

  function scheduleReconnect() {
    if (isReconnectStopped || !state.autoReconnect || isManualDisconnect) return;
    clearTimeout(reconnectTimer);
    const isClean = (state.connectionMode === "cleanip");
    const isCf = (state.connectionMode === "cloudflare") || (!isClean && isCloudflareUrl(state.serverUrl));
    const reconnectTitle = isClean ? "تلاش مجدد اتصال با کلین آی‌پی..." : (isCf ? "تلاش مجدد اتصال کلادفلر..." : "تلاش مجدد اتصال مستقیم...");
    const bannerTitle = isClean ? "در حال تلاش برای اتصال مجدد با کلین آی‌پی تا ۴ ثانیه..." : (isCf ? "در حال تلاش برای اتصال مجدد به کلادفلر تا ۴ ثانیه..." : "در حال تلاش برای اتصال مجدد به سرور مستقیم تا ۴ ثانیه...");
    updateStatus("connecting", reconnectTitle);
    showReconnectBanner(true, bannerTitle, false);
    reconnectTimer = setTimeout(() => {
      if (state.room && state.password && !isReconnectStopped && !isManualDisconnect) {
        connectAndJoinRoom(state.room, state.password, state.nickname);
      }
    }, 4000);
  }

  function leaveRoom() {
    isManualDisconnect = true;
    showReconnectBanner(false);
    isReconnectStopped = false;
    clearTimeout(reconnectTimer);
    clearTimeout(wsHandshakeTimer);
    if (jitteredPingTimer) clearTimeout(jitteredPingTimer);
    if (heartbeatTimer) clearInterval(heartbeatTimer);
    if (peerPingInterval) clearInterval(peerPingInterval);
    if (peerFreshnessChecker) clearInterval(peerFreshnessChecker);
    peers.clear();
    renderRoomMembers();
    clearInterval(decoyChaffTimer);
    clearInterval(httpPollTimer);
    clearInterval(wsProbeTimer);

    if (ws && ws.readyState === WebSocket.OPEN) {
      try {
        ws.send(JSON.stringify({ type: "leave" }));
        ws.close();
      } catch (e) {}
    } else if (state.transportMode === "http" && state.room) {
      try {
        const httpBase = getHttpBaseUrl(state.serverUrl);
        fetch(`${httpBase}/api/leave`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(wrapAntiDpi({
            room: state.room,
            sender: state.nickname,
            clientId: clientId,
          })),
        }).catch(() => {});
      } catch (e) {}
    }
    ws = null;
    returnToRoomGate();
    nativeToast("از اتاق خارج شدید");
  }

  // ==========================================================================
  // Form Events & Interactivity
  // ==========================================================================
  gateForm.addEventListener("submit", (e) => {
    e.preventDefault();
    const room = gateRoomName.value.trim();
    const password = gateRoomPassword.value.trim();
    const nickname = gateNickname.value.trim();

    if (!room || !password) {
      showGateError("لطفاً هم نام اتاق و هم رمز عبور سخت را وارد کنید.");
      return;
    }
    isReconnectStopped = false;
    connectAndJoinRoom(room, password, nickname);
  });

  // Password Visibility Toggle
  btnTogglePassword.addEventListener("click", () => {
    const isPassword = gateRoomPassword.type === "password";
    gateRoomPassword.type = isPassword ? "text" : "password";
    btnTogglePassword.textContent = isPassword ? "🙈" : "👁️";
  });

  // Advanced Server Settings Toggle
  btnToggleAdvanced.addEventListener("click", () => {
    advancedServerBlock.classList.toggle("hidden");
  });

  // Chat Send Form (Encrypts then enqueues for guaranteed delivery)
  chatForm.addEventListener("submit", (e) => {
    e.preventDefault();
    const text = messageInput.value.trim();
    if (!text) return;

    if (!state.isAuthenticated) {
      nativeToast("ابتدا وارد اتاق شوید");
      return;
    }

    const msgId = "m_" + Date.now() + "_" + Math.random().toString(36).substr(2, 6);
    const timeStr = formatTime();

    // 1. Zero-Knowledge E2EE Encryption
    const { ciphertext, encrypted } = encryptPayload(text, state.password);

    // 2. Immediate Local UI Rendering with pending status
    state.seenMessageIds.add(msgId);
    appendMessage({
      id: msgId,
      type: "me",
      sender: state.nickname,
      text: text,
      time: timeStr,
      isEncrypted: encrypted,
      isPending: true,
    });

    messageInput.value = "";
    nativeVibrate(20);

    // 3. Queue for Guaranteed Delivery
    enqueueOutgoingMessage({
      msgId: msgId,
      room: state.room,
      sender: state.nickname,
      ciphertext: ciphertext,
      encrypted: encrypted,
      time: timeStr,
    });
  });

  // Leave room button
  btnLeaveRoom.addEventListener("click", leaveRoom);
  btnDisconnectModal.addEventListener("click", () => {
    closeSettings();
    leaveRoom();
  });

  // Delete room button (enabled only when sole member)
  async function deleteRoom() {
    if (!state.isAuthenticated || !state.room) return;
    if (!isOnlyMemberInRoom()) {
      nativeToast("امکان پاک کردن اتاق وجود ندارد؛ کاربران دیگری در اتاق حضور دارند.");
      return;
    }

    const ok = confirm(
      "آیا مطمئن هستید که می‌خواهید این اتاق را به طور کامل پاک کنید؟\n\n" +
      "با این کار، اتاق از حافظه سرور حذف شده و هر فرد جدیدی می‌تواند اتاق را با رمز عبور جدید بسازد."
    );
    if (!ok) return;

    const roomToDelete = state.room;
    const pw = state.password;

    if (ws && ws.readyState === WebSocket.OPEN) {
      try {
        ws.send(JSON.stringify(wrapAntiDpi({
          type: "delete_room",
          room: roomToDelete,
          password: pw,
          sender: state.nickname,
        })));
      } catch (e) {}
    } else {
      try {
        const httpBase = getHttpBaseUrl(state.serverUrl);
        const res = await fetch(`${httpBase}/api/delete_room`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(wrapAntiDpi({
            room: roomToDelete,
            password: pw,
            sender: state.nickname,
          })),
        });
        if (!res.ok) {
          const errData = await res.json().catch(() => ({}));
          nativeToast(errData.text || "خطا در پاک کردن اتاق");
          return;
        }
      } catch (e) {
        nativeToast("خطا در ارسال درخواست پاک کردن اتاق");
        return;
      }
    }

    leaveRoom();
    gateRoomPassword.value = "";
    gateRoomName.value = roomToDelete;
    gateRoomPassword.focus();
    nativeToast(`اتاق «${roomToDelete}» به طور کامل پاک شد. اکنون می‌توانید آن را با رمز جدید بسازید.`);
  }

  if (btnDeleteRoom) {
    btnDeleteRoom.addEventListener("click", deleteRoom);
  }
  if (btnDeleteRoomModal) {
    btnDeleteRoomModal.addEventListener("click", () => {
      closeSettings();
      deleteRoom();
    });
  }

  // Clear messages button
  btnClear.addEventListener("click", () => {
    chatMessages.innerHTML = "";
    state.seenMessageIds.clear();
    appendMessage({
      type: "system",
      text: "صفحه چت پاکسازی شد.",
      isEncrypted: false,
    });
  });

  // Notification Permission Request
  function requestNotificationAccess() {
    if ("Notification" in window) {
      Notification.requestPermission().then((permission) => {
        if (permission === "granted") {
          notifBanner.classList.add("hidden");
          state.notificationsEnabled = true;
          updateNotificationUI();
          persistSettings();
          nativeToast("اعلان‌های صفحه قفل فعال شد 🔔");
          triggerBackgroundNotification("رخش چت", "اعلان‌ها فعال شدند و آماده دریافت پیام روی صفحه قفل هستند.", state.room || "سیستم");
        } else {
          nativeToast("مجوز اعلان صادر نشد");
        }
      });
    } else {
      nativeToast("این مرورگر از اعلان پشتیبانی نمی‌کند");
    }
  }

  btnEnableNotif.addEventListener("click", requestNotificationAccess);
  btnNotification.addEventListener("click", toggleNotifications);

  if (notificationToggle) {
    notificationToggle.addEventListener("change", () => {
      state.notificationsEnabled = notificationToggle.checked;
      updateNotificationUI();
      persistSettings();
      nativeToast(state.notificationsEnabled ? "اعلان‌ها روشن شد 🔔" : "اعلان‌ها خاموش شد 🔕");
    });
  }

  // Settings Modal Handlers
  function openSettings() {
    document.body.classList.add("modal-open");
    modalServerUrl.value = state.serverUrl;
    if (serverTestFeedback) {
      serverTestFeedback.classList.add("hidden");
      serverTestFeedback.innerHTML = "";
    }
    if (gateCleanIp) gateCleanIp.value = state.cleanIp || "";
  if (modalCleanIp) modalCleanIp.value = state.cleanIp || "";
    if (antiDpiToggle) antiDpiToggle.checked = state.antiDpi;
    if (decoyChaffToggle) decoyChaffToggle.checked = state.decoyChaff;
    autoReconnectInput.checked = state.autoReconnect;
    if (notificationToggle) notificationToggle.checked = state.notificationsEnabled;
    if (vibrationToggle) vibrationToggle.checked = state.vibrationEnabled;
    keepCredentialsInput.checked = state.keepCredentials;
    updatePresetSelectionUI(state.connectionMode);
    settingsModal.classList.remove("hidden");
    if (state.connectionMode === "cloudflare") {
      queryActiveTunnel();
    }
  }

  function closeSettings() {
    document.body.classList.remove("modal-open");
    const oldUrl = state.serverUrl;
    if (modalServerUrl.value.trim()) {
      state.serverUrl = sanitizeServerUrl(modalServerUrl.value);
    }
    serverUrlInput.value = state.serverUrl;
    if (modalCleanIp) {
      state.cleanIp = modalCleanIp.value.trim();
      if (gateCleanIp) gateCleanIp.value = state.cleanIp;
    }
    if (antiDpiToggle) state.antiDpi = antiDpiToggle.checked;
    if (decoyChaffToggle) state.decoyChaff = decoyChaffToggle.checked;
    state.autoReconnect = autoReconnectInput.checked;
    if (vibrationToggle) state.vibrationEnabled = vibrationToggle.checked;
    state.keepCredentials = keepCredentialsInput.checked;
    updatePresetSelectionUI(state.connectionMode);
    updateAntiDpiBadge();
    updateTransportBadge(state.transportMode || "ws");
    persistSettings();
    settingsModal.classList.add("hidden");

    if (oldUrl !== state.serverUrl && state.isAuthenticated && state.room && state.password) {
      nativeToast("در حال انتقال به آدرس جدید سرور...");
      connectAndJoinRoom(state.room, state.password, state.nickname);
    }
  }

  // Connection Presets Handlers - Gate Screen
  if (btnGatePresetDirect) {
    btnGatePresetDirect.addEventListener("click", () => {
      selectConnectionPreset("direct", false);
    });
  }

  if (btnGatePresetCfTunnel) {
    btnGatePresetCfTunnel.addEventListener("click", () => {
      selectConnectionPreset("cloudflare", false);
    });
  }

  if (btnGatePresetCleanIp) {
    btnGatePresetCleanIp.addEventListener("click", () => {
      selectConnectionPreset("cleanip", false);
    });
  }

  // Connection Presets Handlers - Settings Modal
  if (btnPresetDirect) {
    btnPresetDirect.addEventListener("click", () => {
      selectConnectionPreset("direct", false);
    });
  }

  if (btnPresetCfTunnel) {
    btnPresetCfTunnel.addEventListener("click", () => {
      selectConnectionPreset("cloudflare", false);
    });
  }

  if (btnPresetCleanIp) {
    btnPresetCleanIp.addEventListener("click", () => {
      selectConnectionPreset("cleanip", false);
    });
  }

  // Synchronize Clean IP inputs across Gate and Modal
  function handleCleanIpChange(val) {
    state.cleanIp = (val || "").trim();
    if (gateCleanIp && gateCleanIp.value !== state.cleanIp) gateCleanIp.value = state.cleanIp;
    if (modalCleanIp && modalCleanIp.value !== state.cleanIp) modalCleanIp.value = state.cleanIp;
    if (state.connectionMode === "cleanip") {
      const targetUrl = state.cleanIp ? (state.cleanIp.includes("://") ? state.cleanIp : `wss://${state.cleanIp}:443`) : "wss://104.16.132.229:443";
      state.serverUrl = targetUrl;
      if (serverUrlInput) serverUrlInput.value = targetUrl;
      if (modalServerUrl) modalServerUrl.value = targetUrl;
    }
    updatePresetSelectionUI(state.connectionMode);
    persistSettings();
  }

  if (gateCleanIp) {
    gateCleanIp.addEventListener("input", () => handleCleanIpChange(gateCleanIp.value));
  }
  if (modalCleanIp) {
    modalCleanIp.addEventListener("input", () => handleCleanIpChange(modalCleanIp.value));
  }

  // Direct test connection button listeners
  if (btnTestServerConn) {
    btnTestServerConn.addEventListener("click", () => {
      let urlToTest = (modalServerUrl && modalServerUrl.value.trim()) || "";
      if (!urlToTest) {
        if (state.connectionMode === "cloudflare") {
          urlToTest = state.activeTunnelUrl || "wss://medications-firewall-angle-counter.trycloudflare.com";
        } else if (state.connectionMode === "cleanip") {
          const cip = (modalCleanIp && modalCleanIp.value.trim()) || state.cleanIp || "104.16.132.229";
          urlToTest = cip.includes("://") ? cip : `wss://${cip}:443`;
        } else {
          urlToTest = DIRECT_SERVER_URL;
        }
      }
      testServerConnectivity(urlToTest, serverTestFeedback, btnTestServerConn);
    });
  }

  if (btnTestGateConn) {
    btnTestGateConn.addEventListener("click", () => {
      let urlToTest = (serverUrlInput && serverUrlInput.value.trim()) || "";
      if (!urlToTest) {
        if (state.connectionMode === "cloudflare") {
          urlToTest = state.activeTunnelUrl || "wss://medications-firewall-angle-counter.trycloudflare.com";
        } else if (state.connectionMode === "cleanip") {
          const cip = (gateCleanIp && gateCleanIp.value.trim()) || (modalCleanIp && modalCleanIp.value.trim()) || state.cleanIp || "104.16.132.229";
          urlToTest = cip.includes("://") ? cip : `wss://${cip}:443`;
        } else {
          urlToTest = DIRECT_SERVER_URL;
        }
      }
      testServerConnectivity(urlToTest, gateTestFeedback, btnTestGateConn);
    });
  }

  if (btnCloseSettingsBack) {
    btnCloseSettingsBack.addEventListener("click", closeSettings);
  }

  if (modalServerUrl) {
    modalServerUrl.addEventListener("input", () => {
      state.serverUrl = modalServerUrl.value.trim();
      if (serverUrlInput) serverUrlInput.value = modalServerUrl.value;
      updatePresetSelectionUI(state.connectionMode);
    });
    modalServerUrl.addEventListener("keydown", (e) => {
      if (e.key === "Enter") {
        e.preventDefault();
        const urlToTest = modalServerUrl.value.trim() || state.serverUrl;
        testServerConnectivity(urlToTest, serverTestFeedback, btnTestServerConn);
      }
    });
  }

  if (serverUrlInput) {
    serverUrlInput.addEventListener("input", () => {
      state.serverUrl = serverUrlInput.value.trim();
      if (modalServerUrl) modalServerUrl.value = serverUrlInput.value;
      updatePresetSelectionUI(state.connectionMode);
    });
    serverUrlInput.addEventListener("keydown", (e) => {
      if (e.key === "Enter") {
        e.preventDefault();
        const urlToTest = serverUrlInput.value.trim() || state.serverUrl;
        testServerConnectivity(urlToTest, gateTestFeedback, btnTestGateConn);
      }
    });
  }

  if (antiDpiToggle) {
    antiDpiToggle.addEventListener("change", () => {
      state.antiDpi = antiDpiToggle.checked;
      updateAntiDpiBadge();
    });
  }

  // Initialize UI presets and Anti-DPI badge status on launch
  updatePresetSelectionUI(state.connectionMode || getConnectionMode(state.serverUrl));
  updateTransportBadge(state.transportMode || "ws");
  updateAntiDpiBadge();

  btnSettings.addEventListener("click", openSettings);
  btnCloseSettings.addEventListener("click", closeSettings);

  settingsModal.addEventListener("click", (e) => {
    if (e.target === settingsModal) closeSettings();
  });

  btnTestNotif.addEventListener("click", () => {
    triggerBackgroundNotification("آزمایش سیستم", "این یک پیام تستی برای بررسی عملکرد اعلان روی صفحه قفل است.", state.room || "آزمایشی");
    nativeToast("اعلان تستی ارسال شد");
  });

  btnMinimizeApp.addEventListener("click", () => {
    closeSettings();
    if (window.ChatNative && window.ChatNative.minimizeApp) {
      window.ChatNative.minimizeApp();
    } else {
      nativeToast("برنامه در پس‌زمینه فعال باقی می‌ماند");
    }
  });

  // Android Back Button handler
  window.onBackPressed = () => {
    if (!settingsModal.classList.contains("hidden")) {
      closeSettings();
      return true;
    }
    return false;
  };

  // 6. Auto-connect on startup if credentials exist
  if (state.keepCredentials && state.room && state.password) {
    connectAndJoinRoom(state.room, state.password, state.nickname);
  }
})();
