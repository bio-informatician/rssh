package main

import (
	"context"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/spf13/cobra"
	"golang.org/x/term"

	"rssh/pkg/daemon"
	"rssh/pkg/id"
	"rssh/pkg/pty"
	"rssh/pkg/signaling"
	"rssh/pkg/sshserver"
	"rssh/pkg/transport"
	"rssh/pkg/tunnel"
)

var (
	flagServer     string
	flagPIN        string
	flagLocalFwd   string
	flagSocksPort  int
	flagP2PTimeout int
	flagDebug      bool
)

func getDefaultServer() string {
	if s := os.Getenv("RSSH_SERVER"); s != "" {
		return s
	}
	return "ws://localhost:8443"
}

func main() {
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
	rootCmd.PersistentFlags().IntVar(&flagP2PTimeout, "p2p-timeout", 2, "Seconds to attempt P2P before falling back to relay")
	rootCmd.PersistentFlags().BoolVarP(&flagDebug, "debug", "v", false, "Enable verbose diagnostic tracing")

	// Subcommands
	rootCmd.AddCommand(newHostCmd())
	rootCmd.AddCommand(newConnectCmd())
	rootCmd.AddCommand(newProxyCmd())
	rootCmd.AddCommand(newForwardCmd())
	rootCmd.AddCommand(newDaemonCmd())

	if err := rootCmd.Execute(); err != nil {
		os.Exit(1)
	}
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
			pin := flagPIN
			if pin == "" {
				generatedPIN, err := id.GeneratePIN(4)
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

			cfg, err := daemon.LoadOrCreateConfig("", flagPIN, flagServer)
			if err != nil {
				log.Fatalf("failed to load daemon config: %v", err)
			}
			runHost(cfg.MachineID, cfg.Password, cfg.ServerURL)
		},
	}
	cmd.Flags().BoolVar(&installSystemd, "install-systemd", false, "Generate and install systemd user service")
	return cmd
}

func runHost(hostID, pin, serverURL string) {
	fmt.Printf("\n🐎⚡ Rakhssh is ready!\n")
	fmt.Printf("   ├── Machine ID : %s\n", hostID)
	fmt.Printf("   ├── Secret PIN : %s\n", pin)
	fmt.Printf("   └── Stealth    : Active (WSS/443 + P2P Standby)\n\n")
	fmt.Println("Waiting for rider...")

	sigClient, err := signaling.Dial(serverURL)
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

	// Keep alive loop handling incoming sessions
	for sessionID := range sessionCh {
		fmt.Printf("[+] Incoming rider connection (Session: %s)\n", sessionID[:8])

		go func(sid string) {
			session, err := transport.OrchestrateHost(ctx, sigClient, sid, pin, time.Duration(flagP2PTimeout)*time.Second)
			if err != nil {
				fmt.Printf("[-] Handshake failed for session %s: %v\n", sid[:8], err)
				return
			}
			defer session.Close()

			fmt.Printf("✔ Connected to rider via %s\n", session.Type)

			for {
				stream, err := session.AcceptStream()
				if err != nil {
					break
				}

				go func(st net.Conn) {
					// Read 1-byte channel type
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
						// Handle forwarded port stream
						_ = tunnel.HandleIncomingStream(st)
					default:
						_ = st.Close()
					}
				}(stream)
			}
			fmt.Printf("[-] Rider disconnected (Session: %s)\n", sid[:8])
		}(sessionID)
	}
}

func runConnect(targetID string) {
	normID, err := id.NormalizeID(targetID)
	if err != nil {
		log.Fatalf("invalid ID: %v", err)
	}

	pin := flagPIN
	if pin == "" {
		fmt.Fprint(os.Stderr, "🔑 Enter PIN/Password: ")
		bytePin, err := term.ReadPassword(int(os.Stdin.Fd()))
		fmt.Fprintln(os.Stderr)
		if err != nil {
			log.Fatalf("failed to read password: %v", err)
		}
		pin = strings.TrimSpace(string(bytePin))
	}

	sigClient, err := signaling.Dial(flagServer)
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

	pin := flagPIN
	if pin == "" {
		pin = os.Getenv("RSSH_PIN")
	}
	if pin == "" {
		fmt.Fprint(os.Stderr, "Enter PIN/Password: ")
		bytePin, err := term.ReadPassword(int(os.Stdin.Fd()))
		fmt.Fprintln(os.Stderr)
		if err != nil {
			log.Fatalf("failed to read password: %v", err)
		}
		pin = strings.TrimSpace(string(bytePin))
	}

	sigClient, err := signaling.Dial(flagServer)
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

	pin := flagPIN
	if pin == "" {
		fmt.Fprint(os.Stderr, "🔑 Enter PIN/Password: ")
		bytePin, err := term.ReadPassword(int(os.Stdin.Fd()))
		fmt.Fprintln(os.Stderr)
		if err != nil {
			log.Fatalf("failed to read password: %v", err)
		}
		pin = strings.TrimSpace(string(bytePin))
	}

	sigClient, err := signaling.Dial(flagServer)
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
