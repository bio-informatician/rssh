import Foundation
import SwiftUI
import Combine

/// Model representing a chat message
struct ChatMessage: Identifiable, Codable {
    var id: String = UUID().uuidString
    let type: String
    let sender: String
    let text: String
    var time: String = ""

    enum CodingKeys: String, CodingKey {
        case type, sender, text, time
    }
}

/// ViewModel managing WebSocket lifecycle, state, and messages
class ChatViewModel: NSObject, ObservableObject, URLSessionWebSocketDelegate {
    @Published var messages: [ChatMessage] = []
    @Published var isConnected: Bool = false
    @Published var statusText: String = "قطع اتصال"
    
    @Published var serverUrl: String {
        didSet { UserDefaults.standard.set(serverUrl, forKey: "chat_server_url") }
    }
    @Published var nickname: String {
        didSet { UserDefaults.standard.set(nickname, forKey: "chat_nickname") }
    }
    @Published var roomName: String {
        didSet { UserDefaults.standard.set(roomName, forKey: "chat_room") }
    }
    @Published var autoReconnect: Bool {
        didSet { UserDefaults.standard.set(autoReconnect, forKey: "chat_auto_reconnect") }
    }

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var isUserDisconnected: Bool = false

    override init() {
        self.serverUrl = UserDefaults.standard.string(forKey: "chat_server_url") ?? "ws://192.168.1.100:8765"
        self.nickname = UserDefaults.standard.string(forKey: "chat_nickname") ?? "آیفون من"
        self.roomName = UserDefaults.standard.string(forKey: "chat_room") ?? "general"
        self.autoReconnect = UserDefaults.standard.object(forKey: "chat_auto_reconnect") == nil ? true : UserDefaults.standard.bool(forKey: "chat_auto_reconnect")
        
        super.init()
        let config = URLSessionConfiguration.default
        self.urlSession = URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue())
    }

    func connect() {
        var cleanUrl = serverUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanUrl.hasPrefix("ws://") && !cleanUrl.hasPrefix("wss://") {
            cleanUrl = "ws://" + cleanUrl
        }
        
        guard let url = URL(string: cleanUrl) else {
            DispatchQueue.main.async {
                self.statusText = "آدرس نامعتبر است"
            }
            return
        }

        isUserDisconnected = false
        DispatchQueue.main.async {
            self.statusText = "در حال اتصال..."
        }

        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = urlSession?.webSocketTask(with: url)
        webSocketTask?.resume()

        listenForMessages()
    }

    func disconnect() {
        isUserDisconnected = true
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        DispatchQueue.main.async {
            self.isConnected = false
            self.statusText = "قطع اتصال"
        }
    }

    func sendMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let currentTime = formatter.string(from: Date())

        let outgoing = ChatMessage(
            id: UUID().uuidString,
            type: "chat",
            sender: nickname,
            text: trimmed,
            time: currentTime
        )

        // Show locally
        DispatchQueue.main.async {
            self.messages.append(outgoing)
        }

        // Send JSON frame to server
        if let data = try? JSONEncoder().encode(outgoing),
           let jsonString = String(data: data, encoding: .utf8) {
            let message = URLSessionWebSocketTask.Message.string(jsonString)
            webSocketTask?.send(message) { error in
                if let error = error {
                    print("WebSocket send error: \(error.localizedDescription)")
                }
            }
        }
    }

    private func listenForMessages() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let error):
                print("WebSocket receive error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.isConnected = false
                    self.statusText = "قطع شد"
                    if self.autoReconnect && !self.isUserDisconnected {
                        self.scheduleReconnect()
                    }
                }
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleIncomingText(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleIncomingText(text)
                    }
                @unknown default:
                    break
                }
                self.listenForMessages()
            }
        }
    }

    private func handleIncomingText(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        
        DispatchQueue.main.async {
            if let decoded = try? JSONDecoder().decode(ChatMessage.self, from: data) {
                // Avoid duplicating our own echo if server sends it back
                if decoded.sender != self.nickname {
                    self.messages.append(decoded)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            } else {
                // Fallback for plain text messages
                let fallback = ChatMessage(
                    id: UUID().uuidString,
                    type: "chat",
                    sender: "سرور",
                    text: text,
                    time: ""
                )
                self.messages.append(fallback)
            }
        }
    }

    private func scheduleReconnect() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self = self, !self.isConnected, !self.isUserDisconnected else { return }
            self.connect()
        }
    }

    // MARK: - URLSessionWebSocketDelegate
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        DispatchQueue.main.async {
            self.isConnected = true
            self.statusText = "متصل شد"
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        DispatchQueue.main.async {
            self.isConnected = false
            self.statusText = "قطع شد"
            if self.autoReconnect && !self.isUserDisconnected {
                self.scheduleReconnect()
            }
        }
    }
}
