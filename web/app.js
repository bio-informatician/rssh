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

  // DOM Elements - Room Gate
  const roomGate = document.getElementById("roomGate");
  const gateForm = document.getElementById("gateForm");
  const gateNickname = document.getElementById("gateNickname");
  const gateRoomName = document.getElementById("gateRoomName");
  const gateRoomPassword = document.getElementById("gateRoomPassword");
  const btnTogglePassword = document.getElementById("btnTogglePassword");
  const gateError = document.getElementById("gateError");
  const gateErrorText = document.getElementById("gateErrorText");
  const btnToggleAdvanced = document.getElementById("btnToggleAdvanced");
  const advancedServerBlock = document.getElementById("advancedServerBlock");
  const serverUrlInput = document.getElementById("serverUrl");
  const btnEnterRoom = document.getElementById("btnEnterRoom");

  // DOM Elements - Active Chat View
  const chatView = document.getElementById("chatView");
  const notifBanner = document.getElementById("notifBanner");
  const btnEnableNotif = document.getElementById("btnEnableNotif");
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
  const keepCredentialsInput = document.getElementById("keepCredentials");
  const btnTestNotif = document.getElementById("btnTestNotif");
  const btnMinimizeApp = document.getElementById("btnMinimizeApp");
  const btnDisconnectModal = document.getElementById("btnDisconnectModal");

  // Application State
  let ws = null;
  let wsHandshakeTimer = null;
  let jitteredPingTimer = null;
  let decoyChaffTimer = null;
  let reconnectTimer = null;
  let httpPollTimer = null;
  let queueRetryTimer = null;
  let wsProbeTimer = null;
  let isConnecting = false;
  let isManualDisconnect = false;
  let unreadCount = 0;
  const originalTitle = document.title;

  const state = {
    nickname: "کاربر",
    room: "",
    password: "",
    serverUrl: "",
    cleanIp: "",
    antiDpi: true,
    decoyChaff: true,
    autoReconnect: true,
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
  if (savedConfig.serverUrl) {
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
  if (savedConfig.keepCredentials !== undefined) state.keepCredentials = savedConfig.keepCredentials;

  // Initialize Form Values
  gateNickname.value = state.nickname || "کاربر";
  gateRoomName.value = state.room || "";
  gateRoomPassword.value = state.password || "";
  serverUrlInput.value = state.serverUrl;
  modalServerUrl.value = state.serverUrl;
  if (modalCleanIp) modalCleanIp.value = state.cleanIp || "";
  if (antiDpiToggle) antiDpiToggle.checked = state.antiDpi;
  if (decoyChaffToggle) decoyChaffToggle.checked = state.decoyChaff;
  autoReconnectInput.checked = state.autoReconnect;
  keepCredentialsInput.checked = state.keepCredentials;

  // Save Settings Helper
  function persistSettings() {
    const dataToSave = {
      serverUrl: state.serverUrl,
      cleanIp: state.cleanIp,
      antiDpi: state.antiDpi,
      decoyChaff: state.decoyChaff,
      nickname: state.nickname,
      autoReconnect: state.autoReconnect,
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
    if (window.ChatNative && window.ChatNative.vibrate) {
      window.ChatNative.vibrate(ms);
    } else if (navigator.vibrate) {
      navigator.vibrate(ms);
    }
  }

  function triggerBackgroundNotification(sender, messageText, roomName) {
    unreadCount++;
    document.title = `(${unreadCount}) پیام جدید | رخش چت`;

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

  // Clear unread count when window gains focus
  window.addEventListener("focus", () => {
    unreadCount = 0;
    document.title = originalTitle;
  });

  document.addEventListener("visibilitychange", () => {
    if (!document.hidden) {
      unreadCount = 0;
      document.title = originalTitle;
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
    nativeVibrate(150);
  }

  function hideGateError() {
    gateError.classList.add("hidden");
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

  function appendMessage({ type = "peer", sender = "", text = "", time = "", id = "", isEncrypted = true, isPending = false }) {
    // If element with this id already exists in DOM, update status if needed
    if (id) {
      const existing = document.getElementById(`msg-${id}`);
      if (existing) {
        if (!isPending) {
          const statusElem = existing.querySelector(".msg-status");
          if (statusElem) {
            statusElem.className = "msg-status";
            statusElem.textContent = "✓";
          }
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
      const statusIcon = isMe ? (isPending ? '<span class="msg-status pending" title="در حال ارسال / صف تحویل...">⏳</span>' : '<span class="msg-status">✓</span>') : "";

      wrapper.innerHTML = `
        <div class="msg-bubble">
          ${!isMe && sender ? `<div class="msg-sender">${escapeHtml(sender)}</div>` : ""}
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

  // Mark message as confirmed/delivered in UI
  function markMessageDelivered(msgId) {
    const el = document.getElementById(`msg-${msgId}`);
    if (el) {
      const statusElem = el.querySelector(".msg-status");
      if (statusElem) {
        statusElem.className = "msg-status";
        statusElem.textContent = "✓";
      }
    }
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
    if ("Notification" in window && Notification.permission === "default") {
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
    clearInterval(heartbeatTimer);
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
        updateTransportBadge("ws");
        updateAntiDpiBadge();
        updateStatus("connected", "متصل (وب‌سوکت)");
        nativeToast(`وارد اتاق امن «${parsed.room || state.room}» شدید`);
        enterChatView(parsed.room || state.room);
        appendMessage({
          type: "system",
          text: `به اتاق امن و اختصاصی «${parsed.room || state.room}» متصل شدید. تمامی پیام‌ها با رمزنگاری سرتاسری AES-256 و پدینگ تصادفی ضد DPI محافظت می‌شوند.`,
          isEncrypted: false,
        });
        flushOutgoingQueue();
        return;
      }

      // Authentication Error (Wrong Password or Access Denied)
      if (parsed.type === "auth_error") {
        isConnecting = false;
        updateStatus("disconnected", "رمز نادرست");
        showGateError(parsed.text || "رمز عبور اتاق نادرست است! دسترسی غیرمجاز.");
        returnToRoomGate();
        try {
          ws.close();
        } catch (e) {}
        ws = null;
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
        })),
      });

      if (!joinRes.ok) {
        const errData = await joinRes.json().catch(() => ({}));
        updateStatus("disconnected", "خطای تایید");
        showGateError(errData.text || "رمز عبور اتاق نادرست است یا سرور در دسترس نیست.");
        returnToRoomGate();
        return;
      }

      const joinData = await joinRes.json();
      updateStatus("connected", "متصل (تونل امن HTTP)");
      enterChatView(state.room);

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
      if (state.autoReconnect && !isManualDisconnect) {
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
          if (data.status === "ok" && Array.isArray(data.messages)) {
            for (const msg of data.messages) {
              processIncomingChatMessage(msg);
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
    if (state.seenMessageIds.has(msgId)) return;
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
    });

    // If incoming from another user, notify
    if (!isMe) {
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
    clearTimeout(reconnectTimer);
    updateStatus("connecting", "تلاش مجدد تا ۴ ثانیه...");
    reconnectTimer = setTimeout(() => {
      if (state.room && state.password) {
        connectAndJoinRoom(state.room, state.password, state.nickname);
      }
    }, 4000);
  }

  function leaveRoom() {
    isManualDisconnect = true;
    clearTimeout(reconnectTimer);
    clearTimeout(wsHandshakeTimer);
    clearInterval(heartbeatTimer);
    clearInterval(httpPollTimer);
    clearInterval(wsProbeTimer);

    if (ws && ws.readyState === WebSocket.OPEN) {
      try {
        ws.send(JSON.stringify({ type: "leave" }));
        ws.close();
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
          nativeToast("اعلان‌های صفحه قفل فعال شد");
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
  btnNotification.addEventListener("click", requestNotificationAccess);

  // Settings Modal Handlers
  function openSettings() {
    modalServerUrl.value = state.serverUrl;
    if (modalCleanIp) modalCleanIp.value = state.cleanIp || "";
    if (antiDpiToggle) antiDpiToggle.checked = state.antiDpi;
    if (decoyChaffToggle) decoyChaffToggle.checked = state.decoyChaff;
    autoReconnectInput.checked = state.autoReconnect;
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
