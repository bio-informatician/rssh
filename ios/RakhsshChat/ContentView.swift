import SwiftUI

struct ContentView: View {
    @StateObject private var vm = ChatViewModel()
    @State private var inputText: String = ""
    @State private var showSettings: Bool = false

    var body: some View {
        ZStack {
            Color(hex: "0B0F19").ignoresSafeArea()

            VStack(spacing: 0) {
                // Header Bar
                headerView

                // Message Stream
                messageListView

                // Input Bar
                footerInputView
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .sheet(isPresented: $showSettings) {
            SettingsSheetView(vm: vm, isPresented: $showSettings)
        }
        .onAppear {
            if !vm.isConnected {
                vm.connect()
            }
        }
    }

    // MARK: - Header
    private var headerView: some View {
        HStack {
            Button(action: { showSettings = true }) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 20))
                    .foregroundColor(Color(hex: "94A3B8"))
                    .frame(width: 38, height: 38)
                    .background(Color(hex: "1F2C45"))
                    .clipShape(Circle())
            }

            Spacer()

            VStack(spacing: 3) {
                Text("رخش چت (Rakhssh)")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color(hex: "F1F5F9"))

                HStack(spacing: 6) {
                    Circle()
                        .fill(vm.isConnected ? Color(hex: "10B981") : Color(hex: "EF4444"))
                        .frame(width: 8, height: 8)
                    Text(vm.statusText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(hex: "94A3B8"))
                }
            }

            Spacer()

            Button(action: { vm.messages.removeAll() }) {
                Image(systemName: "trash")
                    .font(.system(size: 18))
                    .foregroundColor(Color(hex: "94A3B8"))
                    .frame(width: 38, height: 38)
                    .background(Color(hex: "1F2C45"))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(hex: "151D2F"))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(hex: "2A3854")),
            alignment: .bottom
        )
    }

    // MARK: - Messages
    private var messageListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if vm.messages.isEmpty {
                        welcomeHeroView
                    } else {
                        ForEach(vm.messages) { msg in
                            MessageRowView(message: msg, isMe: msg.sender == vm.nickname)
                                .id(msg.id)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 16)
            }
            .onChange(of: vm.messages.count) { _ in
                if let last = vm.messages.last {
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var welcomeHeroView: some View {
        VStack(spacing: 14) {
            Text("💬")
                .font(.system(size: 52))

            Text("کلاینت چت رخش برای iOS")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Color(hex: "F1F5F9"))

            Text("برای شروع گفتگو، آدرس سرور چت را در تنظیمات وارد کرده و دکمه اتصال را بزنید.")
                .font(.system(size: 13))
                .foregroundColor(Color(hex: "94A3B8"))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            Button(action: { showSettings = true }) {
                Text("تنظیم آدرس سرور")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(Color(hex: "0284C7"))
                    .cornerRadius(20)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(hex: "151D2F").opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color(hex: "2A3854"), lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
        .padding(.top, 40)
    }

    // MARK: - Footer Input
    private var footerInputView: some View {
        HStack(spacing: 10) {
            TextField("پیام خود را بنویسید...", text: $inputText)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(Color(hex: "1F2C45"))
                .foregroundColor(Color(hex: "F1F5F9"))
                .cornerRadius(22)
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(Color(hex: "2A3854"), lineWidth: 1)
                )
                .environment(\.layoutDirection, .rightToLeft)
                .onSubmit {
                    sendMessage()
                }

            Button(action: sendMessage) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(
                        inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? Color(hex: "1F2C45")
                            : Color(hex: "0284C7")
                    )
                    .clipShape(Circle())
            }
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(hex: "151D2F"))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(hex: "2A3854")),
            alignment: .top
        )
    }

    private func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        vm.sendMessage(trimmed)
        inputText = ""
    }
}

// MARK: - Message Row
struct MessageRowView: View {
    let message: ChatMessage
    let isMe: Bool

