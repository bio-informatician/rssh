# 🛡️ Rakhssh Multi-Branch Integrity & Security Audit Report

- **Generated:** `2026-11-22T07:43:15.815803`
- **Repository:** `bio-informatician/rssh`
- **Result:** `100% HEALTHY`
- **Total Checks:** `79/79` passed

| Branch | Functionality | Security | Executability | Status |
|---|---|---|---|---|
| `main` | 4/4 | 3/3 | 3/3 | ✅ PASS |
| `client-linux` | 4/4 | 4/4 | 4/4 | ✅ PASS |
| `server-linux` | 3/3 | 4/4 | 3/3 | ✅ PASS |
| `chat` | 6/6 | 4/4 | 5/5 | ✅ PASS |
| `ssh-android-client` | 4/4 | 3/3 | 4/4 | ✅ PASS |
| `ssh-cli-client` | 2/2 | 4/4 | 4/4 | ✅ PASS |
| `ssh-web-client` | 3/3 | 4/4 | 4/4 | ✅ PASS |

## 🔍 Detailed Findings per Branch

### Branch `main`
- **Functionality:**
  - ✅ main/README.md presence: File present
  - ✅ main/LICENSE presence: File present
  - ✅ main/Makefile presence: File present
  - ✅ main/go.mod presence: File present
- **Security:**
  - ✅ Credentials & Secret Exposure Scan: Zero leaked keys or tokens found
  - ✅ Python AST Static Security Analysis: No dangerous eval, exec, or unvalidated shell=True in daemons
  - ✅ File Permissions Hygiene: No world-writable files in repository tree
- **Executability:**
  - ✅ Python Compilation: No python scripts in this branch
  - ✅ Shell Script Validation: No shell scripts in this branch
  - ✅ JavaScript Validation: No non-minified JavaScript files in this branch

### Branch `client-linux`
- **Functionality:**
  - ✅ client-linux go.mod: go.mod specifies Go module
  - ✅ client-linux install.sh bash syntax: Valid bash syntax
  - ✅ client-linux Makefile presence: Makefile exists
  - ✅ client-linux systemd presence: Systemd service files present
- **Security:**
  - ✅ Credentials & Secret Exposure Scan: Zero leaked keys or tokens found
  - ✅ Python AST Static Security Analysis: No dangerous eval, exec, or unvalidated shell=True in daemons
  - ✅ File Permissions Hygiene: No world-writable files in repository tree
  - ✅ PIN Enforcement & Lockout Protection: PIN security verification and lockout protection present in client code
- **Executability:**
  - ✅ Python Compilation: No python scripts in this branch
  - ✅ Shell Script Syntax (1/1 scripts): All shell scripts passed bash -n syntax validation
  - ✅ Shell Script Executability (1/1): Executable via bash interpreter (shebang verified on 1/1 scripts)
  - ✅ JavaScript Validation: No non-minified JavaScript files in this branch

### Branch `server-linux`
- **Functionality:**
  - ✅ server-linux go.mod presence: go.mod exists
  - ✅ server-linux Dockerfile structure: Dockerfile contains FROM directive
  - ✅ server-linux reverse proxy configs: Reverse proxy configurations present
- **Security:**
  - ✅ Credentials & Secret Exposure Scan: Zero leaked keys or tokens found
  - ✅ Python AST Static Security Analysis: No dangerous eval, exec, or unvalidated shell=True in daemons
  - ✅ File Permissions Hygiene: No world-writable files in repository tree
  - ✅ Container Hardening (Non-root USER): Dockerfile enforces non-root USER
- **Executability:**
  - ✅ Python Compilation: No python scripts in this branch
  - ✅ Shell Script Validation: No shell scripts in this branch
  - ✅ JavaScript Validation: No non-minified JavaScript files in this branch

### Branch `chat`
- **Functionality:**
  - ✅ chat/server.py AST Parse: Clean syntax and AST valid
  - ✅ chat/web/app.js Node syntax check: Valid JavaScript syntax
  - ✅ chat/web/index.html UI structure: Contains standard viewport and chat UI elements
  - ✅ chat/build_apk.py AST: Clean syntax
  - ✅ chat/generate_installer.py AST: Clean syntax
  - ✅ chat/send_dispatch.py AST: Clean syntax
