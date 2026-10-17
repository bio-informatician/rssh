package daemon

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"

	"rssh/pkg/id"
)

// Config stores unattended host settings
type Config struct {
	MachineID string `json:"machine_id"`
	Password  string `json:"password"`
	ServerURL string `json:"server_url"`
}

// DefaultConfigPath returns ~/.config/rssh/config.json
func DefaultConfigPath() string {
	home, err := os.UserHomeDir()
	if err != nil {
		home = "."
	}
	return filepath.Join(home, ".config", "rssh", "config.json")
}

// LoadOrCreateConfig loads existing config or initializes a new one with a persistent ID
func LoadOrCreateConfig(path string, fallbackPassword, defaultServer string) (*Config, error) {
	if path == "" {
		path = DefaultConfigPath()
	}

	data, err := os.ReadFile(path)
	if err == nil {
		var cfg Config
		if err := json.Unmarshal(data, &cfg); err == nil && cfg.MachineID != "" {
			if fallbackPassword != "" {
				cfg.Password = fallbackPassword
			}
			if defaultServer != "" && cfg.ServerURL == "" {
				cfg.ServerURL = defaultServer
			}
			return &cfg, nil
		}
	}

	// Create new configuration
	machineID := id.GeneratePersistentID()
	password := fallbackPassword
	if password == "" {
		generatedPIN, err := id.GeneratePIN(6)
		if err != nil {
			return nil, err
		}
		password = generatedPIN
	}

	cfg := &Config{
		MachineID: machineID,
		Password:  password,
		ServerURL: defaultServer,
	}

	if err := SaveConfig(path, cfg); err != nil {
		return nil, err
	}

	return cfg, nil
}

// SaveConfig writes the configuration to disk
func SaveConfig(path string, cfg *Config) error {
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0700); err != nil {
		return fmt.Errorf("failed to create config dir: %w", err)
	}

	data, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return err
	}

	return os.WriteFile(path, data, 0600)
}

// GenerateSystemdService creates a systemd user unit configuration string
func GenerateSystemdService(binaryPath string) string {
	return fmt.Sprintf(`[Unit]
Description=Rakhssh (rssh) Rootless P2P Host Daemon
After=network.target

[Service]
Type=simple
ExecStart=%s daemon
Restart=always
RestartSec=5s

[Install]
WantedBy=default.target
`, binaryPath)
}

// InstallSystemdUserService writes the service file to ~/.config/systemd/user/rssh.service
func InstallSystemdUserService(binaryPath string) (string, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}

	dir := filepath.Join(home, ".config", "systemd", "user")
	if err := os.MkdirAll(dir, 0755); err != nil {
		return "", err
	}

	serviceFile := filepath.Join(dir, "rssh.service")
	content := GenerateSystemdService(binaryPath)
	if err := os.WriteFile(serviceFile, []byte(content), 0644); err != nil {
		return "", err
	}

	return serviceFile, nil
}
