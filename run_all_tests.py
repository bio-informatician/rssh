#!/usr/bin/env python3
"""
Rakhssh Unified Multi-Branch Test Orchestrator
Executes functionality, security, and executability verification suites across all
branches in bio-informatician/rssh, generating an auditable verification report.
"""

import datetime
import os
import sys

# Add scripts directory to module path
SCRIPTS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "scripts")
sys.path.insert(0, SCRIPTS_DIR)

import check_functionality
import check_security
import check_executability

KNOWN_BRANCHES = [
    "main",
    "client-linux",
    "server-linux",
    "chat",
    "ssh-android-client",
    "ssh-cli-client",
    "ssh-web-client",
]


def print_banner():
    print("=" * 80)
    print("🚀 RAKHSH MULTI-BRANCH VERIFICATION & INTEGRITY TEST HARNESS")
    print(f"📅 Timestamp: {datetime.datetime.now().isoformat()}")
    print(f"📦 Repository: bio-informatician/rssh")
    print(f"🌿 Target Branches: {', '.join(KNOWN_BRANCHES)}")
    print("=" * 80)


def run_full_suite(branches: list[str] = None):
    targets = branches or KNOWN_BRANCHES
    print_banner()

    print("\n▶️ [1/3] Running Functionality Verification Suite...")
    func_results = check_functionality.run_checks(targets)

    print("\n▶️ [2/3] Running Security & Hardening Audit Suite...")
    sec_results = check_security.run_checks(targets)

    print("\n▶️ [3/3] Running Executability & Syntax Verification Suite...")
    exec_results = check_executability.run_checks(targets)

    # Aggregation
    branch_stats = {}
    total_tests = 0
    total_passed = 0
    total_failed = 0

    for b in targets:
        f_checks = func_results.get(b, [])
        s_checks = sec_results.get(b, [])
        e_checks = exec_results.get(b, [])
        all_b_checks = f_checks + s_checks + e_checks

        b_pass = sum(1 for c in all_b_checks if c[1])
        b_fail = sum(1 for c in all_b_checks if not c[1])
        branch_stats[b] = {
            "passed": b_pass,
            "failed": b_fail,
            "total": len(all_b_checks),
            "func": f_checks,
            "sec": s_checks,
            "exec": e_checks,
        }
        total_tests += len(all_b_checks)
        total_passed += b_pass
        total_failed += b_fail

    # Print Summary Table
    print("\n" + "=" * 80)
    print("📋 MULTI-BRANCH VERIFICATION SUMMARY")
    print("=" * 80)
    print(f"{'Branch':<24} | {'Functionality':<14} | {'Security':<14} | {'Executability':<14} | {'Status'}")
    print("-" * 80)

    all_passed = True
    for b in targets:
        st = branch_stats[b]
        f_p = sum(1 for c in st["func"] if c[1])
        f_t = len(st["func"])
        s_p = sum(1 for c in st["sec"] if c[1])
        s_t = len(st["sec"])
        e_p = sum(1 for c in st["exec"] if c[1])
        e_t = len(st["exec"])

        f_str = f"{f_p}/{f_t} OK"
        s_str = f"{s_p}/{s_t} OK"
        e_str = f"{e_p}/{e_t} OK"
        status_str = "✅ HEALTHY" if st["failed"] == 0 else "❌ BROKEN"
        if st["failed"] > 0:
            all_passed = False

        print(f"{b:<24} | {f_str:<14} | {s_str:<14} | {e_str:<14} | {status_str}")

    print("=" * 80)
    pass_pct = (total_passed / total_tests * 100) if total_tests > 0 else 0
    print(f"🏁 FINAL RESULT: {total_passed}/{total_tests} checks passed ({pass_pct:.1f}%).")
    if all_passed:
        print("🎉 ALL 7 BRANCHES ARE FULLY FUNCTIONAL, SECURE, AND EXECUTABLE!")
    else:
        print(f"⚠️ {total_failed} checks failed. See details above.")
    print("=" * 80)

    # Generate Markdown Report
    report_file = os.path.join(os.path.dirname(os.path.abspath(__file__)), "REPORT.md")
    with open(report_file, "w", encoding="utf-8") as rf:
        rf.write("# 🛡️ Rakhssh Multi-Branch Integrity & Security Audit Report\n\n")
        rf.write(f"- **Generated:** `{datetime.datetime.now().isoformat()}`\n")
        rf.write(f"- **Repository:** `bio-informatician/rssh`\n")
        rf.write(f"- **Result:** `{'100% HEALTHY' if all_passed else 'FAILURES DETECTED'}`\n")
        rf.write(f"- **Total Checks:** `{total_passed}/{total_tests}` passed\n\n")
        rf.write("| Branch | Functionality | Security | Executability | Status |\n")
        rf.write("|---|---|---|---|---|\n")
        for b in targets:
            st = branch_stats[b]
            f_p = sum(1 for c in st["func"] if c[1])
            f_t = len(st["func"])
            s_p = sum(1 for c in st["sec"] if c[1])
            s_t = len(st["sec"])
            e_p = sum(1 for c in st["exec"] if c[1])
            e_t = len(st["exec"])
            st_badge = "✅ PASS" if st["failed"] == 0 else "❌ FAIL"
            rf.write(f"| `{b}` | {f_p}/{f_t} | {s_p}/{s_t} | {e_p}/{e_t} | {st_badge} |\n")

        rf.write("\n## 🔍 Detailed Findings per Branch\n\n")
        for b in targets:
            rf.write(f"### Branch `{b}`\n")
            for cat_name, check_list in [("Functionality", branch_stats[b]["func"]),
                                         ("Security", branch_stats[b]["sec"]),
                                         ("Executability", branch_stats[b]["exec"])]:
                rf.write(f"- **{cat_name}:**\n")
                for name, passed, detail in check_list:
                    icon = "✅" if passed else "❌"
                    rf.write(f"  - {icon} {name}: {detail}\n")
            rf.write("\n")

    print(f"📄 Audit report written to: {report_file}")
    return all_passed


if __name__ == "__main__":
    branches_arg = sys.argv[1:] if len(sys.argv) > 1 else KNOWN_BRANCHES
    success = run_full_suite(branches_arg)
    sys.exit(0 if success else 1)
