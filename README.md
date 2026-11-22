# Rakhssh SSH CLI Client (`ssh-cli-client`)

Fast, interactive command-line terminal SSH client for Rakhssh.
Supports direct OpenSSH PTY connection, saved profiles, latency tests, and WebSocket proxy tunneling.

## Usage
- Connect to host: `./rssh_cli.py connect <host> [port] [user]`
- Profile management: `./rssh_cli.py profile save <name> <host> <port> <user>`
- WebSocket proxy mode: `./rssh_cli.py ws-proxy <ws_url>`
