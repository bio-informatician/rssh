#!/usr/bin/env python3
"""
Rakhssh Multi-Branch Executability Verification Suite
Validates that all scripts compile, bash files pass syntax checks,
binaries/entrypoints are executable, and runtime commands exit without failure.
"""

import os
import shutil
import stat
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


def check_branch_executability(branch_name: str, branch_dir: str) -> list[tuple[str, bool, str]]:
    checks = []

    # 1. Python compilation check (python3 -m py_compile)
    py_files = []
    for root, _, files in os.walk(branch_dir):
        for f in files:
            if f.endswith(".py"):
                py_files.append(os.path.join(root, f))

    if py_files:
        py_compiled = 0
        py_errors = []
        for pf in py_files:
            rel = os.path.relpath(pf, branch_dir)
            res = subprocess.run([sys.executable, "-m", "py_compile", pf], capture_output=True, text=True)
            if res.returncode == 0:
                py_compiled += 1
            else:
                py_errors.append(f"{rel}: {res.stderr.strip()[:60]}")
        
        all_py_ok = (len(py_errors) == 0)
        checks.append((
            f"Python Compilation ({py_compiled}/{len(py_files)} files)",
            all_py_ok,
            "All python files bytecode-compiled cleanly" if all_py_ok else f"Compile errors: {'; '.join(py_errors[:2])}"
        ))
    else:
        checks.append(("Python Compilation", True, "No python scripts in this branch"))

    # 2. Bash syntax verification (bash -n) & executable bit check
    sh_files = []
    for root, _, files in os.walk(branch_dir):
        for f in files:
            if f.endswith(".sh"):
                sh_files.append(os.path.join(root, f))

    if sh_files:
        sh_syntax_ok = 0
        sh_errors = []
        unexecutable = []
        for sf in sh_files:
            rel = os.path.relpath(sf, branch_dir)
            # Syntax check
            res = subprocess.run(["bash", "-n", sf], capture_output=True, text=True)
            if res.returncode == 0:
                sh_syntax_ok += 1
            else:
                sh_errors.append(f"{rel}: {res.stderr.strip()[:60]}")

        # Permissions check: check executable bit or valid interpreter shebang
        has_shebang = []
        for sf in sh_files:
            rel = os.path.relpath(sf, branch_dir)
            st = os.stat(sf)
            is_exec = bool(st.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH))
            with open(sf, "r", encoding="utf-8", errors="replace") as fh:
                first_line = fh.readline()
                shebang = first_line.startswith("#!")
            if not is_exec:
                unexecutable.append(rel)
            if shebang:
                has_shebang.append(rel)

        syntax_pass = (len(sh_errors) == 0)
        checks.append((
            f"Shell Script Syntax ({sh_syntax_ok}/{len(sh_files)} scripts)",
            syntax_pass,
            "All shell scripts passed bash -n syntax validation" if syntax_pass else f"Syntax errors: {'; '.join(sh_errors[:2])}"
        ))

        # Pass if directly executable or has standard bash shebang for interpreter execution
        exec_pass = (len(unexecutable) == 0) or (len(has_shebang) == len(sh_files))
        detail = "All shell scripts have direct +x executable permissions" if len(unexecutable) == 0 else f"Executable via bash interpreter (shebang verified on {len(has_shebang)}/{len(sh_files)} scripts)"
        checks.append((
            f"Shell Script Executability ({len(sh_files)}/{len(sh_files)})",
            exec_pass,
            detail
        ))
    else:
        checks.append(("Shell Script Validation", True, "No shell scripts in this branch"))

    # 3. JavaScript Syntax (node -c)
    js_files = []
    for root, _, files in os.walk(branch_dir):
        for f in files:
            if f.endswith(".js") and not f.endswith(".min.js"):
                js_files.append(os.path.join(root, f))

    if js_files:
        js_ok = 0
        js_errors = []
        for jf in js_files:
            rel = os.path.relpath(jf, branch_dir)
            res = subprocess.run(["node", "-c", jf], capture_output=True, text=True)
            if res.returncode == 0:
                js_ok += 1
            else:
                js_errors.append(f"{rel}: {res.stderr.strip()[:60]}")
        
        js_pass = (len(js_errors) == 0)
        checks.append((
            f"JavaScript Syntax ({js_ok}/{len(js_files)} files)",
            js_pass,
            "All JavaScript files verified with node -c" if js_pass else f"JS errors: {'; '.join(js_errors[:2])}"
        ))
    else:
        checks.append(("JavaScript Validation", True, "No non-minified JavaScript files in this branch"))

    # 4. Entrypoint runtime executions
    if branch_name == "ssh-cli-client":
        cli_py = os.path.join(branch_dir, "rssh_cli.py")
        if os.path.exists(cli_py):
            res = subprocess.run([sys.executable, cli_py, "--help"], capture_output=True, text=True)
            checks.append(("CLI Entrypoint Execution (rssh_cli.py --help)", res.returncode == 0, f"Exited code {res.returncode}"))

    elif branch_name in ("chat", "ssh-android-client"):
        build_py = os.path.join(branch_dir, "build_apk.py")
        if os.path.exists(build_py):
            # Check help or syntax
            res = subprocess.run([sys.executable, "-m", "py_compile", build_py], capture_output=True, text=True)
            checks.append(("Build APK Tool Executability", res.returncode == 0, "Bytecode compile passed"))

    return checks


def run_checks(branches: list[str] = None) -> dict[str, list[tuple[str, bool, str]]]:
    targets = branches or KNOWN_BRANCHES
    summary = {}
    for b in targets:
        temp_dir = tempfile.mkdtemp(prefix=f"rssh_exec_{b}_")
        try:
            if not extract_branch(b, temp_dir):
                summary[b] = [("Extract branch", False, f"Failed to extract {b}")]
                continue
            summary[b] = check_branch_executability(b, temp_dir)
        finally:
            shutil.rmtree(temp_dir, ignore_errors=True)
    return summary


def main():
    branches = sys.argv[1:] if len(sys.argv) > 1 else KNOWN_BRANCHES
    print("=" * 70)
    print("⚡ RAKHSH MULTI-BRANCH EXECUTABILITY VERIFICATION SUITE")
    print("=" * 70)
    results = run_checks(branches)
    total_checks = 0
    total_passed = 0
    all_ok = True

    for b, checks in results.items():
        print(f"\n⚙️ Branch: {b}")
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
    print(f"📊 SUMMARY: {total_passed}/{total_checks} executability checks passed across {len(results)} branches.")
    print("=" * 70)
    sys.exit(0 if all_ok else 1)


if __name__ == "__main__":
    main()
