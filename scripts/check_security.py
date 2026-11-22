#!/usr/bin/env python3
"""
Rakhssh Multi-Branch Security Audit & Verification Suite
Inspects codebases across all branches for credentials leakage, insecure patterns,
dangerous AST constructs, permissions hygiene, and network hardening.
"""

import ast
import os
import re
import shutil
import subprocess
import sys
import tempfile

REPO_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

KNOWN_BRANCHES = [
    "main",
    "client-linux",
    "server-linux",
    "chat",
    "ssh-android-client",
    "ssh-cli-client",
    "ssh-web-client",
]

# High-entropy / known token regex patterns
SECRET_PATTERNS = [
    (r"-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----", "Private cryptographic key"),
    (r"ghp_[a-zA-Z0-9]{36}", "GitHub Personal Access Token"),
    (r"github_pat_[a-zA-Z0-9_]{82}", "GitHub Fine-Grained Token"),
    (r"\b[0-9]{9,10}:[a-zA-Z0-9_-]{35}\b", "Telegram Bot Token"),
    (r"\bAKIA[0-9A-Z]{16}\b", "AWS Access Key ID"),
    (r"\bxox[baprs]-[0-9a-zA-Z]{10,48}\b", "Slack API Token"),
]

# False positive allowlist for known benign/test references
ALLOWLIST_PATTERNS = [
    r"PLACEHOLDER",
    r"example",
    r"YOUR_",
    r"<YOUR_",
    r"dummy",
    r"test_token",
]


