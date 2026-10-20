// Copyright (C) 2026 Rakhssh Contributors - AGPLv3
package main

import (
	"context"
	"fmt"
	"io"
	"log"
	"net"
	"net/url"
	"os"
	"os/signal"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/spf13/cobra"
	"golang.org/x/term"

	"rssh/pkg/audit"
	"rssh/pkg/chat"
	"rssh/pkg/daemon"
	"rssh/pkg/id"
	"rssh/pkg/pty"
	"rssh/pkg/signaling"
	"rssh/pkg/sshserver"
	"rssh/pkg/transport"
	"rssh/pkg/tunnel"
)

var (
	flagServer       string
	flagPIN          string
	flagPasswordFile string
	flagLocalFwd     string
	flagSocksPort    int
	flagP2PTimeout   int
	flagDebug        bool
)

func getDefaultServer() string {
	if s := os.Getenv("RSSH_SERVER"); s != "" {
		return s
	}
	return "wss://relay.rakhssh.com"
}

func dialSignaling(serverURL string) (*signaling.Client, error) {
	if err := validateServerURL(serverURL); err != nil {
		return nil, err
	}
	return signaling.Dial(serverURL)
}

func validateServerURL(serverURL string) error {
	u, err := url.Parse(serverURL)
	if err != nil {
		return fmt.Errorf("invalid server URL %q: %w", serverURL, err)
	}
	if u.Scheme == "ws" {
		h := u.Hostname()
		if h != "localhost" && h != "127.0.0.1" && h != "::1" && os.Getenv("RSSH_ALLOW_INSECURE_WS") != "1" {
			return fmt.Errorf("security error: unencrypted ws:// connection rejected for non-loopback host %q (use wss:// or set RSSH_ALLOW_INSECURE_WS=1 to override)", h)
		}
	}
	return nil
}

func resolvePIN() string {
	pin := flagPIN
	if pin == "" && flagPasswordFile != "" {
		if b, err := os.ReadFile(flagPasswordFile); err == nil {
			pin = strings.TrimSpace(string(b))
		}
	}
	if pin == "" {
		pin = os.Getenv("RSSH_PIN")
	}
	if pin == "" {
		pin = os.Getenv("RSSH_PASSWORD")
	}
	return pin
}

func promptPIN() string {
	pin := resolvePIN()
	if pin != "" {
		return pin
	}
	fmt.Fprint(os.Stderr, "🔑 Enter PIN/Password: ")
	bytePin, err := term.ReadPassword(int(os.Stdin.Fd()))
	fmt.Fprintln(os.Stderr)
	if err != nil {
		log.Fatalf("failed to read password: %v", err)
	}
	return strings.TrimSpace(string(bytePin))
}

func main() {
	if err := newRootCmd().Execute(); err != nil {
		os.Exit(1)
	}
}

func newRootCmd() *cobra.Command {
	rootCmd := &cobra.Command{
		Use:   "rssh [command or host-id]",
		Short: "🐎⚡ Rakhssh: Stealth P2P SSH & Terminal Sharing",
		Long: `Rakhssh (rssh) is a zero-configuration, rootless, peer-to-peer SSH
and pseudo-terminal ecosystem tool operating behind strict NATs and firewalls.`,
		Args: cobra.ArbitraryArgs,
		Run: func(cmd *cobra.Command, args []string) {
			if len(args) == 0 {
				_ = cmd.Help()
				return
			}
			// If first arg looks like an ID, treat as connect
			targetID := args[0]
			if id.ValidateID(targetID) {
				runConnect(targetID)
				return
			}
			_ = cmd.Help()
		},
	}

	rootCmd.PersistentFlags().StringVarP(&flagServer, "server", "s", getDefaultServer(), "Signaling & relay server URL")
	rootCmd.PersistentFlags().StringVarP(&flagPIN, "pin", "p", "", "PIN or password for authentication")
	rootCmd.PersistentFlags().StringVar(&flagPasswordFile, "password-file", "", "Path to file containing password or PIN (avoids process listing exposure)")
	rootCmd.PersistentFlags().IntVar(&flagP2PTimeout, "p2p-timeout", 2, "Seconds to attempt P2P before falling back to relay")
	rootCmd.PersistentFlags().BoolVarP(&flagDebug, "debug", "v", false, "Enable verbose diagnostic tracing")

	// Subcommands
	rootCmd.AddCommand(newHostCmd())
	rootCmd.AddCommand(newConnectCmd())
	rootCmd.AddCommand(newProxyCmd())
	rootCmd.AddCommand(newForwardCmd())
	rootCmd.AddCommand(newDaemonCmd())
	rootCmd.AddCommand(newBlockCmd())
	rootCmd.AddCommand(newUnblockCmd())
	rootCmd.AddCommand(newBlockedCmd())
	rootCmd.AddCommand(newChatCmd())

	return rootCmd
}

