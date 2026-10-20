// Copyright (C) 2026 Rakhssh Contributors - AGPLv3
package daemon

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestConfigRoundtrip(t *testing.T) {
	tmpDir := t.TempDir()
	cfgPath := filepath.Join(tmpDir, "test_config.json")

	cfg1, err := LoadOrCreateConfig(cfgPath, "Secret123", "ws://127.0.0.1:8443")
	if err != nil {
		t.Fatalf("LoadOrCreateConfig failed: %v", err)
	}
	if cfg1.Password != "Secret123" || cfg1.ServerURL != "ws://127.0.0.1:8443" {
		t.Fatalf("unexpected config values: %+v", cfg1)
	}

	// Read back
	cfg2, err := LoadOrCreateConfig(cfgPath, "", "")
	if err != nil {
		t.Fatalf("read back failed: %v", err)
	}
	if cfg2.MachineID != cfg1.MachineID || cfg2.Password != cfg1.Password || cfg2.ServerURL != cfg1.ServerURL {
		t.Fatalf("config mismatch on reload: %+v vs %+v", cfg1, cfg2)
	}
}

func TestGenerateSystemdService(t *testing.T) {
	unit := GenerateSystemdService("/usr/local/bin/rssh")
	if !strings.Contains(unit, "ExecStart=/usr/local/bin/rssh daemon") {
		t.Fatalf("systemd unit missing ExecStart: %s", unit)
	}
	if !strings.Contains(unit, "WantedBy=default.target") {
		t.Fatalf("systemd unit missing WantedBy: %s", unit)
	}
}

func TestInstallSystemdUserService(t *testing.T) {
	// Custom HOME to avoid polluting user's actual ~/.config
	tmpHome := t.TempDir()
	origHome := os.Getenv("HOME")
	_ = os.Setenv("HOME", tmpHome)
	defer os.Setenv("HOME", origHome)

	path, err := InstallSystemdUserService("/opt/rssh/rssh")
	if err != nil {
		t.Fatalf("InstallSystemdUserService failed: %v", err)
	}

	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("failed to read installed service: %v", err)
	}
	if !strings.Contains(string(data), "ExecStart=/opt/rssh/rssh daemon") {
		t.Fatalf("installed service content invalid: %s", string(data))
	}
}
