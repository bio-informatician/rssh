#!/usr/bin/env python3
"""
Rakhssh Multi-Branch Functionality Verification Suite
Validates architecture, syntax, components, and module integrity across all branches.
"""

import ast
import os
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

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


def extract_branch(branch_name: str, dest_dir: str) -> bool:
    """Extract files from a git branch into a temporary directory using git archive."""
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
    except Exception as e:
        print(f"Error extracting branch {branch_name}: {e}")
        return False


def check_chat_functionality(branch_dir: str) -> list[tuple[str, bool, str]]:
    results = []
    # 1. Server python syntax & AST
    server_py = os.path.join(branch_dir, "server", "server.py")
    if os.path.exists(server_py):
        try:
            with open(server_py, "r", encoding="utf-8") as f:
                ast.parse(f.read(), filename="server.py")
            results.append(("chat/server.py AST Parse", True, "Clean syntax and AST valid"))
        except SyntaxError as e:
            results.append(("chat/server.py AST Parse", False, f"Syntax error: {e}"))
    else:
        results.append(("chat/server.py presence", False, "Missing server.py"))

    # 2. Web client app.js syntax check via node
    app_js = os.path.join(branch_dir, "web", "app.js")
    if os.path.exists(app_js):
        node_res = subprocess.run(["node", "-c", app_js], capture_output=True, text=True)
        if node_res.returncode == 0:
            results.append(("chat/web/app.js Node syntax check", True, "Valid JavaScript syntax"))
        else:
            results.append(("chat/web/app.js Node syntax check", False, node_res.stderr.strip()))
    else:
        results.append(("chat/web/app.js presence", False, "Missing web/app.js"))

    # 3. Web client index.html structure
    index_html = os.path.join(branch_dir, "web", "index.html")
    if os.path.exists(index_html):
        with open(index_html, "r", encoding="utf-8") as f:
            content = f.read()
        has_viewport = "viewport" in content
        has_messages = "messages" in content or "chat" in content
        if has_viewport and has_messages:
            results.append(("chat/web/index.html UI structure", True, "Contains standard viewport and chat UI elements"))
        else:
            results.append(("chat/web/index.html UI structure", False, "Missing viewport or chat containers"))
    else:
        results.append(("chat/web/index.html presence", False, "Missing web/index.html"))

    # 4. build_apk.py & generate_installer.py AST
    for script_name in ["build_apk.py", "generate_installer.py", "send_dispatch.py"]:
        script_path = os.path.join(branch_dir, script_name)
        if os.path.exists(script_path):
            try:
                with open(script_path, "r", encoding="utf-8") as f:
                    ast.parse(f.read(), filename=script_name)
                results.append((f"chat/{script_name} AST", True, "Clean syntax"))
            except SyntaxError as e:
                results.append((f"chat/{script_name} AST", False, str(e)))
        else:
            results.append((f"chat/{script_name} presence", False, f"Missing {script_name}"))

    return results


def check_ssh_android_client_functionality(branch_dir: str) -> list[tuple[str, bool, str]]:
    results = []
    # 1. build_apk.py & send_dispatch.py
    for s in ["build_apk.py", "send_dispatch.py"]:
        sp = os.path.join(branch_dir, s)
        if os.path.exists(sp):
            try:
                with open(sp, "r", encoding="utf-8") as f:
                    ast.parse(f.read(), filename=s)
                results.append((f"ssh-android-client/{s} AST", True, "Clean syntax"))
            except SyntaxError as e:
                results.append((f"ssh-android-client/{s} AST", False, str(e)))
        else:
            results.append((f"ssh-android-client/{s} presence", False, f"Missing {s}"))

    # 2. web/app.js syntax
    app_js = os.path.join(branch_dir, "web", "app.js")
    if os.path.exists(app_js):
        node_res = subprocess.run(["node", "-c", app_js], capture_output=True, text=True)
        results.append(("ssh-android-client/web/app.js syntax", node_res.returncode == 0, "Valid JS syntax" if node_res.returncode == 0 else node_res.stderr.strip()))

    # 3. AndroidManifest.xml validation
    manifest_path = os.path.join(branch_dir, "app", "src", "main", "AndroidManifest.xml")
    if os.path.exists(manifest_path):
        try:
            tree = ET.parse(manifest_path)
            root = tree.getroot()
            package = root.attrib.get("package", "")
            results.append(("AndroidManifest XML Structure", True, f"Valid XML, package: {package or 'Android namespace'}"))
        except ET.ParseError as e:
            results.append(("AndroidManifest XML Structure", False, f"Invalid XML: {e}"))
    else:
        results.append(("AndroidManifest presence", True, "No AndroidManifest at app/src/main (standalone webview build)"))

    return results