func newHostCmd() *cobra.Command {
	var hostID string
	cmd := &cobra.Command{
		Use:   "host",
		Short: "Host a remote terminal session with a temporary ID and PIN",
		Run: func(cmd *cobra.Command, args []string) {
			if hostID == "" {
				// Use local cryptographic Ed25519 identity
				ident, err := id.LoadOrCreateIdentity("")
				if err == nil {
					hostID = ident.ID
				} else {
					generated, err := id.GenerateRandomID()
					if err != nil {
						log.Fatalf("failed to generate ID: %v", err)
					}
					hostID = generated
				}
			}
			pin := resolvePIN()
			if pin == "" {
				generatedPIN, err := id.GeneratePIN(6)
				if err != nil {
					log.Fatalf("failed to generate PIN: %v", err)
				}
				pin = generatedPIN
			}

			runHost(hostID, pin, flagServer)
		},
	}
	cmd.Flags().StringVar(&hostID, "id", "", "Custom 9-digit ID (XXX-XXX-XXX)")
	return cmd
}

func newConnectCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "connect <id>",
		Short: "Connect directly to a remote host terminal",
		Args:  cobra.ExactArgs(1),
		Run: func(cmd *cobra.Command, args []string) {
			runConnect(args[0])
		},
	}
}

func newProxyCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "proxy <id>",
		Short: "Bridge stdin/stdout to remote SSH server (for OpenSSH ProxyCommand)",
		Args:  cobra.ExactArgs(1),
		Run: func(cmd *cobra.Command, args []string) {
			runProxy(args[0])
		},
	}
}

func newForwardCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "forward <id>",
		Short: "Forward ports or launch SOCKS5 proxy through remote host",
		Args:  cobra.ExactArgs(1),
		Run: func(cmd *cobra.Command, args []string) {
			runForward(args[0])
		},
	}
	cmd.Flags().StringVarP(&flagLocalFwd, "local", "L", "", "Local port forward [bind_addr:]local_port:remote_host:remote_port")
	cmd.Flags().IntVarP(&flagSocksPort, "socks", "D", 0, "Dynamic SOCKS5 proxy port")
	return cmd
}

func newDaemonCmd() *cobra.Command {
	var installSystemd bool
	cmd := &cobra.Command{
		Use:   "daemon",
		Short: "Run unattended persistent host daemon",
		Run: func(cmd *cobra.Command, args []string) {
			if installSystemd {
				binPath, err := os.Executable()
				if err != nil {
					log.Fatalf("failed to get binary path: %v", err)
				}
				svcPath, err := daemon.InstallSystemdUserService(binPath)
				if err != nil {
					log.Fatalf("failed to install systemd user service: %v", err)
				}
				fmt.Printf("✔ Installed systemd user service at: %s\n", svcPath)
				fmt.Println("To enable and start on boot, run:")
				fmt.Println("  systemctl --user daemon-reload")
				fmt.Println("  systemctl --user enable --now rssh")
				return
			}

			password := resolvePIN()
			cfg, err := daemon.LoadOrCreateConfig("", password, flagServer)
			if err != nil {
				log.Fatalf("failed to load daemon config: %v", err)
			}
			runHost(cfg.MachineID, cfg.Password, cfg.ServerURL)
		},
	}
	cmd.Flags().BoolVar(&installSystemd, "install-systemd", false, "Generate and install systemd user service")
	return cmd
}

func newBlockCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "block <client-id>",
		Short: "Permanently ban an unauthorized client ID",
		Args:  cobra.ExactArgs(1),
		Run: func(cmd *cobra.Command, args []string) {
			b := audit.NewBlocklist("")
			if err := b.Block(args[0]); err != nil {
				log.Fatalf("failed to block client: %v", err)
			}
			fmt.Printf("✔ Client %s added to permanent blocklist (~/.config/rssh/blocked_clients)\n", args[0])
		},
	}
}

func newUnblockCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "unblock <client-id>",
		Short: "Remove a client ID from the permanent blocklist",
		Args:  cobra.ExactArgs(1),
		Run: func(cmd *cobra.Command, args []string) {
			b := audit.NewBlocklist("")
			if err := b.Unblock(args[0]); err != nil {
				log.Fatalf("failed to unblock client: %v", err)
			}
			fmt.Printf("✔ Client %s removed from blocklist\n", args[0])
		},
	}
}

func newBlockedCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "blocked",
		Short: "List all currently banned client IDs",
		Run: func(cmd *cobra.Command, args []string) {
			b := audit.NewBlocklist("")
			list := b.List()
			if len(list) == 0 {
				fmt.Println("No clients are currently blocked.")
				return
			}
			fmt.Println("Permanently blocked client IDs:")
			for _, id := range list {
				fmt.Printf(" - %s\n", id)
			}
		},
	}
}

// safeID returns at most 8 characters from an ID without panicking on short strings.
func safeID(id string) string {
	if len(id) > 8 {
		return id[:8]
	}
	return id
}

// sanitizeForTerminal strips control characters from externally-supplied strings
// before they are printed or broadcast to terminals, preventing escape injection.
func sanitizeForTerminal(s string) string {
	out := make([]byte, 0, len(s))
	for i := 0; i < len(s); i++ {
		b := s[i]
		// Allow printable ASCII, space, tab, newline; strip everything else
		if (b >= 0x20 && b < 0x7F) || b == '\t' || b == '\n' || b >= 0x80 {
			out = append(out, b)
		}
	}
	return string(out)
}

