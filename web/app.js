(() => {
  // DOM Elements - Header & Status
  const statusIndicator = document.getElementById("statusIndicator");
  const statusText = document.getElementById("statusText");
  const roomStatusBadge = document.getElementById("roomStatusBadge");
  const currentRoomDisplay = document.getElementById("currentRoomDisplay");
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
  const autoReconnectInput = document.getElementById("autoReconnect");
  const keepCredentialsInput = document.getElementById("keepCredentials");
  const btnTestNotif = document.getElementById("btnTestNotif");
  const btnMinimizeApp = document.getElementById("btnMinimizeApp");
  const btnDisconnectModal = document.getElementById("btnDisconnectModal");

  // Application State
  let ws = null;
  let heartbeatTimer = null;
  let reconnectTimer = null;
  let isConnecting = false;
  let isManualDisconnect = false;
  let unreadCount = 0;
  const originalTitle = document.title;

  const state = {
    nickname: "کاربر",
    room: "",
    password: "",
    serverUrl: "",
    autoReconnect: true,
    keepCredentials: true,
    isAuthenticated: false,
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
  if (savedConfig.autoReconnect !== undefined) state.autoReconnect = savedConfig.autoReconnect;
  if (savedConfig.keepCredentials !== undefined) state.keepCredentials = savedConfig.keepCredentials;

  // Initialize Form Values
  serverUrlInput.value = state.serverUrl;
  modalServerUrl.value = state.serverUrl;
  gateNickname.value = state.nickname;
  gateRoomName.value = state.room;
  if (state.keepCredentials && state.password) {
    gateRoomPassword.value = state.password;
  }
  autoReconnectInput.checked = state.autoReconnect;
  keepCredentialsInput.checked = state.keepCredentials;

  function persistSettings() {
    state.serverUrl = sanitizeServerUrl(serverUrlInput.value.trim() || modalServerUrl.value.trim());
    state.nickname = gateNickname.value.trim() || "کاربر";
    state.autoReconnect = autoReconnectInput.checked;
    state.keepCredentials = keepCredentialsInput.checked;

    const dataToSave = {
      serverUrl: state.serverUrl,
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
    // Clean duplicate prefixes
    if (url.startsWith("ws://http://")) url = "ws://" + url.slice(15);
    else if (url.startsWith("wss://https://")) url = "wss://" + url.slice(16);
    else if (url.startsWith("http://")) url = "ws://" + url.slice(7);
    else if (url.startsWith("https://")) url = "wss://" + url.slice(8);
    else if (!url.startsWith("ws://") && !url.startsWith("wss://")) url = "ws://" + url;
    return url;
  }

  // 2. Native Bridge & Notification Helpers
  function nativeVibrate(ms = 60) {
    if (window.ChatNative && window.ChatNative.vibrate) {
      window.ChatNative.vibrate(ms);
    } else if (navigator.vibrate) {
      navigator.vibrate(ms);
    }
  }

  function nativeToast(msg) {
    if (window.ChatNative && window.ChatNative.showToast) {
      window.ChatNative.showToast(msg);
    }
  }

  function playAudioChime() {
    try {
      const AudioCtx = window.AudioContext || window.webkitAudioContext;
      if (!AudioCtx) return;
      const ctx = new AudioCtx();
      const now = ctx.currentTime;

      const osc = ctx.createOscillator();
      const gain = ctx.createGain();

      osc.type = "sine";
      osc.frequency.setValueAtTime(587.33, now); // D5
      osc.frequency.setValueAtTime(880.00, now + 0.09); // A5

      gain.gain.setValueAtTime(0.2, now);
      gain.gain.exponentialRampToValueAtTime(0.001, now + 0.3);

      osc.connect(gain);
      gain.connect(ctx.destination);

      osc.start(now);
      osc.stop(now + 0.3);
    } catch (ignored) {}
  }

  function triggerBackgroundNotification(sender, text, room) {
    // 1. Android APK Native Notification (Heads-up & Lock Screen)
    if (window.ChatNative && window.ChatNative.showNotification) {
      window.ChatNative.showNotification(sender, text, room);
      nativeVibrate(250);
      return;
    }

    // 2. Web Browser Notification
    playAudioChime();
    nativeVibrate(200);

    if ("Notification" in window && Notification.permission === "granted") {
      try {
        const notif = new Notification(`${sender} («${room}»)`, {
          body: text,
          icon: "apple-touch-icon.png",
          badge: "apple-touch-icon.png",
          tag: "rssh-chat-msg",
          renotify: true,
        });
        notif.onclick = () => {
          window.focus();
          notif.close();
        };
      } catch (e) {}
    }

    unreadCount++;
    document.title = `(${unreadCount}) پیام جدید - رخش چت`;
  }

  // Reset title on window focus
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

  function updateStatus(dotClass, text) {
    statusIndicator.className = `status-dot ${dotClass}`;
    statusText.textContent = text;
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

  function appendMessage({ type = "peer", sender = "", text = "", time = "" }) {
    const wrapper = document.createElement("div");
    wrapper.className = `msg-wrapper ${type}`;

    if (type === "system") {
      wrapper.innerHTML = `
        <div class="msg-bubble">
          <span>${escapeHtml(text)}</span>
        </div>
      `;
    } else {
      const isMe = type === "me";
      const timeStr = time || formatTime();
      wrapper.innerHTML = `
        <div class="msg-bubble">
          ${!isMe && sender ? `<div class="msg-sender">${escapeHtml(sender)}</div>` : ""}
          <div class="msg-text">${escapeHtml(text)}</div>
          <div class="msg-meta">
            <span class="msg-time">${timeStr}</span>
            ${isMe ? '<span class="msg-status">✓</span>' : ""}
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

  // 4. WebSocket & Room Protocol
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
    clearInterval(heartbeatTimer);
    isManualDisconnect = false;
    isConnecting = true;
    updateStatus("connecting", "در حال بررسی رمز...");

    if (ws) {
      try {
        ws.close();
      } catch (e) {}
      ws = null;
    }

    try {
      ws = new WebSocket(state.serverUrl);
    } catch (err) {
      isConnecting = false;
      updateStatus("disconnected", "خطای پروتکل");
      showGateError(`خطا در ارتباط با وب‌سوکت: ${err.message}`);
      return;
    }

    ws.onopen = () => {
      isConnecting = false;
      updateStatus("connecting", "در حال تایید دسترسی...");

      // Send join room authentication payload
      const joinPayload = {
        type: "join",
        room: state.room,
        password: state.password,
        sender: state.nickname,
        time: formatTime()
      };
      try {
        ws.send(JSON.stringify(joinPayload));
      } catch (e) {}

      // Start 20s Keepalive Heartbeat
      clearInterval(heartbeatTimer);
      heartbeatTimer = setInterval(() => {
        if (ws && ws.readyState === WebSocket.OPEN) {
          try {
            ws.send(JSON.stringify({ type: "ping" }));
          } catch (e) {}
        }
      }, 20000);
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

      // Authentication Success
      if (parsed.type === "auth_success") {
        updateStatus("connected", "متصل");
        nativeToast(`وارد اتاق «${parsed.room || state.room}» شدید`);
        enterChatView(parsed.room || state.room);
        appendMessage({
          type: "system",
          text: `به اتاق امن و اختصاصی «${parsed.room || state.room}» خوش آمدید.`
        });
        return;
      }

      // Authentication Error (Wrong Password or Access Denied)
      if (parsed.type === "auth_error") {
        updateStatus("disconnected", "رمز نادرست");
        showGateError(parsed.text || "رمز عبور اتاق نادرست است! اتصال ممکن نیست.");
        returnToRoomGate();
        try {
          ws.close();
        } catch (e) {}
        ws = null;
        return;
      }

      // System Messages within the room
      if (parsed.type === "system") {
        appendMessage({
          type: "system",
          text: parsed.text || parsed.message
        });
        return;
      }

      // Incoming Chat Messages
      if (parsed.type === "chat") {
        const isMe = parsed.sender === state.nickname;
        appendMessage({
          type: isMe ? "me" : "peer",
          sender: parsed.sender,
          text: parsed.text,
          time: parsed.time || formatTime()
        });

        // Trigger Notification if client is in background / phone locked
        const isAppHidden = document.hidden || 
                            !document.hasFocus() || 
                            (window.ChatNative && window.ChatNative.isAppForeground && !window.ChatNative.isAppForeground());

        if (!isMe) {
          if (isAppHidden) {
            triggerBackgroundNotification(parsed.sender, parsed.text, state.room);
          } else {
            playAudioChime();
            nativeVibrate(30);
          }
        }
      }
    };

    ws.onerror = () => {
      // Handled in onclose
    };

    ws.onclose = (event) => {
      isConnecting = false;
      clearInterval(heartbeatTimer);

      if (state.isAuthenticated) {
        updateStatus("disconnected", "ارتباط قطع شد");
        appendMessage({
          type: "system",
          text: "ارتباط با سرور چت قطع شد. در حال تلاش برای اتصال مجدد..."
        });

        if (!isManualDisconnect && state.autoReconnect) {
          scheduleReconnect();
        }
      } else {
        updateStatus("disconnected", "قطع");
      }
    };
  }

  function scheduleReconnect() {
    clearTimeout(reconnectTimer);
    updateStatus("connecting", "اتصال مجدد تا ۳ ثانیه...");
    reconnectTimer = setTimeout(() => {
      if (state.room && state.password) {
        connectAndJoinRoom(state.room, state.password, state.nickname);
      }
    }, 3500);
  }

  function leaveRoom() {
    isManualDisconnect = true;
    clearTimeout(reconnectTimer);
    clearInterval(heartbeatTimer);

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

  // 5. User Interactions & Event Handlers
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

  // Chat Send Form
  chatForm.addEventListener("submit", (e) => {
    e.preventDefault();
    const text = messageInput.value.trim();
    if (!text) return;

    if (!ws || ws.readyState !== WebSocket.OPEN) {
      nativeToast("ارتباط با سرور برقرار نیست");
      return;
    }

    const payload = {
      type: "chat",
      room: state.room,
      sender: state.nickname,
      text: text,
      time: formatTime()
    };

    try {
      ws.send(JSON.stringify(payload));
      appendMessage({
        type: "me",
        sender: state.nickname,
        text: text,
        time: formatTime()
      });
      messageInput.value = "";
      nativeVibrate(20);
    } catch (err) {
      nativeToast("خطا در ارسال پیام");
    }
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
    appendMessage({
      type: "system",
      text: "صفحه چت پاکسازی شد."
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
      nativeToast("اعلان در این مرورگر پشتیبانی نمی‌شود");
    }
  }

  btnEnableNotif?.addEventListener("click", requestNotificationAccess);
  btnNotification.addEventListener("click", () => {
    if (window.ChatNative && window.ChatNative.showNotification) {
      window.ChatNative.showNotification("تست اعلان رخش چت", "پیام تستی روی صفحه قفل با موفقیت نمایش داده شد.", state.room || "تست");
      nativeToast("اعلان تستی ارسال شد");
    } else {
      requestNotificationAccess();
    }
  });

  btnTestNotif?.addEventListener("click", () => {
    if (window.ChatNative && window.ChatNative.showNotification) {
      window.ChatNative.showNotification("تست اعلان صفحه قفل", "سرویس فعال است و پیام‌ها در حالت قفل بودن گوشی دریافت می‌شوند.", state.room || "عمومی");
      nativeToast("اعلان تستی ارسال شد");
    } else {
      triggerBackgroundNotification("تست سیستم", "این یک پیام تستی برای بررسی عملکرد نوتیفیکیشن است.", state.room || "تست");
    }
  });

  // Minimize App Button (Puts Android APK to background without closing socket)
  btnMinimizeApp?.addEventListener("click", () => {
    closeSettings();
    if (window.ChatNative && window.ChatNative.minimizeApp) {
      window.ChatNative.minimizeApp();
    } else {
      nativeToast("برای پنهان شدن صفحه، دکمه هوم یا پاور گوشی را بزنید");
    }
  });

  // Settings Modal Controls
  function openSettings() {
    modalServerUrl.value = state.serverUrl;
    settingsModal.classList.remove("hidden");
  }

  function closeSettings() {
    settingsModal.classList.add("hidden");
    state.serverUrl = sanitizeServerUrl(modalServerUrl.value);
    serverUrlInput.value = state.serverUrl;
    persistSettings();
  }

  btnSettings.addEventListener("click", openSettings);
  btnCloseSettings.addEventListener("click", closeSettings);

  settingsModal.addEventListener("click", (e) => {
    if (e.target === settingsModal) closeSettings();
  });

  // Android Native Back Button Handler
  window.onBackPressed = () => {
    if (!settingsModal.classList.contains("hidden")) {
      closeSettings();
      return true;
    }
    if (state.isAuthenticated) {
      // Don't close app on back, let native moveTaskToBack minimize it
      return false;
    }
    return false;
  };

  // Initial Auto-Join if saved credentials exist
  if (state.keepCredentials && state.room && state.password && state.autoReconnect) {
    connectAndJoinRoom(state.room, state.password, state.nickname);
  }
})();