    var body: some View {
        HStack {
            if isMe {
                Spacer(minLength: 40)
            }

            VStack(alignment: isMe ? .trailing : .leading, spacing: 4) {
                if !isMe && !message.sender.isEmpty {
                    Text(message.sender)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: "38BDF8"))
                }

                Text(message.text)
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "F1F5F9"))
                    .multilineTextAlignment(isMe ? .trailing : .leading)

                if !message.time.isEmpty {
                    Text(message.time)
                        .font(.system(size: 9))
                        .foregroundColor(Color(hex: "94A3B8"))
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(isMe ? Color(hex: "0284C7") : Color(hex: "1E293B"))
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isMe ? Color.clear : Color(hex: "2A3854"), lineWidth: 1)
            )

            if !isMe {
                Spacer(minLength: 40)
            }
        }
    }
}

// MARK: - Settings Sheet
struct SettingsSheetView: View {
    @ObservedObject var vm: ChatViewModel
    @Binding var isPresented: Bool

    var body: some View {
        ZStack {
            Color(hex: "0B0F19").ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                // Sheet Header
                HStack {
                    Text("تنظیمات اتصال سرور")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)

                    Spacer()

                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(Color(hex: "94A3B8"))
                    }
                }
                .padding(.bottom, 6)

                // Server URL Field
                VStack(alignment: .leading, spacing: 6) {
                    Text("آدرس سرور چت (WebSocket):")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(hex: "94A3B8"))

                    TextField("ws://192.168.1.100:8765", text: $vm.serverUrl)
                        .padding(12)
                        .background(Color(hex: "151D2F"))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: "2A3854"), lineWidth: 1))
                        .environment(\.layoutDirection, .leftToRight)

                    // Quick Presets
                    HStack(spacing: 8) {
                        PresetBadge(title: "Localhost", url: "ws://127.0.0.1:8765", target: $vm.serverUrl)
                        PresetBadge(title: "LAN IP", url: "ws://192.168.1.100:8765", target: $vm.serverUrl)
                        PresetBadge(title: "Echo Test", url: "ws://echo.websocket.events", target: $vm.serverUrl)
                    }
                    .padding(.top, 4)
                }

                // Nickname Field
                VStack(alignment: .leading, spacing: 6) {
                    Text("نام مستعار:")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(hex: "94A3B8"))

                    TextField("آیفون من", text: $vm.nickname)
                        .padding(12)
                        .background(Color(hex: "151D2F"))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: "2A3854"), lineWidth: 1))
                }

                // Room Field
                VStack(alignment: .leading, spacing: 6) {
                    Text("اتاق / Room:")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(hex: "94A3B8"))

                    TextField("general", text: $vm.roomName)
                        .padding(12)
                        .background(Color(hex: "151D2F"))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: "2A3854"), lineWidth: 1))
                        .environment(\.layoutDirection, .leftToRight)
                }

                // Auto Reconnect Toggle
                Toggle(isOn: $vm.autoReconnect) {
                    Text("اتصال مجدد خودکار در صورت قطعی")
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                }
                .tint(Color(hex: "0284C7"))
                .padding(.vertical, 4)

                Spacer()

                // Actions
                HStack(spacing: 12) {
                    Button(action: {
                        vm.connect()
                        isPresented = false
                    }) {
                        Text("اتصال به سرور")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(hex: "0284C7"))
                            .cornerRadius(12)
                    }

                    Button(action: {
                        vm.disconnect()
                        isPresented = false
                    }) {
                        Text("قطع اتصال")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Color(hex: "EF4444"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(hex: "1F2C45"))
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "EF4444"), lineWidth: 1))
                    }
                }
            }
            .padding(20)
        }
        .environment(\.layoutDirection, .rightToLeft)
    }
}

struct PresetBadge: View {
    let title: String
    let url: String
    @Binding var target: String

    var body: some View {
        Button(action: { target = url }) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(hex: "38BDF8"))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(hex: "1F2C45"))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(hex: "2A3854"), lineWidth: 1))
        }
    }
}

// MARK: - Color Hex Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