func runHost(hostID, pin, serverURL string) {
	var (
		pinMu          sync.RWMutex
		activePIN      = pin
		failedAttempts int
	)

	fmt.Printf("\n🐎⚡ Rakhssh is ready!\n")
	fmt.Printf("   ├── Machine ID : %s\n", hostID)
	fmt.Printf("   ├── Secret PIN : %s\n", activePIN)
	fmt.Printf("   └── Server     : %s\n\n", serverURL)
	fmt.Println("Waiting for rider...")

	auditLogger := audit.NewLogger("")
	blocklist := audit.NewBlocklist("")

	// Flush any pending security notices accumulated while offline
	daemon.FlushPendingNotices(os.Stderr)

	sigClient, err := dialSignaling(serverURL)
	if err != nil {
		log.Fatalf("failed to connect to signaling server %s: %v", serverURL, err)
	}
	defer sigClient.Close()

	ctx := context.Background()
	if err := sigClient.RegisterHost(ctx, hostID); err != nil {
		log.Fatalf("registration failed: %v", err)
	}

	// Initialize embedded SSH server
	sshSrv, err := sshserver.NewServer()
	if err != nil {
		log.Fatalf("failed to start embedded ssh server: %v", err)
	}
	defer sshSrv.Close()

	// Initialize persistent PTY session
	ptySess, err := pty.StartSession("", 80, 24)
	if err != nil {
		log.Fatalf("failed to start pty session: %v", err)
	}
	defer ptySess.Close()

	sessionCh := make(chan string, 10)
	sigClient.SetHandlers(
		func(sessionID string) {
			sessionCh <- sessionID
		},
		nil, nil, nil, nil,
	)
	sigClient.SetTerminationHandler(func(sid, reason string) {
		safeReason := sanitizeForTerminal(reason)
		fmt.Printf("[-] Session %s terminated by server: %s\n", safeID(sid), safeReason)
		daemon.BroadcastSecurityNotice(fmt.Sprintf("Session %s terminated by server: %s", safeID(sid), safeReason))
		_ = auditLogger.Log(audit.EventSessionDisconnected, safeID(sid), sid, "", fmt.Sprintf("Server terminated: %s", safeReason))
		_ = sigClient.Close()
	})

	// Keep alive loop handling incoming sessions
	for sessionID := range sessionCh {
		sid8 := safeID(sessionID)
		fmt.Printf("[+] Incoming rider connection (Session: %s)\n", sid8)
		daemon.BroadcastSecurityNotice(fmt.Sprintf("Incoming rider connection for Session %s", sid8))

		if blocklist.IsBlocked(sid8) {
			fmt.Printf("[-] Rejected connection from blocked client %s\n", sid8)
			daemon.BroadcastSecurityNotice(fmt.Sprintf("Rejected connection from blocked client %s", sid8))
			_ = auditLogger.Log(audit.EventSessionRejected, sid8, sessionID, "", "Client on permanent blocklist")
			continue
		}

		go func(sid string) {
			defer func() {
				if r := recover(); r != nil {
					fmt.Printf("[-] Panic recovered in session %s handler: %v\n", safeID(sid), r)
				}
			}()

			pinMu.RLock()
			currentPIN := activePIN
			pinMu.RUnlock()

			session, err := transport.OrchestrateHost(ctx, sigClient, sid, currentPIN, time.Duration(flagP2PTimeout)*time.Second)
			if err != nil {
				fmt.Printf("[-] Handshake failed for session %s: %v\n", safeID(sid), err)
				daemon.BroadcastSecurityNotice(fmt.Sprintf("Handshake failed for Session %s", safeID(sid)))
				_ = auditLogger.Log(audit.EventSessionRejected, safeID(sid), sid, "", fmt.Sprintf("Handshake error: %v", err))

				pinMu.Lock()
				failedAttempts++
				if failedAttempts >= 3 {
					if newPin, genErr := id.GeneratePIN(6); genErr == nil {
						activePIN = newPin
						failedAttempts = 0
						fmt.Printf("\n⚠️  [SECURITY LOCKOUT] 3 consecutive handshake failures detected!\n")
						fmt.Printf("⚠️  PIN brute-force lockout triggered. New Secret PIN: %s\n\n", activePIN)
						daemon.BroadcastSecurityNotice(fmt.Sprintf("Brute-force lockout: PIN rotated to %s", activePIN))
						_ = auditLogger.Log(audit.EventSessionRejected, safeID(sid), sid, "", fmt.Sprintf("3 failed attempts: PIN rotated to %s", activePIN))
					}
				}
				pinMu.Unlock()
				time.Sleep(1 * time.Second)
				return
			}
			defer session.Close()

			pinMu.Lock()
			failedAttempts = 0
			pinMu.Unlock()

			session.SetSessionTimeouts(30*time.Minute, 2*time.Hour)
			_ = auditLogger.Log(audit.EventSessionConnected, safeID(sid), sid, string(session.Type), "Authenticated via PAKE + key-confirmation")
			daemon.BroadcastSecurityNotice(fmt.Sprintf("Remote rider authenticated for Session %s via %s", safeID(sid), session.Type))

			defer func() {
				_ = auditLogger.Log(audit.EventSessionDisconnected, safeID(sid), sid, string(session.Type), "Session closed cleanly")
				daemon.BroadcastSecurityNotice(fmt.Sprintf("Rider disconnected from Session %s", safeID(sid)))
			}()

			fmt.Printf("✔ Connected to rider via %s\n", session.Type)

			for {
				stream, err := session.AcceptStream()
				if err != nil {
					break
				}

				go func(st net.Conn) {
					typeBuf := make([]byte, 1)
					if _, err := io.ReadFull(st, typeBuf); err != nil {
						_ = st.Close()
						return
					}

					switch typeBuf[0] {
					case tunnel.StreamTypeSSH:
						_ = sshSrv.PushStream(st)
					case tunnel.StreamTypePTY:
						_ = ptySess.Attach(st)
					case tunnel.StreamTypeDirect:
						_ = tunnel.HandleDirectStream(st)
					case tunnel.StreamTypeChat:
						chatIn, chatOut := io.Pipe()
						go func() {
							_ = chat.RunChat(st, "Host", safeID(sid), chatIn, os.Stderr)
							_ = chatOut.Close()
						}()
					default:
						_ = st.Close()
					}
				}(stream)
			}
			fmt.Printf("[-] Rider disconnected (Session: %s)\n", safeID(sid))
		}(sessionID)
	}
}

