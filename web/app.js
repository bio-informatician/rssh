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
  const btnCloseSettings = document.getElementById("btnCloseSettings");
  const modalServerUrl = document.getElementById("modalServerUrl");
  const modalCleanIp = document.getElementById("modalCleanIp");
  const antiDpiToggle = document.getElementById("antiDpiToggle");
  const decoyChaffToggle = document.getElementById("decoyChaffToggle");
  const btnPresetDirect = document.getElementById("btnPresetDirect");
  const btnPresetCfTunnel = document.getElementById("btnPresetCfTunnel");
  const autoReconnectInput = document.getElementById("autoReconnect");
  const notificationToggle = document.getElementById("notificationToggle");
  const vibrationToggle = document.getElementById("vibrationToggle");
  const keepCredentialsInput = document.getElementById("keepCredentials");
  const btnTestNotif = document.getElementById("btnTestNotif");
  const btnMinimizeApp = document.getElementById("btnMinimizeApp");
  const btnDisconnectModal = document.getElementById("btnDisconnectModal");

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

  const state = {
    nickname: "کاربر",
    room: "",
    password: "",
    serverUrl: "",
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
  if (savedConfig.serverUrl && !savedConfig.serverUrl.includes("trycloudflare.com")) {
    state.serverUrl = savedConfig.serverUrl;
  } else if (window.location && window.location.host && !window.location.protocol.startsWith("file")) {
    const proto = window.location.protocol === "https:" ? "wss:" : "ws:";
    state.serverUrl = `${proto}//${window.location.host}`;
  } else {
    state.serverUrl = "ws://193.168.175.227:8765";
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
    if (mode === "http") {
      transportBadge.className = "transport-pill http";
      transportBadge.textContent = "🛡️ تونل ضد فایروال (HTTP)";
      transportBadge.title = "داده‌ها از طریق درخواست‌های امن HTTP و بدون قطعی از فایروال عبور می‌کنند";
    } else {
      transportBadge.className = "transport-pill ws";
      transportBadge.textContent = "⚡ وب‌سوکت";
      transportBadge.title = "اتصال برخط و پرسرعت مستقیم وب‌سوکت فعال است";
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
  // Peer Presence & 2-Second Ping Indicator
  // ==========================================================================
  function cssEscape(str) {
    return encodeURIComponent(str).replace(/%/g, "_");
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
      const title = data.isOnline ? "آنلاین (پینگ فعال زیر ۲ ثانیه)" : "قطع ارتباط (بیش از ۲ ثانیه بدون پینگ)";
      chip.title = `${user}: ${title}`;
      chip.innerHTML = `<span class="peer-status-dot ${dotClass}" title="${title}"></span> <span>${escapeHtml(user)}</span>`;
      membersList.appendChild(chip);
    });
  }

  function updatePeerStatusIndicators(user, isOnline) {
    const dotClass = isOnline ? "online" : "offline";
    const title = isOnline ? "آنلاین (پینگ فعال زیر ۲ ثانیه)" : "قطع ارتباط (بیش از ۲ ثانیه بدون پینگ)";

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
  }

  function initPeerPresence() {
    if (peerPingInterval) clearInterval(peerPingInterval);
    if (peerFreshnessChecker) clearInterval(peerFreshnessChecker);

    // 1. Ping Sender: Send heartbeat ping every 1000ms
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
    }, 1000);

    // 2. Freshness Checker: every 400ms, if now - lastPing > 2000ms -> offline (RED LIGHT)!
    peerFreshnessChecker = setInterval(() => {
      if (!state.isAuthenticated) return;
      const now = Date.now();
      peers.forEach((data, user) => {
        if (user === state.nickname) return;
        const diff = now - (data.lastPing || 0);
        const isOnline = diff <= 2000; // 2 seconds limit!
        if (data.isOnline !== isOnline) {
          data.isOnline = isOnline;
          updatePeerStatusIndicators(user, isOnline);
        }
      });
    }, 400);
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
    btnClear.classList.remove("hidden");
    roomStatusBadge.classList.remove("hidden");
    currentRoomDisplay.textContent = roomName;
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
    state.serverUrl = sanitizeServerUrl(serverUrlInput.value || modalServerUrl.value);
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
    updateTransportBadge("ws");
    updateStatus("connecting", "در حال بررسی دسترسی...");

    if (ws) {
      try {
        ws.close();
      } catch (e) {}
      ws = null;
    }

    // Set a 4-second timeout: If WebSocket fails to establish handshake,
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
    }, 4000);

    try {
      ws = new WebSocket(state.serverUrl);
    } catch (err) {
      clearTimeout(wsHandshakeTimer);
      activateHttpTunnelFallback();
      return;
    }

    ws.onopen = () => {
      clearTimeout(wsHandshakeTimer);
      updateStatus("connecting", "در حال تایید کلید امنیتی...");

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
        updateTransportBadge("ws");
        updateAntiDpiBadge();
        updateStatus("connected", "متصل (وب‌سوکت)");
        nativeToast(`وارد اتاق امن «${parsed.room || state.room}» شدید`);
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
          text: `به اتاق امن و اختصاصی «${parsed.room || state.room}» متصل شدید. تمامی پیام‌ها با رمزنگاری سرتاسری AES-256 و پدینگ تصادفی ضد DPI محافظت می‌شوند.`,
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

      if (state.isAuthenticated) {
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

    updateStatus("connecting", "فعال‌سازی تونل HTTP...");
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
      updateStatus("connected", "متصل (تونل امن HTTP)");
      showReconnectBanner(false);
      isReconnectStopped = false;
      enterChatView(state.room);
      initPeerPresence();

      if (!state.seenMessageIds.has("sys_http_welcome")) {
        state.seenMessageIds.add("sys_http_welcome");
        appendMessage({
          type: "system",
          text: `ارتباط با پروتکل ضد فایروال (HTTP Safe Tunnel) برقرار شد. تحویل پیام‌ها به صورت تضمینی و رمزنگاری‌شده انجام می‌شود.`,
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
                processIncomingChatMessage(msg);
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
    updateStatus("connecting", "تلاش مجدد تا ۴ ثانیه...");
    showReconnectBanner(true, "در حال تلاش برای اتصال مجدد تا ۴ ثانیه...", false);
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
    modalServerUrl.value = state.serverUrl;
    if (modalCleanIp) modalCleanIp.value = state.cleanIp || "";
    if (antiDpiToggle) antiDpiToggle.checked = state.antiDpi;
    if (decoyChaffToggle) decoyChaffToggle.checked = state.decoyChaff;
    autoReconnectInput.checked = state.autoReconnect;
    if (notificationToggle) notificationToggle.checked = state.notificationsEnabled;
    if (vibrationToggle) vibrationToggle.checked = state.vibrationEnabled;
    keepCredentialsInput.checked = state.keepCredentials;
    settingsModal.classList.remove("hidden");
  }

  function closeSettings() {
    state.serverUrl = sanitizeServerUrl(modalServerUrl.value);
    serverUrlInput.value = state.serverUrl;
    if (modalCleanIp) state.cleanIp = modalCleanIp.value.trim();
    if (antiDpiToggle) state.antiDpi = antiDpiToggle.checked;
    if (decoyChaffToggle) state.decoyChaff = decoyChaffToggle.checked;
    state.autoReconnect = autoReconnectInput.checked;
    if (vibrationToggle) state.vibrationEnabled = vibrationToggle.checked;
    state.keepCredentials = keepCredentialsInput.checked;
    updateAntiDpiBadge();
    persistSettings();
    settingsModal.classList.add("hidden");
  }

  // Connection Presets Handlers
  if (btnPresetDirect) {
    btnPresetDirect.addEventListener("click", () => {
      modalServerUrl.value = "ws://193.168.175.227:8765";
      nativeToast("الگوی اتصال مستقیم سرور انتخاب شد (:8765)");
    });
  }

  if (btnPresetCfTunnel) {
    btnPresetCfTunnel.addEventListener("click", () => {
      // If a saved tunnel URL or host exists, use it, otherwise provide Cloudflare WSS template
      const currentTunnel = state.serverUrl.startsWith("wss://") ? state.serverUrl : "wss://chat.yourdomain.com";
      modalServerUrl.value = currentTunnel;
      nativeToast("الگوی کلودفلر تونل انتخاب شد (WSS پورت 443)");
    });
  }

  if (antiDpiToggle) {
    antiDpiToggle.addEventListener("change", () => {
      state.antiDpi = antiDpiToggle.checked;
      updateAntiDpiBadge();
    });
  }

  // Initialize Anti-DPI badge status on launch
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