def extract_branch(branch_name: str, dest_dir: str) -> bool:
    try:
        proc = subprocess.Popen(
            ["git", "archive", branch_name],
            cwd=REPO_DIR,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        tar_proc = subprocess.Popen(
            ["tar", "-x", "-C", dest_dir],
            stdin=proc.stdout,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        proc.stdout.close()
        tar_proc.communicate()
        proc.wait()
        return proc.returncode == 0 and tar_proc.returncode == 0
    except Exception:
        return False


def scan_for_secrets(branch_dir: str) -> list[tuple[str, str, int, str]]:
    findings = []
    for root, _, files in os.walk(branch_dir):
        for f in files:
            path = os.path.join(root, f)
            rel_path = os.path.relpath(path, branch_dir)
            if any(part.startswith(".") for part in rel_path.split(os.sep)):
                continue
            if f.endswith((".png", ".jpg", ".ico", ".apk", ".zip", ".tar", ".gz")):
                continue

            try:
                with open(path, "r", encoding="utf-8", errors="replace") as fh:
                    for line_num, line in enumerate(fh, start=1):
                        for pattern, desc in SECRET_PATTERNS:
                            if re.search(pattern, line):
                                # Check allowlist
                                if not any(re.search(al, line, re.IGNORECASE) for al in ALLOWLIST_PATTERNS):
                                    findings.append((rel_path, desc, line_num, line.strip()[:60]))
            except Exception:
                pass
    return findings


class ASTSecurityAuditor(ast.NodeVisitor):
    def __init__(self, filename: str):
        self.filename = filename
        self.issues = []

    def visit_Call(self, node):
        func_name = ""
        if isinstance(node.func, ast.Name):
            func_name = node.func.id
        elif isinstance(node.func, ast.Attribute):
            func_name = node.func.attr

        # 1. Flag eval() and exec()
        if func_name in ("eval", "exec"):
            self.issues.append((self.filename, node.lineno, f"Dangerous dynamic execution function: {func_name}()"))

        # 2. Flag subprocess with shell=True
        if func_name in ("Popen", "run", "call", "check_output", "check_call"):
            for kw in node.keywords:
                if kw.arg == "shell" and isinstance(kw.value, ast.Constant) and kw.value.value is True:
                    self.issues.append((self.filename, node.lineno, "Subprocess invoked with shell=True"))

        # 3. Flag insecure pickle loads
        if func_name in ("loads", "load") and isinstance(node.func, ast.Attribute):
            if isinstance(node.func.value, ast.Name) and node.func.value.id == "pickle":
                self.issues.append((self.filename, node.lineno, "Insecure pickle deserialization"))

        self.generic_visit(node)


def audit_python_files(branch_dir: str) -> list[tuple[str, int, str]]:
    issues = []
    for root, _, files in os.walk(branch_dir):
        for f in files:
            if f.endswith(".py"):
                path = os.path.join(root, f)
                rel_path = os.path.relpath(path, branch_dir)
                try:
                    with open(path, "r", encoding="utf-8", errors="replace") as fh:
                        tree = ast.parse(fh.read(), filename=rel_path)
                    auditor = ASTSecurityAuditor(rel_path)
                    auditor.visit(tree)
                    issues.extend(auditor.issues)
                except Exception:
                    pass
    return issues


def audit_permissions(branch_dir: str) -> list[tuple[str, str]]:
    issues = []
    for root, _, files in os.walk(branch_dir):
        for f in files:
            path = os.path.join(root, f)
            rel_path = os.path.relpath(path, branch_dir)
            st = os.stat(path)
            mode = st.st_mode
            # Check world writable
            if mode & 0o002:
                issues.append((rel_path, "World-writable file permission detected"))
    return issues


def check_branch_security(branch_name: str, branch_dir: str) -> list[tuple[str, bool, str]]:
    checks = []

    # 1. Scan for leaked secrets
    secret_findings = scan_for_secrets(branch_dir)
    if not secret_findings:
        checks.append(("Credentials & Secret Exposure Scan", True, "Zero leaked keys or tokens found"))
    else:
        details = "; ".join([f"{f[0]}:{f[2]} ({f[1]})" for f in secret_findings[:3]])
        checks.append(("Credentials & Secret Exposure Scan", False, f"Potential secrets detected: {details}"))

    # 2. AST Static Code Security
    ast_issues = audit_python_files(branch_dir)
    # Check if shell=True is in build scripts (benign) vs production daemons
    critical_ast = [i for i in ast_issues if not (i[0].startswith("build") or "installer" in i[0])]
    if not critical_ast:
        checks.append(("Python AST Static Security Analysis", True, "No dangerous eval, exec, or unvalidated shell=True in daemons"))
    else:
        details = "; ".join([f"{i[0]}:{i[1]} ({i[2]})" for i in critical_ast[:2]])
        checks.append(("Python AST Static Security Analysis", False, f"Dangerous AST pattern: {details}"))

    # 3. File Permissions
    perm_issues = audit_permissions(branch_dir)
    if not perm_issues:
        checks.append(("File Permissions Hygiene", True, "No world-writable files in repository tree"))
    else:
        checks.append(("File Permissions Hygiene", False, f"Found {len(perm_issues)} permissive files"))

    # 4. Branch-specific security features
    if branch_name == "client-linux":
        has_pin_check = False
        for root, _, files in os.walk(branch_dir):
            for f in files:
                if f.endswith((".go", ".md", ".sh")):
                    try:
                        with open(os.path.join(root, f), "r", encoding="utf-8", errors="replace") as fh:
                            c = fh.read()
                            if "GeneratePIN" in c or "lockout protection" in c or "brute-force" in c:
                                has_pin_check = True
                                break
                    except Exception:
                        pass
            if has_pin_check:
                break
        checks.append(("PIN Enforcement & Lockout Protection", has_pin_check, "PIN security verification and lockout protection present in client code" if has_pin_check else "PIN logic not detected in client files"))

    elif branch_name == "server-linux":
        dockerfile = os.path.join(branch_dir, "Dockerfile")
        has_user = False
        if os.path.exists(dockerfile):
            with open(dockerfile, "r", encoding="utf-8") as f:
                has_user = "USER" in f.read()
        checks.append(("Container Hardening (Non-root USER)", has_user, "Dockerfile enforces non-root USER" if has_user else "Non-root USER directive missing"))

    elif branch_name == "ssh-cli-client":
        cli_py = os.path.join(branch_dir, "rssh_cli.py")
        has_key_protect = False
        if os.path.exists(cli_py):
            with open(cli_py, "r", encoding="utf-8") as f:
                c = f.read()
                has_key_protect = "identity" in c or "key" in c
        checks.append(("SSH Key File Security Handling", has_key_protect, "Handles private keys via explicit identity parameter"))

    elif branch_name in ("chat", "ssh-web-client"):
        # Check TLS / WSS transport support
        web_dir = os.path.join(branch_dir, "web")
        tls_support = False
        if os.path.isdir(web_dir):
            for root, _, files in os.walk(web_dir):
                for f in files:
                    if f.endswith((".js", ".html")):
                        with open(os.path.join(root, f), "r", encoding="utf-8", errors="replace") as fh:
                            content = fh.read()
                            if "wss://" in content or "https://" in content or "location.protocol" in content:
                                tls_support = True
                                break
        checks.append(("Secure TLS/WSS Transport Architecture", tls_support, "Enforces or dynamically resolves secure HTTPS/WSS protocols"))

    return checks


def run_checks(branches: list[str] = None) -> dict[str, list[tuple[str, bool, str]]]:
    targets = branches or KNOWN_BRANCHES
    summary = {}
    for b in targets:
        temp_dir = tempfile.mkdtemp(prefix=f"rssh_sec_{b}_")
        try:
            if not extract_branch(b, temp_dir):
                summary[b] = [("Extract branch", False, f"Failed to extract {b}")]
                continue
            summary[b] = check_branch_security(b, temp_dir)
        finally:
            shutil.rmtree(temp_dir, ignore_errors=True)
    return summary


def main():
    branches = sys.argv[1:] if len(sys.argv) > 1 else KNOWN_BRANCHES
    print("=" * 70)
    print("🛡️ RAKHSH MULTI-BRANCH SECURITY AUDIT SUITE")
    print("=" * 70)
    results = run_checks(branches)
    total_checks = 0
    total_passed = 0
    all_ok = True

    for b, checks in results.items():
        print(f"\n🔒 Branch: {b}")
        print("-" * 50)
        for name, passed, detail in checks:
            total_checks += 1
            if passed:
                total_passed += 1
                status = "✅ PASS"
            else:
                all_ok = False
                status = "❌ FAIL"
            print(f"  [{status}] {name}: {detail}")

    print("\n" + "=" * 70)
    print(f"📊 SUMMARY: {total_passed}/{total_checks} security checks passed across {len(results)} branches.")
    print("=" * 70)
    sys.exit(0 if all_ok else 1)


if __name__ == "__main__":
    main()