func runConnect(targetID string) {
	normID, err := id.NormalizeID(targetID)
	if err != nil {
		log.Fatalf("invalid ID: %v", err)
	}

	pin := promptPIN()

	sigClient, err := dialSignaling(flagServer)
	if err != nil {
		log.Fatalf("failed to connect to signaling server %s: %v", flagServer, err)
	}
	defer sigClient.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	fmt.Fprintf(os.Stderr, "⚡ Dialing %s...\n", normID)
	sessionID, err := sigClient.ConnectTarget(ctx, normID)
	if err != nil {
		log.Fatalf("failed to connect to target: %v", err)
	}

	session, err := transport.OrchestrateClient(ctx, sigClient, sessionID, pin, time.Duration(flagP2PTimeout)*time.Second)
	if err != nil {
		log.Fatalf("PAKE Handshake failed: %v", err)
	}
	defer session.Close()

	sigClient.SetTerminationHandler(func(sid, reason string) {
		fmt.Fprintf(os.Stderr, "\n[-] Session terminated by server: %s\n", reason)
		_ = session.Close()
	})

	fmt.Fprintf(os.Stderr, "✔ PAKE Handshake verified (Zero-Knowledge E2EE)\n")
	fmt.Fprintf(os.Stderr, "✔ Connected via %s\n\n", session.Type)

	// Open PTY stream
	stream, err := session.OpenStream(ctx)
	if err != nil {
		log.Fatalf("failed to open terminal stream: %v", err)
	}
	defer stream.Close()

	// Write PTY type header
	if _, err := stream.Write([]byte{tunnel.StreamTypePTY}); err != nil {
		log.Fatalf("stream init failed: %v", err)
	}

	// Put local terminal into Raw mode
	oldState, err := term.MakeRaw(int(os.Stdin.Fd()))
	if err == nil {
		defer func() {
			_ = term.Restore(int(os.Stdin.Fd()), oldState)
		}()
	}

	// Handle window size changes
	sigwinch := make(chan os.Signal, 1)
	signal.Notify(sigwinch, syscall.SIGWINCH)
	go func() {
		for range sigwinch {
			// Window size changes can be sent if needed
		}
	}()

	errCh := make(chan error, 2)
	go func() {
		_, err := io.Copy(stream, os.Stdin)
		errCh <- err
	}()
	go func() {
		_, err := io.Copy(os.Stdout, stream)
		errCh <- err
	}()

	<-errCh
}