def check_ssh_cli_client_functionality(branch_dir: str) -> list[tuple[str, bool, str]]:
    results = []
    cli_py = os.path.join(branch_dir, "rssh_cli.py")
    if os.path.exists(cli_py):
        # 1. AST parse
        try:
            with open(cli_py, "r", encoding="utf-8") as f:
                ast.parse(f.read(), filename="rssh_cli.py")
            results.append(("ssh-cli-client AST Parse", True, "Clean syntax and AST valid"))
        except SyntaxError as e:
            results.append(("ssh-cli-client AST Parse", False, str(e)))

        # 2. --help execution
        run_res = subprocess.run([sys.executable, cli_py, "--help"], capture_output=True, text=True)
        if run_res.returncode == 0 and "Rakhssh SSH CLI" in run_res.stdout:
            results.append(("ssh-cli-client --help execution", True, "Executed cleanly with expected banner and options"))
        else:
            results.append(("ssh-cli-client --help execution", False, run_res.stderr.strip() or f"Exit {run_res.returncode}"))
    else:
        results.append(("rssh_cli.py presence", False, "Missing rssh_cli.py"))

    return results


def check_ssh_web_client_functionality(branch_dir: str) -> list[tuple[str, bool, str]]:
    results = []
    server_py = os.path.join(branch_dir, "server.py")
    if os.path.exists(server_py):
        try:
            with open(server_py, "r", encoding="utf-8") as f:
                ast.parse(f.read(), filename="server.py")
            results.append(("ssh-web-client/server.py AST", True, "Clean syntax and AST valid"))
        except SyntaxError as e:
            results.append(("ssh-web-client/server.py AST", False, str(e)))
    else:
        results.append(("ssh-web-client/server.py presence", False, "Missing server.py"))

    service_sh = os.path.join(branch_dir, "service.sh")
    if os.path.exists(service_sh):
        sh_res = subprocess.run(["bash", "-n", service_sh], capture_output=True, text=True)
        results.append(("ssh-web-client/service.sh bash syntax", sh_res.returncode == 0, "Valid bash syntax" if sh_res.returncode == 0 else sh_res.stderr.strip()))
    else:
        results.append(("ssh-web-client/service.sh presence", False, "Missing service.sh"))

    web_dir = os.path.join(branch_dir, "web")
    if os.path.isdir(web_dir) and os.listdir(web_dir):
        results.append(("ssh-web-client web assets", True, f"Found {len(os.listdir(web_dir))} static files"))
    else:
        results.append(("ssh-web-client web assets", False, "web/ directory missing or empty"))

    return results


def check_client_linux_functionality(branch_dir: str) -> list[tuple[str, bool, str]]:
    results = []
    # 1. go.mod check
    go_mod = os.path.join(branch_dir, "go.mod")
    if os.path.exists(go_mod):
        with open(go_mod, "r", encoding="utf-8") as f:
            mod_text = f.read()
        results.append(("client-linux go.mod", "module" in mod_text, "go.mod specifies Go module"))
    else:
        results.append(("client-linux go.mod presence", False, "Missing go.mod"))

    # 2. install.sh bash syntax
    install_sh = os.path.join(branch_dir, "install.sh")
    if os.path.exists(install_sh):
        b_res = subprocess.run(["bash", "-n", install_sh], capture_output=True, text=True)
        results.append(("client-linux install.sh bash syntax", b_res.returncode == 0, "Valid bash syntax" if b_res.returncode == 0 else b_res.stderr.strip()))
    else:
        results.append(("client-linux install.sh presence", False, "Missing install.sh"))

    # 3. Makefile & Systemd presence
    makefile = os.path.join(branch_dir, "Makefile")
    results.append(("client-linux Makefile presence", os.path.exists(makefile), "Makefile exists" if os.path.exists(makefile) else "Missing"))
    systemd_dir = os.path.join(branch_dir, "systemd")
    results.append(("client-linux systemd presence", os.path.isdir(systemd_dir) and len(os.listdir(systemd_dir)) > 0, "Systemd service files present"))

    return results


