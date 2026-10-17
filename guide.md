# Rakhssh (`rssh`) Architecture & Module Guide

Rakhssh (`rssh`) is a zero-configuration, rootless, peer-to-peer SSH and pseudo-terminal ecosystem tool designed to operate behind strict enterprise NATs, CGNATs, and DPI firewalls. It provides an AnyDesk-style user experience (`9-digit ID + PIN`) for the command line with end-to-end zero-knowledge encryption.

---

## 1. System Architecture

```text
+------------------+             +--------------------------+             +------------------+
|   Client (CLI)   |             |  Signaling/Relay Server  |             |   Host Daemon    |
|   `rssh <ID>`    |             |      `rssh-server`       |             |   `rssh host`    |
+--------+---------+             +------------+-------------+             +--------+---------+
         |                                    |                                    |
         |                                    |<--- 1. Register ID (WSS/443) ------|
         |                                    |                                    |
         |--- 2. Connect Target (WSS/443) --->|                                    |
         |                                    |--- 3. Incoming Session Notify ---->|
         |                                    |                                    |
         |<======= 4. Zero-Knowledge PAKE (SPAKE2) Handshake (Zero Server Knowledge) ======>|
         |                                    |                                    |
         |<======= 5. Attempt Direct P2P (UDP Hole Punching via WebRTC DataChannel) =======>|
         |                                    |                                    |
         |--- 5b. Fallback: Seamless WSS Relay (if UDP blocked by enterprise firewall) --->|
         |                                    |                                    |
         |<======= 6. ChaCha20-Poly1305 AEAD Symmetric Framing + yamux Multiplexing ======>|
         |                                                                                 |
         +--> Channel 0: PTY Shell Session (with Persistent Scrollback Buffer) <-----------+
         +--> Channel 1: Embedded OpenSSH Server (SFTP / SCP / VS Code Remote-SSH) <-------+
         +--> Channel 2: Port Forwarding (-L / -R) & Dynamic SOCKS5 Proxy (-D) <-----------+
```

---

## 2. Directory & Module Guide

```
rssh/
├── bin/                       # Compiled binaries (rssh, rssh-server)
├── cmd/
│   ├── rssh/                  # Unified client & host CLI entrypoint
│   └── rssh-server/           # Standalone signaling & relay server
├── pkg/
│   ├── crypto/                # Zero-Knowledge PAKE & AEAD frame encryption
│   ├── daemon/                # Unattended host daemon & systemd user service
│   ├── id/                    # 9-digit machine identifier & PIN generation
│   ├── p2p/                   # WebRTC DataChannel P2P & NAT traversal
│   ├── pty/                   # Pseudo-terminal management & session persistence
│   ├── signaling/             # WebSocket protocol, client, server & relay
│   ├── sshserver/             # Embedded OpenSSH server & SFTP subsystem
│   ├── transport/             # Transport orchestrator & yamux multiplexing
│   └── tunnel/                # Local/Remote port forwarding & SOCKS5 proxy
├── test/
│   └── e2e_test.go            # End-to-end integration test suite
├── guide.md                   # This documentation
└── README.md                  # Project overview & feature matrix
```

### Module Breakdown

#### `pkg/id`
- **Purpose**: Generates, validates, and standardizes 9-digit identifiers (`XXX-XXX-XXX`) and temporary PIN codes.
- **Key Functions**:
  - `GenerateRandomID()`: Generates a cryptographically random 9-digit ID.
  - `GeneratePersistentID()`: Computes a deterministic 9-digit ID based on hardware attributes (`/etc/machine-id`, hostname, MAC address).
  - `GeneratePIN(digits int)`: Generates secure numeric PINs (default 4–6 digits).
  - `NormalizeID(input string)`: Cleans and formats raw user input into `XXX-XXX-XXX`.
- **Test File**: `pkg/id/id_test.go` (Format validation, random & persistent ID tests, PIN length tests).

#### `pkg/crypto`
- **Purpose**: Zero-Knowledge end-to-end encryption.
- **Key Features**:
  - **PAKE (SPAKE2)**: Based on `siec` elliptic curve (`github.com/schollz/pake/v3`). Both peers independently compute a shared secret authenticated by the PIN. The signaling server never receives or decrypts this key.
  - **HKDF Key Derivation**: Derives separate directional keys:
    - `HostToClientKey`: 32-byte key for Host -> Client traffic.
    - `ClientToHostKey`: 32-byte key for Client -> Host traffic.
    - `VerificationKey`: 32-byte key for mutual HMAC authentication.
  - **ChaCha20-Poly1305 AEAD Streaming**: `SecureConn` wraps any `net.Conn` into authenticated, encrypted frames with independent 64-bit sequence counters to prevent replay attacks and detect tampering.
- **Test File**: `pkg/crypto/crypto_test.go` (PAKE handshake success, wrong PIN failure, duplex `SecureConn` framing).