func runProxy(targetID string) {
	normID, err := id.NormalizeID(targetID)
	if err != nil {
		log.Fatalf("invalid ID: %v", err)
	}

	pin := promptPIN()

	sigClient, err := dialSignaling(flagServer)
	if err != nil {
		log.Fatalf("signaling dial failed: %v", err)
	}
	defer sigClient.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	sessionID, err := sigClient.ConnectTarget(ctx, normID)
	if err != nil {
		log.Fatalf("connect failed: %v", err)
	}

	session, err := transport.OrchestrateClient(ctx, sigClient, sessionID, pin, time.Duration(flagP2PTimeout)*time.Second)
	if err != nil {
		log.Fatalf("PAKE Handshake failed: %v", err)
	}
	defer session.Close()

	// Open stream for embedded SSH server
	stream, err := session.OpenStream(ctx)
	if err != nil {
		log.Fatalf("failed to open stream: %v", err)
	}
	defer stream.Close()

	// Send SSH channel header
	if _, err := stream.Write([]byte{tunnel.StreamTypeSSH}); err != nil {
		log.Fatalf("failed to write stream header: %v", err)
	}

	// Bridge stdin/stdout with stream
	errCh := make(chan error, 2)
	go func() {
		_, err := io.Copy(stream, os.Stdin)
		errCh <- err
	}()
	go func() {
		_, err := io.Copy(os.Stdout, stream)
		errCh <- err
	}()

	<-errCh
}

func runForward(targetID string) {
	normID, err := id.NormalizeID(targetID)
	if err != nil {
		log.Fatalf("invalid ID: %v", err)
	}

	pin := promptPIN()

	sigClient, err := dialSignaling(flagServer)
	if err != nil {
		log.Fatalf("signaling dial failed: %v", err)
	}
	defer sigClient.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	sessionID, err := sigClient.ConnectTarget(ctx, normID)
	if err != nil {
		log.Fatalf("connect failed: %v", err)
	}

	session, err := transport.OrchestrateClient(ctx, sigClient, sessionID, pin, time.Duration(flagP2PTimeout)*time.Second)
	if err != nil {
		log.Fatalf("PAKE Handshake failed: %v", err)
	}
	defer session.Close()

	fmt.Fprintf(os.Stderr, "✔ Connected to %s via %s\n", normID, session.Type)

	mgr := tunnel.NewTunnelManager(session)
	defer mgr.Close()

	if flagLocalFwd != "" {
		spec, err := tunnel.ParseForwardSpec(flagLocalFwd)
		if err != nil {
			log.Fatalf("invalid forward spec: %v", err)
		}
		ln, err := mgr.StartLocalForward(spec)
		if err != nil {
			log.Fatalf("failed to start local forward: %v", err)
		}
		defer ln.Close()
		fmt.Fprintf(os.Stderr, "✔ Local forward listening on %s -> %s:%d\n", ln.Addr().String(), spec.RemoteHost, spec.RemotePort)
	}

	if flagSocksPort > 0 {
		ln, err := mgr.StartSOCKS5Proxy("127.0.0.1", flagSocksPort)
		if err != nil {
			log.Fatalf("failed to start SOCKS5 proxy: %v", err)
		}
		defer ln.Close()
		fmt.Fprintf(os.Stderr, "✔ SOCKS5 Dynamic Proxy listening on 127.0.0.1:%d\n", flagSocksPort)
	}

	fmt.Fprintf(os.Stderr, "Press Ctrl+C to terminate forwarding.\n")
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, os.Interrupt, syscall.SIGTERM)
	<-sigChan
}

func newChatCmd() *cobra.Command {
	var hostID string
	cmd := &cobra.Command{
		Use:   "chat [target-id]",
		Short: "Start an ephemeral end-to-end encrypted chat session",
		Long: `Start an ephemeral, encrypted peer-to-peer chat session.
If target-id is omitted, starts a chat host and displays a room ID + PIN.
All messages exist solely in memory and are wiped when the session closes.`,
		Args: cobra.MaximumNArgs(1),
		Run: func(cmd *cobra.Command, args []string) {
			if len(args) == 1 {
				runChatClient(args[0])
			} else {
				runChatHost(hostID)
			}
		},
	}
	cmd.Flags().StringVar(&hostID, "id", "", "Custom 9-digit host ID")
	return cmd
}

