(() => {
  // DOM Elements
  const statusIndicator = document.getElementById("statusIndicator");
  const statusText = document.getElementById("statusText");
  const chatMessages = document.getElementById("chatMessages");
  const chatForm = document.getElementById("chatForm");
  const messageInput = document.getElementById("messageInput");
  const btnSettings = document.getElementById("btnSettings");
  const btnClear = document.getElementById("btnClear");
  const settingsModal = document.getElementById("settingsModal");
  const btnCloseSettings = document.getElementById("btnCloseSettings");
  const btnConnect = document.getElementById("btnConnect");
  const btnDisconnect = document.getElementById("btnDisconnect");
  const serverUrlInput = document.getElementById("serverUrl");
  const nicknameInput = document.getElementById("nickname");
  const roomNameInput = document.getElementById("roomName");
  const autoReconnectInput = document.getElementById("autoReconnect");
  const btnOpenSettingsHero = document.getElementById("btnOpenSettingsHero");

  // State
  let ws = null;
  let reconnectTimer = null;
  let isConnecting = false;
  let isManualDisconnect = false;

  // Load Saved Settings
  const savedSettings = JSON.parse(localStorage.getItem("rssh_chat_settings") || "{}");
  if (savedSettings.serverUrl) {
    serverUrlInput.value = savedSettings.serverUrl;
  } else if (window.location && window.location.host && !window.location.protocol.startsWith("file")) {
    const proto = window.location.protocol === "https:" ? "wss:" : "ws:";
    serverUrlInput.value = `${proto}//${window.location.host}`;
  }
  if (savedSettings.nickname) nicknameInput.value = savedSettings.nickname;
  if (savedSettings.roomName) roomNameInput.value = savedSettings.roomName;
  if (savedSettings.autoReconnect !== undefined) autoReconnectInput.checked = savedSettings.autoReconnect;

  function saveSettings() {
    const settings = {
      serverUrl: serverUrlInput.value.trim(),
      nickname: nicknameInput.value.trim() || "گوشی من",
      roomName: roomNameInput.value.trim() || "general",
      autoReconnect: autoReconnectInput.checked
    };
    localStorage.setItem("rssh_chat_settings", JSON.stringify(settings));
    return settings;
  }

  // Native Bridge Helper
  function nativeVibrate(ms = 40) {
    if (window.ChatNative && window.ChatNative.vibrate) {
      window.ChatNative.vibrate(ms);
    }
  }

  function nativeToast(msg) {
    if (window.ChatNative && window.ChatNative.showToast) {
      window.ChatNative.showToast(msg);
    }
  }

  function updateStatus(state, message) {
    statusIndicator.className = `status-dot ${state}`;
    statusText.textContent = message;
  }

  // Format Time
  function formatTime(date = new Date()) {
    const h = String(date.getHours()).padStart(2, "0");
    const m = String(date.getMinutes()).padStart(2, "0");
    return `${h}:${m}`;
  }

  // Append Message to UI
  function appendMessage({ type = "peer", sender = "", text = "", time = "" }) {
    // Remove welcome box if present
    const welcome = chatMessages.querySelector(".welcome-box");
    if (welcome) welcome.remove();

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

  function escapeHtml(str) {
    if (!str) return "";
    return String(str)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#039;");
  }

  // Connect to WebSocket Server
  function connect() {
    if (ws && (ws.readyState === WebSocket.OPEN || ws.readyState === WebSocket.CONNECTING)) {
      return;
    }

    const settings = saveSettings();
    let url = settings.serverUrl;
    if (!url) {
      nativeToast("لطفاً آدرس سرور را وارد کنید");
      openSettings();
      return;
    }

    // Auto-fix and sanitize protocol
    url = url.trim();
    if (url.startsWith("ws://http://")) {
      url = "ws://" + url.slice(15);
    } else if (url.startsWith("wss://https://")) {
      url = "wss://" + url.slice(16);
    } else if (url.startsWith("http://")) {
      url = "ws://" + url.slice(7);
    } else if (url.startsWith("https://")) {
      url = "wss://" + url.slice(8);
    } else if (!url.startsWith("ws://") && !url.startsWith("wss://")) {
      url = "ws://" + url;
    }
    serverUrlInput.value = url;

    clearTimeout(reconnectTimer);
    isManualDisconnect = false;
    isConnecting = true;
    updateStatus("connecting", "در حال اتصال...");

    appendMessage({
      type: "system",
      text: `در حال اتصال به ${url}...`
    });

    try {
      ws = new WebSocket(url);
    } catch (err) {
      updateStatus("disconnected", "خطای پروتکل");
      appendMessage({
        type: "system",
        text: `خطا در باز کردن وب‌سوکت: ${err.message}`
      });
      isConnecting = false;
      return;
    }

    ws.onopen = () => {
      isConnecting = false;
      updateStatus("connected", "متصل");
      nativeVibrate(60);
      nativeToast("به سرور متصل شدید");
      closeSettings();

      appendMessage({
        type: "system",
        text: `با موفقیت به سرور متصل شدید`
      });

      // Send join message if room / nickname configured
      const joinPayload = {
        type: "join",
        sender: settings.nickname,
        room: settings.roomName,
        time: formatTime()
      };
      try {
        ws.send(JSON.stringify(joinPayload));
      } catch (e) {}
    };

    ws.onmessage = (event) => {
      nativeVibrate(30);
      let data = event.data;
      try {
        const parsed = JSON.parse(data);
        if (parsed.type === "system") {
          appendMessage({ type: "system", text: parsed.text || parsed.message });
        } else {
          const isMe = parsed.sender === settings.nickname;
          appendMessage({
            type: isMe ? "me" : "peer",
            sender: parsed.sender || "Peer",
            text: parsed.text || parsed.message || JSON.stringify(parsed),
            time: parsed.time || formatTime()
          });
        }
      } catch (err) {
        // Plain text message format
        appendMessage({
          type: "peer",
          sender: "سرور / سرور چت",
          text: data,
          time: formatTime()
        });
      }
    };

    ws.onerror = (e) => {
      // ws onerror
    };

    ws.onclose = (event) => {
      isConnecting = false;
      updateStatus("disconnected", "قطع ارتباط");
      appendMessage({
        type: "system",
        text: `ارتباط با سرور قطع شد (${event.code ? "کد: " + event.code : "نامشخص"})`
      });

      if (!isManualDisconnect && settings.autoReconnect) {
        scheduleReconnect();
      }
    };
  }

  function disconnect() {
    isManualDisconnect = true;
    clearTimeout(reconnectTimer);
    if (ws) {
      ws.close();
      ws = null;
    }
    updateStatus("disconnected", "قطع شد");
    nativeToast("ارتباط با سرور متوقف شد");
  }

  function scheduleReconnect() {
    clearTimeout(reconnectTimer);
    updateStatus("connecting", "تلاش مجدد تا ۴ ثانیه...");
    reconnectTimer = setTimeout(() => {
      connect();
    }, 4000);
  }

  // Send Message
  chatForm.addEventListener("submit", (e) => {
    e.preventDefault();
    const text = messageInput.value.trim();
    if (!text) return;

    if (!ws || ws.readyState !== WebSocket.OPEN) {
      nativeToast("ابتدا به سرور وصل شوید");
      openSettings();
      return;
    }

    const settings = saveSettings();
    const payload = {
      type: "chat",
      sender: settings.nickname,
      room: settings.roomName,
      text: text,
      time: formatTime()
    };

    try {
      ws.send(JSON.stringify(payload));
      appendMessage({
        type: "me",
        sender: settings.nickname,
        text: text,
        time: formatTime()
      });
      messageInput.value = "";
      nativeVibrate(20);
    } catch (err) {
      nativeToast("خطا در ارسال پیام");
    }
  });

  // Presets click
  document.querySelectorAll(".preset-tag").forEach((tag) => {
    tag.addEventListener("click", () => {
      serverUrlInput.value = tag.getAttribute("data-url");
    });
  });

  // Settings Modal Controls
  function openSettings() {
    settingsModal.classList.remove("hidden");
  }

  function closeSettings() {
    settingsModal.classList.add("hidden");
    saveSettings();
  }

  btnSettings.addEventListener("click", openSettings);
  btnOpenSettingsHero?.addEventListener("click", openSettings);
  btnCloseSettings.addEventListener("click", closeSettings);

  settingsModal.addEventListener("click", (e) => {
    if (e.target === settingsModal) {
      closeSettings();
    }
  });

  btnConnect.addEventListener("click", () => {
    connect();
  });

  btnDisconnect.addEventListener("click", () => {
    disconnect();
  });

  btnClear.addEventListener("click", () => {
    chatMessages.innerHTML = "";
    appendMessage({
      type: "system",
      text: "تاریخچه چت پاکسازی شد"
    });
  });

  // Back button handling in Android WebView
  window.onBackPressed = () => {
    if (!settingsModal.classList.contains("hidden")) {
      closeSettings();
      return true; // handled
    }
    return false; // let activity exit
  };

  // Initial Auto Connect if configured
  if (savedSettings.serverUrl && savedSettings.autoReconnect) {
    connect();
  }
})();