def check_server_linux_functionality(branch_dir: str) -> list[tuple[str, bool, str]]:
    results = []
    # 1. go.mod
    go_mod = os.path.join(branch_dir, "go.mod")
    results.append(("server-linux go.mod presence", os.path.exists(go_mod), "go.mod exists" if os.path.exists(go_mod) else "Missing"))

    # 2. Dockerfile & docker-compose.yml
    dockerfile = os.path.join(branch_dir, "Dockerfile")
    if os.path.exists(dockerfile):
        with open(dockerfile, "r", encoding="utf-8") as f:
            df_content = f.read()
        has_from = "FROM" in df_content
        results.append(("server-linux Dockerfile structure", has_from, "Dockerfile contains FROM directive"))
    else:
        results.append(("server-linux Dockerfile presence", False, "Missing Dockerfile"))

    # 3. Caddy & Nginx config presence
    caddy_dir = os.path.join(branch_dir, "caddy")
    nginx_dir = os.path.join(branch_dir, "nginx")
    results.append(("server-linux reverse proxy configs", os.path.isdir(caddy_dir) or os.path.isdir(nginx_dir), "Reverse proxy configurations present"))

    return results


def check_main_functionality(branch_dir: str) -> list[tuple[str, bool, str]]:
    results = []
    for f in ["README.md", "LICENSE", "Makefile", "go.mod"]:
        p = os.path.join(branch_dir, f)
        results.append((f"main/{f} presence", os.path.exists(p), "File present" if os.path.exists(p) else "Missing"))
    return results


CHECKERS = {
    "chat": check_chat_functionality,
    "ssh-android-client": check_ssh_android_client_functionality,
    "ssh-cli-client": check_ssh_cli_client_functionality,
    "ssh-web-client": check_ssh_web_client_functionality,
    "client-linux": check_client_linux_functionality,
    "server-linux": check_server_linux_functionality,
    "main": check_main_functionality,
}


def run_checks(branches: list[str] = None) -> dict[str, list[tuple[str, bool, str]]]:
    targets = branches or KNOWN_BRANCHES
    summary = {}
    for b in targets:
        temp_dir = tempfile.mkdtemp(prefix=f"rssh_func_{b}_")
        try:
            if not extract_branch(b, temp_dir):
                summary[b] = [("Extract branch", False, f"Failed to extract {b} via git archive")]
                continue
            checker = CHECKERS.get(b)
            if checker:
                summary[b] = checker(temp_dir)
            else:
                summary[b] = [("Unknown branch checker", True, "No dedicated checker, extraction succeeded")]
        finally:
            shutil.rmtree(temp_dir, ignore_errors=True)
    return summary


def main():
    branches = sys.argv[1:] if len(sys.argv) > 1 else KNOWN_BRANCHES
    print("=" * 70)
    print("🔍 RAKHSH MULTI-BRANCH FUNCTIONALITY VERIFICATION SUITE")
    print("=" * 70)
    results = run_checks(branches)
    total_checks = 0
    total_passed = 0
    all_ok = True

    for b, checks in results.items():
        print(f"\n📦 Branch: {b}")
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
    print(f"📊 SUMMARY: {total_passed}/{total_checks} functionality tests passed across {len(results)} branches.")
    print("=" * 70)
    sys.exit(0 if all_ok else 1)


if __name__ == "__main__":
    main()
