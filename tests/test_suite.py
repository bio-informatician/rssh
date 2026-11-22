#!/usr/bin/env python3
"""
Unit tests for the multi-branch verification test suite.
"""

import os
import sys
import unittest

ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPTS_DIR = os.path.join(ROOT_DIR, "scripts")
sys.path.insert(0, SCRIPTS_DIR)

import check_functionality
import check_security
import check_executability


class TestMultiBranchVerification(unittest.TestCase):
    def test_known_branches_list(self):
        self.assertEqual(len(check_functionality.KNOWN_BRANCHES), 7)
        self.assertIn("chat", check_functionality.KNOWN_BRANCHES)
        self.assertIn("client-linux", check_functionality.KNOWN_BRANCHES)
        self.assertIn("server-linux", check_functionality.KNOWN_BRANCHES)
        self.assertIn("ssh-cli-client", check_functionality.KNOWN_BRANCHES)
        self.assertIn("ssh-web-client", check_functionality.KNOWN_BRANCHES)

    def test_secret_scanner_false_positive_filtering(self):
        # Allowlist should prevent false alarms on template tokens
        dummy_line = "TOKEN = 'YOUR_TELEGRAM_BOT_TOKEN_PLACEHOLDER'"
        match = any(
            __import__("re").search(pat, dummy_line) and not any(__import__("re").search(al, dummy_line) for al in check_security.ALLOWLIST_PATTERNS)
            for pat, _ in check_security.SECRET_PATTERNS
        )
        self.assertFalse(match)

    def test_ast_security_auditor(self):
        sample_code = """
import os
import subprocess

def safe_run():
    subprocess.run(["ls", "-la"])

def unsafe_eval():
    eval("1 + 1")
"""
        tree = __import__("ast").parse(sample_code)
        auditor = check_security.ASTSecurityAuditor("sample.py")
        auditor.visit(tree)
        self.assertEqual(len(auditor.issues), 1)
        self.assertIn("eval", auditor.issues[0][2])


if __name__ == "__main__":
    unittest.main()