#### `pkg/signaling`
- **Purpose**: Coordinates WebSocket-based rendezvous and provides fallback data relaying.
- **Components**:
  - `protocol.go`: Defines JSON signaling messages (`register`, `connect`, `pake`, `signal`, `relay`, `close`).
  - `server.go`: Thread-safe registry mapping 9-digit host IDs to active connections and routing session pairs. Serves a benign HTTP page on non-upgrade GET requests for DPI disguise.
  - `client.go`: Dial helper with ping/pong keepalives.
  - `RelayConn`: An adapter implementing `net.Conn` over WebSocket relay frames, providing zero-config fallback when UDP is blocked.
- **Test File**: `pkg/signaling/signaling_test.go` (Registration, target connection, relay data roundtrip, offline host handling).

#### `pkg/p2p`
- **Purpose**: Direct user-space NAT traversal using WebRTC Data Channels (`github.com/pion/webrtc/v4`).
- **Components**:
  - `peer.go`: Manages `PeerConnection` state, generates SDP offers/answers, and gathers STUN candidates (`stun.l.google.com:19302`, `stun.cloudflare.com:3478`).
  - `conn.go`: `DataChannelConn` wraps WebRTC binary data channels into a standard `net.Conn`.
- **Test File**: `pkg/p2p/p2p_test.go` (In-memory WebRTC DataChannel connection and bidirectional throughput test).

#### `pkg/transport`
- **Purpose**: Unifies transport selection ("Fast-Start, Smart-Upgrade") and layers stream multiplexing.
- **Components**:
  - `session.go`: Manages `yamux.Session` on top of `SecureConn`. Provides `OpenStream()` and `AcceptStream()`.
  - `orchestrator.go`: Concurrently starts fallback relay and initiates P2P ICE discovery. Wraps the established connection with ChaCha20-Poly1305 encryption.
- **Test File**: `pkg/transport/transport_test.go` (Encrypted yamux stream exchange, full signaling + PAKE orchestration test).

#### `pkg/pty`
- **Purpose**: Pseudo-terminal management and session persistence.
- **Components**:
  - `session.go`: Spawns `$SHELL` inside a virtual terminal (`github.com/creack/pty`). Handles terminal resize events. Keeps shell process running detached if network drops.
  - `ringbuffer.go`: Circular memory buffer retaining recent terminal scrollback. Replays history when client re-attaches.
- **Test File**: `pkg/pty/pty_test.go` (Ring buffer wrap-around, PTY shell execution and resize).

#### `pkg/sshserver`
- **Purpose**: Embedded user-space OpenSSH-compatible server (`github.com/gliderlabs/ssh`).
- **Features**:
  - Generates ephemeral in-memory Ed25519 host keys without root permissions.
  - Interactive shell sessions with PTY allocation.
  - Command execution (`exec`), enabling `scp`, `rsync`, and non-interactive automation.
  - Embedded SFTP subsystem (`github.com/pkg/sftp`).
  - Direct TCP/IP port forwarding.
  - `VirtualListener`: Accepts logical streams routed directly from `yamux`.
- **Test File**: `pkg/sshserver/server_test.go` (Embedded SSH server exec command test, SFTP file creation and readback).

#### `pkg/tunnel`
- **Purpose**: TCP port forwarding and dynamic SOCKS5 proxy.
- **Components**:
  - Local port forwarding (`-L [bind:]port:host:port`).
  - SOCKS5 dynamic proxy (`-D port`): RFC 1928 proxy server routing client connections through the remote host.
- **Test File**: `pkg/tunnel/tunnel_test.go` (Forward spec parser, local port forwarding test, SOCKS5 CONNECT handshake and echo test).

#### `pkg/daemon`
- **Purpose**: Unattended background access without root.
- **Components**:
  - Configuration manager storing machine ID and persistent password in `~/.config/rssh/config.json`.
  - Rootless systemd service generator (`~/.config/systemd/user/rssh.service`).
- **Test File**: `pkg/daemon/daemon_test.go` (Config roundtrip, systemd service generation and installation).

#### `cmd/rssh`
- **Purpose**: Unified CLI command offering `host`, `connect`, `proxy`, `forward`, and `daemon`.

#### `cmd/rssh-server`
- **Purpose**: Lightweight signaling and fallback relay server with optional TLS support.

---

## 3. Building the Binaries

From the `rssh` project directory:

```bash
# Set path to Go (if using internal toolchain)
export PATH="$PWD/.go/bin:$PATH"

# Build both executables into bin/
go build -o bin/rssh ./cmd/rssh
go build -o bin/rssh-server ./cmd/rssh-server
```

---

## 4. Usage Guide

### 1. Start the Signaling & Relay Server
```bash
./bin/rssh-server --addr :8443
```
*Optional TLS flags for production HTTPS/WSS*:
```bash
./bin/rssh-server --addr :443 --cert /path/to/cert.pem --key /path/to/key.pem
```

