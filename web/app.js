(function() {
  'use strict';

  let term = null;
  let fitAddon = null;
  let ws = null;
  let ctrlActive = false;
  let altActive = false;

  const indicator = document.getElementById('sessionIndicator');
  const statusText = document.getElementById('sessionStatusText');
  const btnReconnect = document.getElementById('btnReconnect');
  const btnClear = document.getElementById('btnClearScreen');
  const keyCtrl = document.getElementById('keyCtrl');
  const keyAlt = document.getElementById('keyAlt');

  function init() {
    term = new Terminal({
      cursorBlink: true,
      cursorStyle: 'block',
      fontSize: 14,
      fontFamily: 'Menlo, Monaco, "Courier New", monospace',
      theme: {
        background: '#05080f',
        foreground: '#e6edf3',
        cursor: '#10b981',
        selectionBackground: '#10b98144'
      }
    });

    if (window.FitAddon && window.FitAddon.FitAddon) {
      fitAddon = new window.FitAddon.FitAddon();
      term.loadAddon(fitAddon);
    }

    term.open(document.getElementById('terminal'));
    setTimeout(fit, 100);
    window.addEventListener('resize', fit);

    term.onData(data => {
      handleInput(data);
    });

    connect();
  }

  function fit() {
    if (!fitAddon || !term) return;
    try {
      fitAddon.fit();
      if (ws && ws.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify({
          type: 'resize',
          cols: term.cols,
          rows: term.rows
        }));
      }
    } catch (e) {}
  }

  function handleInput(data) {
    if (ctrlActive) {
      ctrlActive = false;
      keyCtrl.classList.remove('active');
      if (data.length === 1) {
        const code = data.toUpperCase().charCodeAt(0);
        if (code >= 64 && code <= 95) {
          send(String.fromCharCode(code - 64));
          return;
        }
      }
    }

    if (altActive) {
      altActive = false;
      keyAlt.classList.remove('active');
      send('\x1b' + data);
      return;
    }

    send(data);
  }

  function send(data) {
    if (ws && ws.readyState === WebSocket.OPEN) {
      ws.send(data);
    }
  }

  function setStatus(status, text) {
    indicator.className = 'session-indicator ' + status;
    statusText.textContent = text;
  }

  function connect() {
    if (ws) {
      try { ws.close(); } catch (e) {}
    }

    setStatus('connecting', 'در حال اتصال به سرور...');
    term.writeln('\x1b[33m--> در حال اتصال به وب‌ترمینال سرور...\x1b[0m');

    const protocol = location.protocol === 'https:' ? 'wss:' : 'ws:';
    const wsUrl = `${protocol}//${location.host}/ws/ssh?mode=terminal`;

    try {
      ws = new WebSocket(wsUrl);
      ws.binaryType = 'arraybuffer';

      ws.onopen = () => {
        setStatus('connected', 'متصل به ترمینال شل');
        term.writeln('\x1b[1;32m--> اتصال ترمینال برقرار شد.\x1b[0m\r\n');
        fit();
      };

      ws.onmessage = (event) => {
        if (typeof event.data === 'string') {
          term.write(event.data);
        } else {
          term.write(new Uint8Array(event.data));
        }
      };

      ws.onerror = (err) => {
        setStatus('disconnected', 'خطا در ارتباط');
      };

      ws.onclose = () => {
        setStatus('disconnected', 'ارتباط قطع شد');
        term.writeln('\r\n\x1b[1;31m--> نشست ترمینال بسته شد.\x1b[0m');
      };
    } catch (e) {
      setStatus('disconnected', 'خطا در سوکت: ' + e.message);
    }
  }

  btnReconnect.addEventListener('click', () => {
    connect();
  });

  btnClear.addEventListener('click', () => {
    term.clear();
  });

  // Keys
  document.querySelectorAll('.key-btn[data-key]').forEach(btn => {
    btn.addEventListener('click', () => {
      const key = btn.dataset.key;
      switch (key) {
        case 'ESC': send('\x1b'); break;
        case 'TAB': send('\t'); break;
        case 'CTRL':
          ctrlActive = !ctrlActive;
          btn.classList.toggle('active', ctrlActive);
          break;
        case 'ALT':
          altActive = !altActive;
          btn.classList.toggle('active', altActive);
          break;
        case 'UP': send('\x1b[A'); break;
        case 'DOWN': send('\x1b[B'); break;
        case 'RIGHT': send('\x1b[C'); break;
        case 'LEFT': send('\x1b[D'); break;
        default: send(key); break;
      }
    });
  });

  document.addEventListener('DOMContentLoaded', init);
})();
