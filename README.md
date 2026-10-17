<div align="center">

# 🐎⚡ Rakhssh (`rssh`)

**Ride through firewalls and NATs at lightning speed.**  
*Zero-config, rootless, peer-to-peer SSH & terminal sharing with an AnyDesk-like (`ID + PIN`) experience.*

[![Go Report Card](https://img.shields.io/badge/go%20report-A+-brightgreen.svg?style=flat-square)](https://goreportcard.com/)
[![License: AGPL v3](https://img.shields.io/badge/License-AGPLv3-blue.svg?style=flat-square)](https://www.gnu.org/licenses/agpl-3.0)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg?style=flat-square)](http://makeapullrequest.com)
[![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20Windows-lightgrey?style=flat-square)]()

</div>

---

## 📖 The Story Behind the Name
In Persian mythology (*Shahnameh*), **Rakhsh** (رخش — meaning *"lightning"* or *"luminous"*) is the legendary, ultra-fast stallion of the hero Rostam. Rakhsh was famous for his unmatched speed, intelligence, and ability to carry his rider safely through impossible terrains and ambushes. 

**Rakhssh** (`Rakhsh` + `SSH`) brings that same spirit to your terminal: galloping past strict corporate firewalls, Deep Packet Inspection (DPI), and CGNATs with zero network configuration.

---

## 🎯 The Problem & Our Solution

Connecting to a remote machine behind a strict firewall or without a Public IP usually forces you into one of two extremes:
1. **Heavy Infrastructure VPNs (Tailscale, ZeroTier):** Require `root/admin` privileges, virtual network interfaces (`TUN/TAP`), user accounts, and can be easily flagged or blocked by strict corporate environments.
2. **Ephemeral Web/Terminal Relays (tmate, sshx):** Only share a terminal screen. You lose the rich OpenSSH ecosystem (no `SFTP`, `SCP`, `rsync`, port forwarding, or **VS Code Remote-SSH**), and all traffic is routed through third-party relays with high latency.

**Rakhssh bridges the gap:** It is a single, rootless binary that gives you a 9-digit **ID** and a **PIN** (just like AnyDesk or `croc`). It disguises initial signaling as normal HTTPS traffic, establishes a **Zero-Knowledge (PAKE)** encrypted tunnel, upgrades to a direct **User-Space P2P (WebRTC/QUIC)** connection whenever possible, and supports the **entire OpenSSH ecosystem**.

---

## ⚔️ Feature Comparison

| Feature | **Rakhssh (`rssh`)** | Tailscale / ZeroTier | tmate / sshx | croc |
| :--- | :---: | :---: | :---: | :---: |
| **No Root / Admin Required** | ✅ Yes (100% User-space) | ❌ No (Needs TUN/TAP) | ✅ Yes | ✅ Yes |
| **No Account / Signup Needed** | ✅ Yes (`ID + PIN`) | ❌ No (Requires SSO) | ✅ Yes | ✅ Yes |
| **Direct P2P Connection** | ✅ Yes (QUIC / WebRTC) | ✅ Yes (WireGuard) | ❌ No (Relay only) | ❌ No (Relay/LAN) |
| **DPI & Firewall Stealth** | ✅ Yes (WSS / CDN over 443) | ⚠️ Partial (DERP) | ✅ Yes | ❌ No |
| **Zero-Knowledge Encryption** | ✅ Yes (PAKE / SPAKE2) | ✅ Yes | ⚠️ Trust Relay | ✅ Yes (PAKE) |
| **Full SSH Ecosystem (SFTP, VS Code)**| ✅ Yes (`ProxyCommand`) | ✅ Yes | ❌ Terminal Only | ❌ File Transfer Only |
| **Built-in Session Persistence** | ✅ Yes (Mosh-like) | ❌ Needs `tmux` | ✅ Yes | N/A |

---

## 🚀 Quick Experience (CLI UX)

Rakhssh uses the short, snappy command `rssh` so you can type it in milliseconds.

### 1. On the Remote Machine (Behind NAT / No Public IP)
Run Rakhssh without `sudo`. It instantly generates a 9-digit machine ID and a one-time PIN:

```bash
$ rssh host

🐎⚡ Rakhssh is ready!
   ├── Machine ID : 482-910-334
   ├── Secret PIN : 8492
   └── Stealth    : Active (WSS/443 + P2P Standby)

Waiting for rider...
```

Or run it in the background for **Unattended Access** with a permanent password:
```bash
$ rssh daemon --password "MySuperSecretPassword"
```

### 2. On Your Local Machine (Anywhere in the World)
Simply dial the 9-digit ID and enter the PIN:

```bash
$ rssh 482-910-334
? Enter PIN/Password: ****
✔ PAKE Handshake verified (Zero-Knowledge E2EE)
✔ Upgraded to Direct P2P (QUIC | Latency: 21ms)

user@remote-machine:~$ _
```

### 3. Advanced OpenSSH Ecosystem Usage

* **Port Forwarding (Local & Remote):**
  ```bash
  # Expose remote port 8080 on your local port 3000
  $ rssh forward 482-910-334 -L 3000:localhost:8080
  ```
* **File Transfer (SFTP / Mount):**
  ```bash
  $ rssh sftp 482-910-334
  ```
* **Native OpenSSH & VS Code Remote-SSH Integration:**
  Add this single block to your `~/.ssh/config` and use `ssh`, `scp`, `rsync`, or **VS Code** natively!
  ```ssh-config
  Host work-pc
      ProxyCommand rssh proxy 482-910-334
  ```

---

## 🏗️ System Architecture & Connection Lifecycle

Rakhssh consists of a unified client/host binary (`rssh`) and a lightweight, self-hostable signaling/relay server (`rssh-server`).

```text
[Client Machine]                                  [Signaling / Relay Server]                                  [Host Machine (Behind NAT)]
       |                                                      |                                                             |
       |                                                      |<--- 1. Registers ID (482-910-334) via WSS (Port 443) -------|
       |                                                      |                                                             |
       |--- 2. Dials ID (482-910-334) ----------------------->|                                                             |
       |                                                      |--- 3. Wakes Host & Bridges Signaling ---------------------->|
       |                                                      |                                                             |
       |<==================== 4. PAKE Handshake (SPAKE2) via Server (Zero-Knowledge Key Exchange) =========================>|
       |                                                      |                                                             |
       |<==================== 5. Attempt Direct P2P (UDP Hole Punching via WebRTC / QUIC) =================================>|
       |                                                      |                                                             |
       |--- (If Symmetric NAT / UDP Blocked) ---------------->|--- 5b. Seamless Fallback to Stealth WSS/CDN Relay --------->|
       |                                                      |                                                             |
       |<==================== 6. Multiplexed Stream (yamux) carrying PTY, SFTP, & Port Forwards ===========================>|
```

### Key Technical Pillars:
1. **Zero-Knowledge PAKE (`SPAKE2`):** Neither the signaling server nor any network middlebox can ever see your PIN or decrypt your session. Both peers derive a shared symmetric key using Password-Authenticated Key Exchange.
2. **User-Space NAT Traversal:** Uses STUN/ICE (`pion/webrtc` or `quic-go`) to punch holes through firewalls directly from user-space—no kernel drivers or `root` needed.
3. **DPI Stealth & CDN Fronting:** When UDP is completely blocked by an enterprise firewall, Rakhssh falls back to WebSockets over TLS (`WSS` on port `443`), capable of routing through Cloudflare CDN so deep packet inspectors only see standard web traffic.
4. **Session Persistence:** The host daemon maintains an internal PTY ring-buffer. If you close your laptop or switch from Wi-Fi to mobile hotspot, your terminal session and running processes stay alive and resume instantaneously.

---

## 🛠️ Tech Stack (Golang)

Rakhssh is built in **Go** for zero-dependency cross-compilation, tiny binary footprint, and battle-tested networking libraries:

* **Embedded SSH Server & Protocol:** `golang.org/x/crypto/ssh` & `github.com/gliderlabs/ssh`
* **Pseudo-Terminal (PTY) Management:** `github.com/creack/pty` (Unix) & ConPTY (Windows)
* **Zero-Knowledge PAKE Cryptography:** `github.com/schollz/pake/v3`
* **User-Space P2P & NAT Traversal:** `github.com/pion/webrtc/v4` (Data Channels) / `github.com/quic-go/quic-go`
* **Stream Multiplexing:** `github.com/hashicorp/yamux`
* **Stealth WebSocket Transport:** `nhooyr.io/websocket`
* **CLI Interface:** `github.com/spf13/cobra`

---

## 🗺️ Development Roadmap

### Phase 1: MVP — Stealth Relay & PAKE Terminal
- [ ] Build lightweight `rssh-server` for WebSocket signaling and fallback relay.
- [ ] Implement 9-digit ID generation and registration for `rssh host`.
- [ ] Integrate `SPAKE2` (PAKE) handshake + ChaCha20-Poly1305 stream encryption between Host and Client.
- [ ] Spawn cross-platform PTY on Host and pipe encrypted `stdin`/`stdout` + terminal window resize (`SIGWINCH`) events.

### Phase 2: Multiplexing & Full OpenSSH Ecosystem
- [ ] Layer `yamux` stream multiplexer over the encrypted connection.
- [ ] Embed user-space SSH server (`gliderlabs/ssh`) inside the host process over `yamux`.
- [ ] Implement `rssh proxy <ID>` to support standard OpenSSH `ProxyCommand` (unlocking `scp`, `sftp`, `rsync`, and VS Code Remote-SSH).
- [ ] Add built-in TCP port forwarding (`-L`, `-R`, and `-D` SOCKS5 proxy).

### Phase 3: Lightning P2P (NAT Traversal)
- [ ] Integrate STUN/ICE candidate gathering via `pion/webrtc` Data Channels.
- [ ] Implement "Fast-Start, Smart-Upgrade": connect immediately via WebSocket Relay (<500ms) while negotiating direct UDP Hole Punching in the background, then seamlessly hot-swap the underlying transport to P2P.

### Phase 4: Session Persistence & Unattended Access
- [ ] Implement detached PTY state buffer on the host (surviving network drops and IP roaming without needing `tmux`).
- [ ] Build `rssh daemon` mode with user-level service installers (`systemd --user`, macOS `launchd`, Windows Task Scheduler).
- [ ] Add optional Self-Hosted Relay deployment scripts (Docker / One-click Cloudflare Tunnel setup).

---

## 🤝 Contributing
Contributions, issues, and feature requests are welcome! Feel free to check the [issues page](#) if you want to help build the fastest stealth SSH tool in the open-source community.

## ⚖️ Legal, Abuse Policy & Disclaimer
- **As-Is Disclaimer:** Rakhssh is provided on an "as is" and "as available" basis without warranties of any kind. Use at your own risk.
- **Acceptable Use & Anti-Intrusion:** Rakhssh is strictly engineered for authorized systems administration and development. Using Rakhssh to bypass enterprise firewalls without administrative consent, conduct electronic intrusion, or exfiltrate data is strictly prohibited and illegal under domestic and international cybersecurity laws.
- **Responsible Disclosure:** If you discover a vulnerability, please report it via private security advisory.

## 📄 License
Distributed under the **GNU Affero General Public License v3.0 (AGPL-3.0)** with dual-licensing available for commercial managed relay providers. See [LICENSE](file:///home/shrm/project/rssh/LICENSE) for more information.