### 2. On the Host (Behind NAT / Firewall)
Run a temporary session with a randomly generated 9-digit ID and 4-digit PIN:
```bash
./bin/rssh host --server ws://localhost:8443
```
Output:
```
🐎⚡ Rakhssh is ready!
   ├── Machine ID : 482-910-334
   ├── Secret PIN : 8492
   └── Stealth    : Active (WSS/443 + P2P Standby)

Waiting for rider...
```

Or run as an unattended background service with a persistent password:
```bash
./bin/rssh daemon --password "MySecretPass" --server ws://localhost:8443
```

To install as an auto-starting user service on Linux (no root required):
```bash
./bin/rssh daemon --install-systemd
systemctl --user daemon-reload
systemctl --user enable --now rssh
```

### 3. On the Client (Connect to Remote Terminal)
Connect using the 9-digit ID:
```bash
./bin/rssh connect 482-910-334 --server ws://localhost:8443
# Or shorthand:
./bin/rssh 482-910-334 --server ws://localhost:8443
```

### 4. OpenSSH, SCP, SFTP & VS Code Remote-SSH Integration
Rakhssh acts as an OpenSSH `ProxyCommand` bridge via `rssh proxy <ID>`.

Add this to `~/.ssh/config`:
```ssh-config
Host rakhsh-box
    ProxyCommand /path/to/bin/rssh proxy 482-910-334 --server ws://localhost:8443 --pin 8492
```

Now you can natively run:
- Standard SSH: `ssh rakhsh-box`
- File copy: `scp file.txt rakhsh-box:~/`
- Directory sync: `rsync -avz ./dist rakhsh-box:~/dist`
- SFTP: `sftp rakhsh-box`
- **VS Code Remote-SSH**: Select `Connect to Host...` -> `rakhsh-box`!

### 5. Port Forwarding & Dynamic SOCKS5 Proxy
```bash
# Forward remote port 8080 to local port 3000
./bin/rssh forward 482-910-334 -L 3000:localhost:8080 --pin 8492

# Open dynamic SOCKS5 proxy on local port 1080
./bin/rssh forward 482-910-334 -D 1080 --pin 8492
```

---

## 5. Running the Automated Test Suites

All tests run completely offline or via local loopback without requiring root or external infrastructure:

```bash
export PATH="$PWD/.go/bin:$PATH"

# Run all unit tests across all packages
go test -v -count=1 ./pkg/...

# Run end-to-end integration test
go test -v -count=1 ./test/...

# Run all tests in the entire project
go test -v -count=1 ./...
```

---

## 6. Server-Enforced Control, Timeouts & Concurrency

### 1. Persistent Control Channel & Heartbeats
Both Host and Client maintain an active WebSocket signaling connection with `rssh-server` even while P2P data channels are flowing.
- **Heartbeat**: 30-second ping/pong frames prevent NAT bindings from dropping.
- **Remote Termination**: If the server revokes a session (due to idle timeout, duration limit, or admin action), it sends a JSON `{"type": "terminate", "session_id": "...", "error": "..."}` message. Both peers immediately abort their local sockets and PTY processes.

### 2. Session Timeouts
- **Idle Timeout**: Set via `--idle-timeout` on `rssh-server` (default `30m`). If no frames/signals are passed within this duration, the session is terminated.
- **Max Duration Limit**: Set via `--max-duration` on `rssh-server` (default `2h`). Hard ceiling terminating connections regardless of active traffic.

### 3. Single-Session Lock (Preventing Dual Connections)
A Host ID can only be bound to **one active session** at a time:
- When a client connects, the server marks the Host ID as `BUSY`.
- Any subsequent client attempting to dial the same Host ID while busy is immediately rejected with:
  `{"type": "error", "error": "host is busy with another active session"}`.
- The lock is atomically released as soon as the session closes or terminates.

---

## 7. EU & US Regulatory Compliance, Privacy & Abuse Prevention

### 1. European Union (GDPR / Privacy by Design)
- **Zero-Knowledge Processing**: The signaling relay server (`rssh-server`) processes metadata solely to broker initial handshakes. Decrypted terminal streams, keystrokes, and file payloads never touch the server.
- **Transient Routing**: IP addresses and session state reside purely in volatile memory and are cleaned upon session termination.
- **Local User Audit Trail**: Successful connections, rejected connection attempts, and disconnections are appended to `~/.config/rssh/audit.log` on the Host machine for full user visibility.

### 2. United States (EAR Export Controls & DMCA Safe Harbor)
- **Export Control (EAR)**: Utilizes standard open-source cryptographic primitives (`Ed25519`, `SPAKE2`, `ChaCha20-Poly1305`) adhering to 15 CFR § 742.15(b) mass-market compliance.
- **Abuse Prevention & Client Blocking**:
  Host operators can permanently ban unauthorized client IDs from connecting:
  ```bash
  # Ban an unauthorized client ID
  rssh block 123-456-789

  # View all blocked client IDs
  rssh blocked

  # Remove a client from the ban list
  rssh unblock 123-456-789
  ```
- **Legal Notice**: See [LICENSE](file:///home/shrm/project/rssh/LICENSE) for explicit acceptable use disclaimers prohibiting unauthorized network intrusion.


