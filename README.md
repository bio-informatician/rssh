# Rakhssh Multi-Branch Integrity & Test Suite (`test` branch)

This branch contains the multi-branch automated testing, security auditing, and executability verification harness for the `bio-informatician/rssh` repository.

## 🎯 Purpose
The Rakhsh ecosystem is organized into dedicated branches within this repository:
- `main`: Core reverse SSH daemon & shared configs
- `client-linux`: Linux reverse SSH client (Go)
- `server-linux`: Linux reverse SSH server (Go, Caddy, Nginx, Docker)
- `chat`: Rakhsh Chat E2EE messaging platform & Android client
- `ssh-android-client`: Rakhsh Android SSH terminal client (`org.rssh.terminal`)
- `ssh-cli-client`: Interactive CLI SSH client (`rssh_cli.py`)
- `ssh-web-client`: Web SSH terminal & WebSocket server (`server.py`, port 8766)

The test suite in this branch audits, tests, and verifies the health of **all branches** without altering their code or disrupting production services.

---

## 🧪 Verification Modules

### 1. `scripts/check_functionality.py`
Extracts each branch via isolated `git archive` streams and validates:
- Python AST structure and imports
- Node.js JavaScript syntax verification (`node -c`)
- Web UI layouts and HTML elements
- Go module contracts (`go.mod`)
- Reverse proxy configs (Caddy / Nginx)
- Service unit definitions and installers

### 2. `scripts/check_security.py`
Audits each branch for security posture:
- Secret & token scanning (zero credentials / private keys checked into Git)
- Python AST security checking (flags unsafe `eval()`, `exec()`, or unvalidated `shell=True`)
- File permissions hygiene (ensures no world-writable permissions)
- Transport layer security (TLS/WSS validation)
- PIN brute-force lockout and rate-limiting enforcement

### 3. `scripts/check_executability.py`
Validates end-to-end execution readiness:
- Python bytecode compilation (`python3 -m py_compile`)
- Bash syntax validation (`bash -n`)
- Script file executable permissions (`+x`)
- CLI command executions (e.g. `rssh_cli.py --help`)

---

## 🚀 Running the Tests

### Run All Tests Across All Branches:
```bash
./test_all.sh
# Or directly:
python3 run_all_tests.py
```

### Run on a Specific Branch:
```bash
python3 run_all_tests.py chat
python3 run_all_tests.py ssh-cli-client
```

### Run an Individual Test Module:
```bash
python3 scripts/check_functionality.py
python3 scripts/check_security.py
python3 scripts/check_executability.py
```

### Run Unit Tests of the Test Suite:
```bash
python3 -m unittest tests/test_suite.py
```
