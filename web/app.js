/**
 * Rakhssh SSH - Modern Terminal Client
 * Supports Native Java SSH Socket Bridge & WebSocket Tunnel Relay
 */

(function() {
  'use strict';

  // State
  const state = {
    connected: false,
    connecting: false,
    currentHost: '',
    currentPort: 22,
    currentUser: '',
    protocol: 'direct', // 'direct' or 'websocket'
    ctrlActive: false,
    altActive: false,
    fontSize: 14,
    theme: 'cyber',
    cursorStyle: 'block',
    cursorBlink: true,
    wakeLock: true,
    haptics: true,
    activeProfile: null,
    savedProfiles: []
  };

  // Color Themes
  const THEMES = {
    cyber: {
      background: '#05080f',
      foreground: '#e6edf3',
      cursor: '#10b981',
      cursorAccent: '#05080f',
      selectionBackground: '#10b98144',
      black: '#0a0e17',
      red: '#ef4444',
      green: '#10b981',
      yellow: '#f59e0b',
      blue: '#3b82f6',
      magenta: '#a855f7',
      cyan: '#06b6d4',
      white: '#f3f4f6',
      brightBlack: '#4b5563',
      brightRed: '#f87171',
      brightGreen: '#34d399',
      brightYellow: '#fbbf24',
      brightBlue: '#60a5fa',
      brightMagenta: '#c084fc',
      brightCyan: '#22d3ee',
      brightWhite: '#ffffff'
    },
    dracula: {
      background: '#282a36',
      foreground: '#f8f8f2',
      cursor: '#ff79c6',
      cursorAccent: '#282a36',
      selectionBackground: '#44475a',
      black: '#21222c',
      red: '#ff5555',
      green: '#50fa7b',
      yellow: '#f1fa8c',
      blue: '#bd93f9',
      magenta: '#ff79c6',
      cyan: '#8be9fd',
      white: '#f8f8f2',
      brightBlack: '#6272a4',
      brightRed: '#ff6e6e',
      brightGreen: '#69ff94',
      brightYellow: '#ffffa5',
      brightBlue: '#d6acff',
      brightMagenta: '#ff92df',
      brightCyan: '#a4ffff',
      brightWhite: '#ffffff'
    },
    solarized: {
      background: '#002b36',
      foreground: '#839496',
      cursor: '#2aa198',
      cursorAccent: '#002b36',
      selectionBackground: '#073642',
      black: '#073642',
      red: '#dc322f',
      green: '#859900',
      yellow: '#b58900',
      blue: '#268bd2',
      magenta: '#d33682',
      cyan: '#2aa198',
      white: '#eee8d5',
      brightBlack: '#586e75',
      brightRed: '#cb4b16',
      brightGreen: '#586e75',
      brightYellow: '#657b83',
      brightBlue: '#839496',
      brightMagenta: '#6c71c4',
      brightCyan: '#93a1a1',
      brightWhite: '#fdf6e3'
    },
    matrix: {
      background: '#000000',
      foreground: '#00ff66',
      cursor: '#00ff66',
      cursorAccent: '#000000',
      selectionBackground: '#005522',
      black: '#001100',
      red: '#ff2222',
      green: '#00ee44',
      yellow: '#ffee00',
      blue: '#22bbff',
      magenta: '#ee44ee',
      cyan: '#00ffff',
      white: '#ffffff',
      brightBlack: '#006622',
      brightRed: '#ff4444',
      brightGreen: '#22ff66',
      brightYellow: '#ffff44',
      brightBlue: '#44ccff',
      brightMagenta: '#ff66ff',
      brightCyan: '#44ffff',
      brightWhite: '#ffffff'
    },
    oneDark: {
      background: '#1e222a',
      foreground: '#abb2bf',
      cursor: '#528bff',
      cursorAccent: '#1e222a',
      selectionBackground: '#3e4451',
      black: '#282c34',
      red: '#e06c75',
      green: '#98c379',
      yellow: '#e5c07b',
      blue: '#61afef',
      magenta: '#c678dd',
      cyan: '#56b6c2',
      white: '#abb2bf',
      brightBlack: '#5c6370',
      brightRed: '#be5046',
      brightGreen: '#98c379',
      brightYellow: '#d19a66',
      brightBlue: '#61afef',
      brightMagenta: '#c678dd',
      brightCyan: '#56b6c2',
      brightWhite: '#ffffff'
    }
  };

  // DOM Elements
  const el = {
    topBar: document.getElementById('topBar'),
    btnToggleDrawer: document.getElementById('btnToggleDrawer'),
    sessionIndicator: document.getElementById('sessionIndicator'),
    sessionStatusText: document.getElementById('sessionStatusText'),
    btnReconnect: document.getElementById('btnReconnect'),
    btnDisconnect: document.getElementById('btnDisconnect'),
    btnOpenSettings: document.getElementById('btnOpenSettings'),
    terminalContainer: document.getElementById('terminalContainer'),
    terminalDiv: document.getElementById('terminal'),
    terminalOverlay: document.getElementById('terminalOverlay'),
    btnOverlayConnect: document.getElementById('btnOverlayConnect'),
    accessoryBar: document.getElementById('accessoryBar'),
    drawerOverlay: document.getElementById('drawerOverlay'),
    btnCloseDrawer: document.getElementById('btnCloseDrawer'),
    settingsModal: document.getElementById('settingsModal'),
    btnCloseSettings: document.getElementById('btnCloseSettings'),
    // Form
    connectionForm: document.getElementById('connectionForm'),
    inputHost: document.getElementById('inputHost'),
    inputPort: document.getElementById('inputPort'),
    inputUsername: document.getElementById('inputUsername'),
    tabAuthPassword: document.getElementById('tabAuthPassword'),
    tabAuthKey: document.getElementById('tabAuthKey'),
    passwordFieldGroup: document.getElementById('passwordFieldGroup'),
    keyFieldGroup: document.getElementById('keyFieldGroup'),
    inputPassword: document.getElementById('inputPassword'),
    btnTogglePassword: document.getElementById('btnTogglePassword'),
    inputPrivateKey: document.getElementById('inputPrivateKey'),
    inputKeyPassphrase: document.getElementById('inputKeyPassphrase'),
    radioDirectMode: document.getElementById('radioDirectMode'),
    radioWsMode: document.getElementById('radioWsMode'),
    wsUrlRow: document.getElementById('wsUrlRow'),
    inputWsUrl: document.getElementById('inputWsUrl'),
    chkSaveProfile: document.getElementById('chkSaveProfile'),
    btnSubmitConnect: document.getElementById('btnSubmitConnect'),
    savedProfilesList: document.getElementById('savedProfilesList'),
    presetDirectServer: document.getElementById('presetDirectServer'),
    presetWebSsh: document.getElementById('presetWebSsh'),
    // Settings
    btnFontDec: document.getElementById('btnFontDec'),
    btnFontInc: document.getElementById('btnFontInc'),
    fontSizeVal: document.getElementById('fontSizeVal'),
    selectTheme: document.getElementById('selectTheme'),
    selectCursor: document.getElementById('selectCursor'),
    chkCursorBlink: document.getElementById('chkCursorBlink'),
    chkWakeLock: document.getElementById('chkWakeLock'),
    chkHaptics: document.getElementById('chkHaptics'),
    btnClearScreen: document.getElementById('btnClearScreen'),
    // Keys
    keyCtrl: document.getElementById('keyCtrl'),
    keyAlt: document.getElementById('keyAlt'),
    keyClear: document.getElementById('keyClear'),
    keyPaste: document.getElementById('keyPaste')
  };

  // xterm.js instance
  let term = null;
  let fitAddon = null;
  let activeWs = null;

  function initTerminal() {
    term = new Terminal({
      cursorBlink: state.cursorBlink,
      cursorStyle: state.cursorStyle,
      fontSize: state.fontSize,
      fontFamily: 'Menlo, Monaco, "Courier New", monospace',
      theme: THEMES[state.theme] || THEMES.cyber,
      allowTransparency: true,
      scrollback: 5000,
      disableStdin: false
    });

    if (window.FitAddon && window.FitAddon.FitAddon) {
      fitAddon = new window.FitAddon.FitAddon();
      term.loadAddon(fitAddon);
    }

    term.open(el.terminalDiv);

    // Initial resize
    setTimeout(fitTerminal, 100);

    // Terminal data input handler
    term.onData(data => {
      handleUserInput(data);
    });

    // Write banner
    showWelcomeBanner();
  }

  function showWelcomeBanner() {
    term.clear();
    term.writeln('\x1b[1;36m=====================================================\x1b[0m');
    term.writeln('\x1b[1;32m       ⚡ رخش ترمینال SSH - نسخه ۱.۰.۰ (Rakhssh SSH) \x1b[0m');
    term.writeln('\x1b[1;36m=====================================================\x1b[0m');
    term.writeln('\x1b[90m• پشتیبانی از اتصال مستقیم سوکت SSHv2 (RFC 4253)');
    term.writeln('• پشتیبانی از کلید خصوصی OpenSSH / RSA / Ed25519');
    term.writeln('• قابلیت اتصال از بستر وب اس اس اچ و تونل‌های ضد فیلتر\x1b[0m');
    term.writeln('');
  }

  function fitTerminal() {
    if (!fitAddon || !term) return;
    try {
      fitAddon.fit();
      const cols = term.cols;
      const rows = term.rows;
      if (window.AndroidSSH && state.connected) {
        window.AndroidSSH.resize(cols, rows);
      }
    } catch (e) {
      console.warn('fit error', e);
    }
  }

  // Handle Input with virtual modifier keys (CTRL, ALT)
  function handleUserInput(data) {
    if (state.ctrlActive) {
      state.ctrlActive = false;
      el.keyCtrl.classList.remove('active');

      // Convert letter to control code
      if (data.length === 1) {
        const code = data.toUpperCase().charCodeAt(0);
        if (code >= 64 && code <= 95) {
          sendToSsh(String.fromCharCode(code - 64));
          return;
        }
      }
    }

    if (state.altActive) {
      state.altActive = false;
      el.keyAlt.classList.remove('active');
      sendToSsh('\x1b' + data);
      return;
    }

    sendToSsh(data);
  }

  function sendToSsh(text) {
    if (state.protocol === 'websocket' && activeWs && activeWs.readyState === WebSocket.OPEN) {
      activeWs.send(text);
    } else if (window.AndroidSSH) {
      window.AndroidSSH.sendData(text);
    }
  }

  // Base64 incoming data receiver from Java SshBridge
  window.onTerminalDataB64 = function(b64) {
    if (!term || !b64) return;
    try {
      const binaryStr = atob(b64);
      const len = binaryStr.length;
      const bytes = new Uint8Array(len);
      for (let i = 0; i < len; i++) {
        bytes[i] = binaryStr.charCodeAt(i);
      }
      term.write(bytes);
    } catch (e) {
      console.error('Data decode error', e);
    }
  };

  // SSH Status Receiver from Java SshBridge
  window.onSshStatus = function(status, message) {
    console.log('SSH Status:', status, message);

    el.sessionIndicator.className = 'session-indicator';

    if (status === 'CONNECTING' || status === 'AUTHENTICATING' || status === 'INITIALIZING_SHELL') {
      state.connecting = true;
      state.connected = false;
      el.sessionIndicator.classList.add('connecting');
      el.sessionStatusText.textContent = message || 'در حال اتصال...';
      term.writeln('\x1b[33m--> ' + (message || status) + '\x1b[0m');
    } else if (status === 'CONNECTED') {
      state.connecting = false;
      state.connected = true;
      el.sessionIndicator.classList.add('connected');
      el.sessionStatusText.textContent = state.currentUser + '@' + state.currentHost + ':' + state.currentPort;
      el.btnReconnect.style.display = 'none';
      el.btnDisconnect.style.display = 'flex';
      el.terminalOverlay.classList.add('hidden');
      closeDrawer();
      term.writeln('\x1b[1;32m--> ' + message + '\x1b[0m\r\n');
      fitTerminal();
    } else if (status === 'DISCONNECTED') {
      state.connecting = false;
      state.connected = false;
      el.sessionIndicator.classList.add('disconnected');
      el.sessionStatusText.textContent = 'قطع ارتباط';
      el.btnReconnect.style.display = 'flex';
      el.btnDisconnect.style.display = 'none';
      term.writeln('\r\n\x1b[1;31m--> ' + message + '\x1b[0m');
    } else if (status === 'ERROR') {
      state.connecting = false;
      state.connected = false;
      el.sessionIndicator.classList.add('disconnected');
      el.sessionStatusText.textContent = 'خطای اتصال';
      el.btnReconnect.style.display = 'flex';
      el.btnDisconnect.style.display = 'none';
      term.writeln('\r\n\x1b[1;31m[ERROR] ' + message + '\x1b[0m\r\n');
      if (window.AndroidSSH) {
        window.AndroidSSH.toast(message);
      } else {
        alert(message);
      }
    }
  };

  // Connect Handler
  function connectToServer(profile) {
    const host = profile.host.trim();
    const port = parseInt(profile.port, 10) || 22;
    const user = profile.user.trim();
    const authType = profile.authType || 'password';
    const secret = profile.secret || '';
    const passphrase = profile.passphrase || '';
    const protocol = profile.protocol || 'direct';

    if (!host) {
      alert('لطفاً آدرس سرور را وارد کنید.');
      return;
    }
    if (!user) {
      alert('لطفاً نام کاربری را وارد کنید.');
      return;
    }

    state.currentHost = host;
    state.currentPort = port;
    state.currentUser = user;
    state.protocol = protocol;
    state.activeProfile = profile;

    term.clear();
    showWelcomeBanner();

    if (protocol === 'websocket') {
      connectWebSocket(profile);
    } else {
      // Direct Native SSH through Java SshBridge
      if (window.AndroidSSH) {
        const cols = term ? term.cols : 80;
        const rows = term ? term.rows : 24;
        window.AndroidSSH.connect(host, port, user, authType, secret, passphrase, cols, rows);
      } else {
        window.onSshStatus('ERROR', 'پل محلی SSH جاوا فقط در محیط برنامه اندروید فعال است. برای مرورگر وب اس اس اچ از حالت تونل وب‌سوکت استفاده کنید.');
      }
    }

    if (el.chkSaveProfile.checked) {
      saveProfile(profile);
    }
  }

  // WebSocket SSH Tunnel connection
  function connectWebSocket(profile) {
    const wsUrl = el.inputWsUrl.value.trim() || `wss://${profile.host}:${profile.port}/ws/ssh`;
    window.onSshStatus('CONNECTING', 'در حال اتصال به تونل وب اس اس اچ: ' + wsUrl);

    try {
      if (activeWs) {
        activeWs.close();
      }
      activeWs = new WebSocket(wsUrl);
      activeWs.binaryType = 'arraybuffer';

      activeWs.onopen = () => {
        window.onSshStatus('CONNECTED', 'اتصال به تونل وب اس اس اچ برقرار شد.');
        // Send initial resize
        activeWs.send(JSON.stringify({
          type: 'init',
          cols: term.cols,
          rows: term.rows,
          host: profile.host,
          port: profile.port,
          user: profile.user,
          secret: profile.secret
        }));
      };

      activeWs.onmessage = (event) => {
        if (typeof event.data === 'string') {
          term.write(event.data);
        } else {
          term.write(new Uint8Array(event.data));
        }
      };

      activeWs.onerror = (err) => {
        window.onSshStatus('ERROR', 'خطا در اتصال به وب‌سوکت SSH.');
      };

      activeWs.onclose = () => {
        window.onSshStatus('DISCONNECTED', 'اتصال وب اس اس اچ پایان یافت.');
      };
    } catch (e) {
      window.onSshStatus('ERROR', 'خطای راه‌اندازی سوکت: ' + e.message);
    }
  }

  function disconnectCurrent() {
    if (activeWs) {
      activeWs.close();
      activeWs = null;
    }
    if (window.AndroidSSH) {
      window.AndroidSSH.disconnect();
    } else {
      window.onSshStatus('DISCONNECTED', 'ارتباط قطع شد.');
    }
  }

  // Haptic feedback
  function haptic(ms = 25) {
    if (!state.haptics) return;
    if (window.AndroidSSH) {
      window.AndroidSSH.vibrate(ms);
    } else if (navigator.vibrate) {
      navigator.vibrate(ms);
    }
  }

  // Saved Profiles Storage
  function loadProfiles() {
    let raw = '[]';
    if (window.AndroidSSH) {
      raw = window.AndroidSSH.getSavedSessionProfiles();
    } else {
      raw = localStorage.getItem('rssh_terminal_profiles') || '[]';
    }

    try {
      state.savedProfiles = JSON.parse(raw);
    } catch (e) {
      state.savedProfiles = [];
    }
    renderProfilesList();
  }

  function saveProfile(prof) {
    const list = state.savedProfiles.filter(p => p.host !== prof.host || p.user !== prof.user);
    list.unshift({
      name: prof.name || `${prof.user}@${prof.host}`,
      host: prof.host,
      port: prof.port,
      user: prof.user,
      authType: prof.authType,
      protocol: prof.protocol,
      savedAt: Date.now()
    });

    state.savedProfiles = list.slice(0, 15);
    const json = JSON.stringify(state.savedProfiles);

    if (window.AndroidSSH) {
      window.AndroidSSH.saveSessionProfiles(json);
    } else {
      localStorage.setItem('rssh_terminal_profiles', json);
    }
    renderProfilesList();
  }

  function renderProfilesList() {
    el.savedProfilesList.innerHTML = '';
    if (state.savedProfiles.length === 0) {
      el.savedProfilesList.innerHTML = '<div style="color:var(--text-muted);font-size:12px;text-align:center;padding:12px;">هنوز سروری ذخیره نشده است.</div>';
      return;
    }

    state.savedProfiles.forEach((p, idx) => {
      const item = document.createElement('div');
      item.className = 'profile-item';
      item.innerHTML = `
        <div class="profile-info">
          <div class="profile-name">${escapeHtml(p.name)}</div>
          <div class="profile-addr">${escapeHtml(p.user)}@${escapeHtml(p.host)}:${p.port}</div>
        </div>
        <div class="profile-actions">
          <button class="profile-btn connect" data-idx="${idx}">⚡ اتصال</button>
          <button class="profile-btn delete" data-idx="${idx}">🗑️</button>
        </div>
      `;
      el.savedProfilesList.appendChild(item);
    });

    el.savedProfilesList.querySelectorAll('.profile-btn.connect').forEach(btn => {
      btn.addEventListener('click', () => {
        haptic();
        const p = state.savedProfiles[parseInt(btn.dataset.idx, 10)];
        if (p) {
          el.inputHost.value = p.host;
          el.inputPort.value = p.port;
          el.inputUsername.value = p.user;
          connectToServer(p);
        }
      });
    });

    el.savedProfilesList.querySelectorAll('.profile-btn.delete').forEach(btn => {
      btn.addEventListener('click', () => {
        haptic();
        const idx = parseInt(btn.dataset.idx, 10);
        state.savedProfiles.splice(idx, 1);
        const json = JSON.stringify(state.savedProfiles);
        if (window.AndroidSSH) {
          window.AndroidSSH.saveSessionProfiles(json);
        } else {
          localStorage.setItem('rssh_terminal_profiles', json);
        }
        renderProfilesList();
      });
    });
  }

  function escapeHtml(str) {
    return (str || '').replace(/[&<>"']/g, m => ({
      '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
    }[m]));
  }

  // Modals & Drawers control
  function openDrawer() {
    haptic();
    el.drawerOverlay.classList.remove('hidden');
  }

  function closeDrawer() {
    el.drawerOverlay.classList.add('hidden');
  }

  function openSettings() {
    haptic();
    el.settingsModal.classList.remove('hidden');
  }

  function closeSettings() {
    el.settingsModal.classList.add('hidden');
  }

  window.onBackPressed = function() {
    if (!el.drawerOverlay.classList.contains('hidden')) {
      closeDrawer();
      return true;
    }
    if (!el.settingsModal.classList.contains('hidden')) {
      closeSettings();
      return true;
    }
    return false;
  };

  // Event Listeners
  function setupEvents() {
    window.addEventListener('resize', fitTerminal);

    el.btnToggleDrawer.addEventListener('click', openDrawer);
    el.btnCloseDrawer.addEventListener('click', closeDrawer);
    el.btnOverlayConnect.addEventListener('click', openDrawer);

    el.btnOpenSettings.addEventListener('click', openSettings);
    el.btnCloseSettings.addEventListener('click', closeSettings);

    el.btnDisconnect.addEventListener('click', () => {
      haptic();
      disconnectCurrent();
    });

    el.btnReconnect.addEventListener('click', () => {
      haptic();
      if (state.activeProfile) {
        connectToServer(state.activeProfile);
      } else {
        openDrawer();
      }
    });

    // Auth Tabs
    el.tabAuthPassword.addEventListener('click', () => {
      haptic();
      el.tabAuthPassword.classList.add('active');
      el.tabAuthKey.classList.remove('active');
      el.passwordFieldGroup.style.display = 'block';
      el.keyFieldGroup.style.display = 'none';
    });

    el.tabAuthKey.addEventListener('click', () => {
      haptic();
      el.tabAuthKey.classList.add('active');
      el.tabAuthPassword.classList.remove('active');
      el.passwordFieldGroup.style.display = 'none';
      el.keyFieldGroup.style.display = 'block';
    });

    // Password show/hide toggle
    el.btnTogglePassword.addEventListener('click', () => {
      const type = el.inputPassword.getAttribute('type') === 'password' ? 'text' : 'password';
      el.inputPassword.setAttribute('type', type);
      el.btnTogglePassword.textContent = type === 'password' ? '👁️' : '🙈';
    });

    // Radio Protocol switch
    el.radioDirectMode.addEventListener('click', () => {
      el.radioDirectMode.classList.add('active');
      el.radioWsMode.classList.remove('active');
      el.wsUrlRow.style.display = 'none';
    });

    el.radioWsMode.addEventListener('click', () => {
      el.radioWsMode.classList.add('active');
      el.radioDirectMode.classList.remove('active');
      el.wsUrlRow.style.display = 'block';
    });

    // Presets
    el.presetDirectServer.addEventListener('click', () => {
      haptic();
      el.presetDirectServer.classList.add('active');
      el.presetWebSsh.classList.remove('active');
      el.inputHost.value = '193.168.175.227';
      el.inputPort.value = '22';
      el.inputUsername.value = 'agent';
      el.radioDirectMode.click();
    });

    el.presetWebSsh.addEventListener('click', () => {
      haptic();
      el.presetWebSsh.classList.add('active');
      el.presetDirectServer.classList.remove('active');
      el.inputHost.value = 'occurring-nearby-salvador-photography.trycloudflare.com';
      el.inputPort.value = '443';
      el.inputUsername.value = 'agent';
      el.radioWsMode.click();
      el.inputWsUrl.value = 'wss://occurring-nearby-salvador-photography.trycloudflare.com/ws/ssh';
    });

    // Submit Connect
    el.btnSubmitConnect.addEventListener('click', () => {
      haptic();
      const isKey = el.tabAuthKey.classList.contains('active');
      const isWs = el.radioWsMode.classList.contains('active');

      const profile = {
        name: `${el.inputUsername.value.trim()}@${el.inputHost.value.trim()}`,
        host: el.inputHost.value.trim(),
        port: parseInt(el.inputPort.value, 10) || 22,
        user: el.inputUsername.value.trim(),
        authType: isKey ? 'key' : 'password',
        secret: isKey ? el.inputPrivateKey.value : el.inputPassword.value,
        passphrase: el.inputKeyPassphrase.value,
        protocol: isWs ? 'websocket' : 'direct'
      };

      connectToServer(profile);
    });

    // Virtual Accessory Keys
    el.accessoryBar.querySelectorAll('.key-btn[data-key]').forEach(btn => {
      btn.addEventListener('click', (e) => {
        haptic(15);
        const key = btn.dataset.key;
        switch (key) {
          case 'ESC':
            sendToSsh('\x1b');
            break;
          case 'TAB':
            sendToSsh('\t');
            break;
          case 'CTRL':
            state.ctrlActive = !state.ctrlActive;
            btn.classList.toggle('active', state.ctrlActive);
            break;
          case 'ALT':
            state.altActive = !state.altActive;
            btn.classList.toggle('active', state.altActive);
            break;
          case 'UP':
            sendToSsh('\x1b[A');
            break;
          case 'DOWN':
            sendToSsh('\x1b[B');
            break;
          case 'RIGHT':
            sendToSsh('\x1b[C');
            break;
          case 'LEFT':
            sendToSsh('\x1b[D');
            break;
          default:
            sendToSsh(key);
            break;
        }
      });
    });

    el.keyClear.addEventListener('click', () => {
      haptic();
      term.clear();
    });

    el.keyPaste.addEventListener('click', async () => {
      haptic();
      let text = '';
      if (window.AndroidSSH) {
        text = window.AndroidSSH.getClipboardText();
      } else if (navigator.clipboard && navigator.clipboard.readText) {
        try {
          text = await navigator.clipboard.readText();
        } catch (ignored) {}
      }
      if (text) {
        sendToSsh(text);
      }
    });

    // Settings actions
    el.btnFontDec.addEventListener('click', () => {
      if (state.fontSize > 10) {
        state.fontSize--;
        el.fontSizeVal.textContent = state.fontSize + 'px';
        term.options.fontSize = state.fontSize;
        fitTerminal();
      }
    });

    el.btnFontInc.addEventListener('click', () => {
      if (state.fontSize < 24) {
        state.fontSize++;
        el.fontSizeVal.textContent = state.fontSize + 'px';
        term.options.fontSize = state.fontSize;
        fitTerminal();
      }
    });

    el.selectTheme.addEventListener('change', () => {
      state.theme = el.selectTheme.value;
      if (THEMES[state.theme]) {
        term.options.theme = THEMES[state.theme];
      }
    });

    el.selectCursor.addEventListener('change', () => {
      state.cursorStyle = el.selectCursor.value;
      term.options.cursorStyle = state.cursorStyle;
    });

    el.chkCursorBlink.addEventListener('change', () => {
      state.cursorBlink = el.chkCursorBlink.checked;
      term.options.cursorBlink = state.cursorBlink;
    });

    el.chkWakeLock.addEventListener('change', () => {
      state.wakeLock = el.chkWakeLock.checked;
      if (window.AndroidSSH) {
        window.AndroidSSH.setKeepScreenOn(state.wakeLock && state.connected);
      }
    });

    el.chkHaptics.addEventListener('change', () => {
      state.haptics = el.chkHaptics.checked;
    });

    el.btnClearScreen.addEventListener('click', () => {
      haptic();
      term.clear();
      closeSettings();
    });
  }

  // Init
  document.addEventListener('DOMContentLoaded', () => {
    initTerminal();
    setupEvents();
    loadProfiles();
  });

})();