- **Security:**
  - ✅ Credentials & Secret Exposure Scan: Zero leaked keys or tokens found
  - ✅ Python AST Static Security Analysis: No dangerous eval, exec, or unvalidated shell=True in daemons
  - ✅ File Permissions Hygiene: No world-writable files in repository tree
  - ✅ Secure TLS/WSS Transport Architecture: Enforces or dynamically resolves secure HTTPS/WSS protocols
- **Executability:**
  - ✅ Python Compilation (4/4 files): All python files bytecode-compiled cleanly
  - ✅ Shell Script Syntax (3/3 scripts): All shell scripts passed bash -n syntax validation
  - ✅ Shell Script Executability (3/3): All shell scripts have direct +x executable permissions
  - ✅ JavaScript Syntax (1/1 files): All JavaScript files verified with node -c
  - ✅ Build APK Tool Executability: Bytecode compile passed

### Branch `ssh-android-client`
- **Functionality:**
  - ✅ ssh-android-client/build_apk.py AST: Clean syntax
  - ✅ ssh-android-client/send_dispatch.py AST: Clean syntax
  - ✅ ssh-android-client/web/app.js syntax: Valid JS syntax
  - ✅ AndroidManifest XML Structure: Valid XML, package: org.rssh.terminal
- **Security:**
  - ✅ Credentials & Secret Exposure Scan: Zero leaked keys or tokens found
  - ✅ Python AST Static Security Analysis: No dangerous eval, exec, or unvalidated shell=True in daemons
  - ✅ File Permissions Hygiene: No world-writable files in repository tree
- **Executability:**
  - ✅ Python Compilation (2/2 files): All python files bytecode-compiled cleanly
  - ✅ Shell Script Validation: No shell scripts in this branch
  - ✅ JavaScript Syntax (3/3 files): All JavaScript files verified with node -c
  - ✅ Build APK Tool Executability: Bytecode compile passed

### Branch `ssh-cli-client`
- **Functionality:**
  - ✅ ssh-cli-client AST Parse: Clean syntax and AST valid
  - ✅ ssh-cli-client --help execution: Executed cleanly with expected banner and options
- **Security:**
  - ✅ Credentials & Secret Exposure Scan: Zero leaked keys or tokens found
  - ✅ Python AST Static Security Analysis: No dangerous eval, exec, or unvalidated shell=True in daemons
  - ✅ File Permissions Hygiene: No world-writable files in repository tree
  - ✅ SSH Key File Security Handling: Handles private keys via explicit identity parameter
- **Executability:**
  - ✅ Python Compilation (1/1 files): All python files bytecode-compiled cleanly
  - ✅ Shell Script Validation: No shell scripts in this branch
  - ✅ JavaScript Validation: No non-minified JavaScript files in this branch
  - ✅ CLI Entrypoint Execution (rssh_cli.py --help): Exited code 0

### Branch `ssh-web-client`
- **Functionality:**
  - ✅ ssh-web-client/server.py AST: Clean syntax and AST valid
  - ✅ ssh-web-client/service.sh bash syntax: Valid bash syntax
  - ✅ ssh-web-client web assets: Found 6 static files
- **Security:**
  - ✅ Credentials & Secret Exposure Scan: Zero leaked keys or tokens found
  - ✅ Python AST Static Security Analysis: No dangerous eval, exec, or unvalidated shell=True in daemons
  - ✅ File Permissions Hygiene: No world-writable files in repository tree
  - ✅ Secure TLS/WSS Transport Architecture: Enforces or dynamically resolves secure HTTPS/WSS protocols
- **Executability:**
  - ✅ Python Compilation (1/1 files): All python files bytecode-compiled cleanly
  - ✅ Shell Script Syntax (1/1 scripts): All shell scripts passed bash -n syntax validation
  - ✅ Shell Script Executability (1/1): All shell scripts have direct +x executable permissions
  - ✅ JavaScript Syntax (3/3 files): All JavaScript files verified with node -c

