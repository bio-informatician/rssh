# Rakhssh Server (`rssh-server`) — Production Deployment Guide

Signaling and fallback relay server for the Rakhssh (`rssh`) remote access network.

---

## 1. Architecture Overview

`rssh-server` coordinates user-space P2P signaling and acts as an encrypted fallback relay when direct peer-to-peer connectivity is prevented by symmetric NATs or firewalls.

- **Port:** Defaults to `:8443` (HTTP/WebSocket) or direct TLS on `:443`.
- **Protocol:** Standard WebSocket (WSS) handling initial registration, session matchmaking, PAKE point exchange, and encrypted fallback relay frames.
- **Resource Limits:**
  - 64 KB maximum WebSocket message limit to prevent memory exhaustion.
  - 5,000 maximum concurrent active connections (configurable in source).
  - Rate-limited registration and connection endpoints keyed by parsed client IP.
  - Automatic idle timeout (30m default) and hard maximum session duration (2h default).

---

## 2. Deployment Options

### Option A: Systemd Service (Recommended for Bare-Metal / VPS)

1. **Build and install:**
   ```bash
   make build
   sudo make install-service
   ```

2. **Configure Nginx or Caddy reverse proxy for TLS termination (Port 443):**
   - **Nginx:** Use the provided [nginx/rssh-server.conf](nginx/rssh-server.conf).
   - **Caddy:** Use the provided [caddy/Caddyfile](caddy/Caddyfile).

3. **Verify service:**
   ```bash
   sudo systemctl status rssh-server
   sudo journalctl -u rssh-server -f
   ```

---

### Option B: Docker / Docker Compose

1. **Launch container:**
   ```bash
   docker compose up -d --build
   ```

2. **View logs:**
   ```bash
   docker compose logs -f
   ```

---

## 3. Configuration Flags

| Flag | Default | Description |
|------|---------|-------------|
| `--addr` | `:8443` | Listen address |
| `--cert` | `""` | Path to TLS certificate (if terminating TLS directly in Go) |
| `--key` | `""` | Path to TLS private key |
| `--idle-timeout` | `30m` | Disconnect sessions idle for longer than this duration |
| `--max-duration` | `2h` | Maximum absolute session duration before forced rotation |

---

## 4. Health & Monitoring

The server exposes HTTP `GET /` returning server status and active connection count:
```bash
curl -i http://localhost:8443/
```
Expected output:
```http
HTTP/1.1 200 OK
Content-Type: text/plain; charset=utf-8

🐎⚡ Rakhssh Signaling & Relay Server is online. Active connections: 0
```