func runChatClient(targetID string) {
	normID, err := id.NormalizeID(targetID)
	if err != nil {
		log.Fatalf("invalid ID: %v", err)
	}

	pin := promptPIN()

	sigClient, err := dialSignaling(flagServer)
	if err != nil {
		log.Fatalf("signaling dial failed: %v", err)
	}
	defer sigClient.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	fmt.Fprintf(os.Stderr, "⚡ Dialing %s for secure chat...\n", normID)
	sessionID, err := sigClient.ConnectTarget(ctx, normID)
	if err != nil {
		log.Fatalf("connect failed: %v", err)
	}

	session, err := transport.OrchestrateClient(ctx, sigClient, sessionID, pin, time.Duration(flagP2PTimeout)*time.Second)
	if err != nil {
		log.Fatalf("PAKE Handshake failed: %v", err)
	}
	defer session.Close()

	sigClient.SetTerminationHandler(func(sid, reason string) {
		fmt.Fprintf(os.Stderr, "\n%s[-] Session terminated by server: %s%s\n", chat.ColorRed, reason, chat.ColorReset)
		_ = session.Close()
	})

	stream, err := session.OpenStream(ctx)
	if err != nil {
		log.Fatalf("failed to open chat stream: %v", err)
	}
	defer stream.Close()

	if _, err := stream.Write([]byte{tunnel.StreamTypeChat}); err != nil {
		log.Fatalf("failed to write stream header: %v", err)
	}

	_ = chat.RunChat(stream, "Client", normID, os.Stdin, os.Stdout)
}

func runChatHost(hostID string) {
	if hostID == "" {
		ident, err := id.LoadOrCreateIdentity("")
		if err == nil {
			hostID = ident.ID
		} else {
			generated, err := id.GenerateRandomID()
			if err != nil {
				log.Fatalf("failed to generate ID: %v", err)
			}
			hostID = generated
		}
	}
	pin := resolvePIN()
	if pin == "" {
		generatedPIN, err := id.GeneratePIN(6)
		if err != nil {
			log.Fatalf("failed to generate PIN: %v", err)
		}
		pin = generatedPIN
	}

	fmt.Printf("\n🐎⚡ Rakhssh Secure Chat is ready!\n")
	fmt.Printf("   ├── Chat Room ID : %s\n", hostID)
	fmt.Printf("   ├── Secret PIN   : %s\n", pin)
	fmt.Printf("   └── Storage      : Ephemeral (Zero Disk Persistence)\n\n")
	fmt.Println("Waiting for peer to join...")

	sigClient, err := dialSignaling(flagServer)
	if err != nil {
		log.Fatalf("signaling dial failed: %v", err)
	}
	defer sigClient.Close()

	ctx := context.Background()
	if err := sigClient.RegisterHost(ctx, hostID); err != nil {
		log.Fatalf("registration failed: %v", err)
	}

	sessionCh := make(chan string, 1)
	sigClient.SetHandlers(
		func(sessionID string) {
			select {
			case sessionCh <- sessionID:
			default:
			}
		},
		nil, nil, nil, nil,
	)

	sessionID := <-sessionCh
	fmt.Printf("[+] Peer connected (Session: %s), performing Zero-Knowledge PAKE...\n", safeID(sessionID))

	session, err := transport.OrchestrateHost(ctx, sigClient, sessionID, pin, time.Duration(flagP2PTimeout)*time.Second)
	if err != nil {
		log.Fatalf("PAKE Handshake failed: %v", err)
	}
	defer session.Close()

	sigClient.SetTerminationHandler(func(sid, reason string) {
		fmt.Fprintf(os.Stderr, "\n%s[-] Session terminated by server: %s%s\n", chat.ColorRed, reason, chat.ColorReset)
		_ = session.Close()
	})

	stream, err := session.AcceptStream()
	if err != nil {
		log.Fatalf("failed to accept chat stream: %v", err)
	}
	defer stream.Close()

	typeBuf := make([]byte, 1)
	if _, err := io.ReadFull(stream, typeBuf); err != nil {
		log.Fatalf("failed to read stream header: %v", err)
	}

	_ = chat.RunChat(stream, "Host", safeID(sessionID), os.Stdin, os.Stdout)
}
