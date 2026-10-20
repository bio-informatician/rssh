<div align="center">

# 🐎⚡ Rakhssh (`rssh`)

**Ride through firewalls and NATs at lightning speed.**  
*Zero-config, 100% rootless, peer-to-peer SSH & terminal sharing for Linux.*

[![License: AGPL v3](https://img.shields.io/badge/License-AGPLv3-blue.svg?style=flat-square)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Linux%20(amd64%20%7C%20arm64)-lightgrey?style=flat-square)]()

</div>

---

## 🚀 Quick Install (No Root Required)

Install Rakhssh directly into `~/.local/bin` without root privileges:

```bash
curl -fsSL https://raw.githubusercontent.com/shrm/rssh/client-linux/install.sh | bash
```

To install system-wide (requires `sudo`):
```bash
curl -fsSL https://raw.githubusercontent.com/shrm/rssh/client-linux/install.sh | sudo bash -s -- --system
```

---

## 📖 Usage Guide

### 1. Host Mode (Share Your Machine)
Run without `sudo` on any machine behind a firewall, NAT, or CGNAT:

```bash
rssh host
```
Output:
```text
🐎⚡ Rakhssh is ready!
   ├── Machine ID : 482-910-334
   ├── Secret PIN : 8492
   └── Stealth    : Active (WSS/443 + P2P Standby)

Waiting for rider...
```

### 2. Connect Mode (Access Remote Machine)
From anywhere in the world, dial the 9-digit ID:

```bash
rssh 482-910-334
# Enter PIN when prompted
```

### 3. Unattended Access (Daemon Mode)
Run in the background with a persistent password:

```bash
rssh daemon --password "YourStrongPasswordHere"
```

To run as a systemd user service:
```bash
mkdir -p ~/.config/systemd/user
cp systemd/rssh-daemon.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now rssh-daemon.service
```

### 4. Port Forwarding
Tunnel remote services to your local machine:
```bash
# Forward remote port 8080 to local port 3000
rssh forward 482-910-334 -L 3000:localhost:8080

# Dynamic SOCKS5 proxy on local port 1080
rssh forward 482-910-334 -D 1080
```

### 5. File Transfer (SFTP)
```bash
rssh sftp 482-910-334
```

### 6. Native OpenSSH & VS Code Remote Integration
Add to `~/.ssh/config`:
```ssh-config
Host work-pc
    ProxyCommand rssh proxy 482-910-334
```
Now connect seamlessly via native tools:
```bash
ssh work-pc
rsync -avz ./src/ work-pc:~/src/
```
In **VS Code**, install the *Remote - SSH* extension and select `Connect to Host... -> work-pc`.

---

## 🔒 Security Architecture

1. **Zero-Knowledge PAKE (SPAKE2):** Key exchange is performed over NIST P-256 curve with HMAC-SHA256 mutual key confirmation. The relay server never sees your encryption keys or plain text.
2. **End-to-End Encryption:** All session payloads (terminal, SSH, SFTP, forwarded ports) are encrypted using ChaCha20-Poly1305.
3. **100% Rootless:** Rakhssh operates entirely in user-space without TUN/TAP virtual network devices or administrative privileges.
4. **Audit Logging & Access Control:** Unattended sessions are logged locally to `~/.rssh/audit.json`. Built-in client blocklist (`rssh block <client-id>`).

---

## 🛠️ Building From Source

```bash
make test
make build
make cross-compile-linux
```
The compiled binaries will be in `bin/` and `bin/dist/`.
