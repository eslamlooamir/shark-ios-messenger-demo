//
//  ContentView.swift
//  Shark
//
//  Created by amir eslamlou on 2/1/26.
//


import SwiftUI
import Combine

// ============================================================

// ============================================================
private let BASE_HTTP = ""
private let BASE_WS   = ""


// MARK: - Shark  UI/UX Shell — Dark Blue + Glass + Oval Buttons
// Single-file app: UI + REST + WebSocket + Stores (MVP)

struct ContentView: View {
    var body: some View { SharkAppShell() }
}

// MARK: - Theme

enum SharkTheme {
    static let bgTop     = Color(hex: "#050B14")
    static let bgBottom  = Color(hex: "#071426")
    static let card      = Color(hex: "#0B1C2D").opacity(0.85)
    static let stroke    = Color.white.opacity(0.10)
    static let text      = Color(hex: "#EAF1FF")
    static let subtext   = Color(hex: "#9FB3C8")
    static let accent    = Color(hex: "#1E5EFF")
    static let accent2   = Color(hex: "#31A8FF")
    static let danger    = Color(hex: "#FF4D6D")

    static let corner: CGFloat = 22
    static let rowH: CGFloat = 72
}

extension Color {
    init(hex: String) {
        var hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if hex.count == 6 { hex = "FF" + hex }
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a = Double((int >> 24) & 0xFF) / 255
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

// MARK: - Domain Models (UI)

enum ChatKind: String, CaseIterable {
    case direct = "Chat"
    case group = "Group"
    case channel = "Channel"
}

struct ChatPreview: Identifiable, Hashable {
    // IMPORTANT: backend uses Int chatId
    var id: Int
    var kind: ChatKind
    var title: String
    var last: String
    var time: String
    var unread: Int
    var verified: Bool
}

struct MessageItem: Identifiable, Hashable {
    var id: Int
    var mine: Bool
    var text: String
    var time: String
    var status: String
}

enum CallType { case voice, video }
enum CallDirection { case incoming, outgoing, missed }

struct CallLogItem: Identifiable, Hashable {
    var id: Int
    var name: String
    var type: CallType
    var direction: CallDirection
    var time: String
}

// MARK: - API DTOs

struct APIContact: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let username: String
    let verified: Bool
}

struct APIChat: Codable, Identifiable, Hashable {
    let id: Int
    let kind: String   // direct/group/channel
    let title: String
    let last: String
    let time: String
    let unread: Int
    let verified: Bool
}

struct APIMessage: Codable, Identifiable, Hashable {
    let id: Int
    let chat_id: Int
    let mine: Bool
    let text: String
    let time: String
    let status: String
}

struct APICallLog: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let type: String       // voice/video
    let direction: String  // incoming/outgoing/missed
    let time: String
}

struct APISettings: Codable, Hashable {
    var screen_lock: Bool
    var read_receipts: Bool
    var link_preview: Bool
    var safety_alerts: Bool
}

struct CreateChatBody: Codable {
    let kind: String
    let title: String
    let verified: Bool
}

struct CreateMessageBody: Codable {
    let mine: Bool
    let text: String
}

struct CreateCallLogBody: Codable {
    let name: String
    let type: String
    let direction: String
    let time: String
}

struct WSIncoming: Decodable {
    let type: String
    let chat_id: Int
    let id: Int
    let mine: Bool
    let text: String
    let time: String
    let status: String
}

// MARK: - REST Client

final class SharkAPI {
    private let base = URL(string: BASE_HTTP)!

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        try JSONDecoder().decode(T.self, from: data)
    }

    func getContacts(q: String? = nil) async throws -> [APIContact] {
        var url = base.appendingPathComponent("contacts")
        if let q, !q.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            comps.queryItems = [URLQueryItem(name: "q", value: q)]
            url = comps.url!
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        return try decode(data)
    }

    func getChats() async throws -> [APIChat] {
        let url = base.appendingPathComponent("chats")
        let (data, _) = try await URLSession.shared.data(from: url)
        return try decode(data)
    }

    func createChat(kind: String, title: String, verified: Bool) async throws -> APIChat {
        let url = base.appendingPathComponent("chats")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(CreateChatBody(kind: kind, title: title, verified: verified))
        let (data, _) = try await URLSession.shared.data(for: req)
        return try decode(data)
    }

    func getMessages(chatId: Int) async throws -> [APIMessage] {
        let url = base.appendingPathComponent("chats/\(chatId)/messages")
        let (data, _) = try await URLSession.shared.data(from: url)
        return try decode(data)
    }

    func sendMessage(chatId: Int, text: String, mine: Bool) async throws -> APIMessage {
        let url = base.appendingPathComponent("chats/\(chatId)/messages")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(CreateMessageBody(mine: mine, text: text))
        let (data, _) = try await URLSession.shared.data(for: req)
        return try decode(data)
    }

    func getCallLogs() async throws -> [APICallLog] {
        let url = base.appendingPathComponent("calls/logs")
        let (data, _) = try await URLSession.shared.data(from: url)
        return try decode(data)
    }

    func addCallLog(_ body: CreateCallLogBody) async throws -> APICallLog {
        let url = base.appendingPathComponent("calls/logs")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        let (data, _) = try await URLSession.shared.data(for: req)
        return try decode(data)
    }

    func getSettings() async throws -> APISettings {
        let url = base.appendingPathComponent("settings")
        let (data, _) = try await URLSession.shared.data(from: url)
        return try decode(data)
    }

    func updateSettings(_ s: APISettings) async throws -> APISettings {
        let url = base.appendingPathComponent("settings")
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(s)
        let (data, _) = try await URLSession.shared.data(for: req)
        return try decode(data)
    }
}

// MARK: - WebSocket (singleton, broadcasts incoming messages to stores)

@MainActor
final class SharkWS: ObservableObject {
    static let shared = SharkWS()
    private var task: URLSessionWebSocketTask?
    @Published var lastIncoming: WSIncoming?

    func connect() {
        guard task == nil else { return }
        let url = URL(string: BASE_WS)!
        task = URLSession.shared.webSocketTask(with: url)
        task?.resume()
        listen()

        // Keep-alive ping
        Task { [weak self] in
            while let self, self.task != nil {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                self.sendKeepAlive()
            }
        }
    }

    func disconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    private func sendKeepAlive() {
        task?.send(.string("ping")) { _ in }
    }

    private func listen() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure:
                break
            case .success(let msg):
                if case .string(let text) = msg,
                   let data = text.data(using: .utf8),
                   let decoded = try? JSONDecoder().decode(WSIncoming.self, from: data),
                   decoded.type == "message" {
                    Task { @MainActor in
                        self.lastIncoming = decoded
                    }
                }
            }
            self.listen()
        }
    }
}

// MARK: - Stores (backend-driven)

@MainActor
final class CryptoServicePlaceholder: ObservableObject {
    func isEndToEndEnabled() -> Bool { true }
}

@MainActor
final class ContactsStore: ObservableObject {
    @Published var contacts: [APIContact] = []
    private let api = SharkAPI()

    func load(q: String? = nil) async {
        do { contacts = try await api.getContacts(q: q) } catch { contacts = [] }
    }
}

@MainActor
final class MessagingStore: ObservableObject {
    @Published var chats: [ChatPreview] = []
    private let api = SharkAPI()
    private var cancellables = Set<AnyCancellable>()

    init() {
        SharkWS.shared.$lastIncoming
            .compactMap { $0 }
            .sink { [weak self] inc in
                self?.applyIncoming(inc)
            }
            .store(in: &cancellables)
    }

    func start() {
        SharkWS.shared.connect()
    }

    func refreshChats() async {
        do {
            let apiChats = try await api.getChats()
            chats = apiChats.map { c in
                ChatPreview(
                    id: c.id,
                    kind: Self.kindFromAPI(c.kind),
                    title: c.title,
                    last: c.last,
                    time: c.time,
                    unread: c.unread,
                    verified: c.verified
                )
            }
        } catch {
            chats = []
        }
    }

    func createDirect(from contact: APIContact) async {
        do {
            _ = try await api.createChat(kind: "direct", title: contact.name, verified: contact.verified)
            await refreshChats()
        } catch {}
    }

    func create(kind: ChatKind, title: String) async {
        let apiKind: String = {
            switch kind {
            case .direct: return "direct"
            case .group: return "group"
            case .channel: return "channel"
            }
        }()
        do {
            _ = try await api.createChat(kind: apiKind, title: title, verified: false)
            await refreshChats()
        } catch {}
    }

    private func applyIncoming(_ inc: WSIncoming) {
        // Update chat preview when any message comes in
        if let idx = chats.firstIndex(where: { $0.id == inc.chat_id }) {
            chats[idx].last = inc.text
            chats[idx].time = inc.time
            // simple unread bump if incoming not mine
            if !inc.mine { chats[idx].unread = max(chats[idx].unread + 1, 1) }
        }
    }

    private static func kindFromAPI(_ k: String) -> ChatKind {
        switch k.lowercased() {
        case "group": return .group
        case "channel": return .channel
        default: return .direct
        }
    }
}

@MainActor
final class ChatDetailStore: ObservableObject {
    @Published var messages: [MessageItem] = []
    private let api = SharkAPI()
    private let chatId: Int
    private var cancellables = Set<AnyCancellable>()

    init(chatId: Int) {
        self.chatId = chatId

        SharkWS.shared.$lastIncoming
            .compactMap { $0 }
            .sink { [weak self] inc in
                guard let self else { return }
                guard inc.chat_id == self.chatId else { return }
                // append if not exists
                if !self.messages.contains(where: { $0.id == inc.id }) {
                    self.messages.append(
                        MessageItem(id: inc.id, mine: inc.mine, text: inc.text, time: inc.time, status: inc.status)
                    )
                }
            }
            .store(in: &cancellables)
    }

    func load() async {
        do {
            let apiMsgs = try await api.getMessages(chatId: chatId)
            messages = apiMsgs.map { m in
                MessageItem(id: m.id, mine: m.mine, text: m.text, time: m.time, status: m.status)
            }
        } catch {
            messages = []
        }
    }

    func send(text: String) async {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        do {
            _ = try await api.sendMessage(chatId: chatId, text: t, mine: true)
            // message will also arrive via WS; but for snappiness, we can reload or wait
        } catch {}
    }
}

@MainActor
final class CallsStore: ObservableObject {
    @Published var logs: [CallLogItem] = []
    private let api = SharkAPI()

    func refresh() async {
        do {
            let rows = try await api.getCallLogs()
            logs = rows.map { r in
                CallLogItem(
                    id: r.id,
                    name: r.name,
                    type: (r.type == "video" ? .video : .voice),
                    direction: {
                        switch r.direction {
                        case "incoming": return .incoming
                        case "outgoing": return .outgoing
                        default: return .missed
                        }
                    }(),
                    time: r.time
                )
            }
        } catch {
            logs = []
        }
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published var screenLock = true
    @Published var readReceipts = true
    @Published var linkPreview = false
    @Published var safetyAlerts = true

    private let api = SharkAPI()

    func load() async {
        do {
            let s = try await api.getSettings()
            screenLock = s.screen_lock
            readReceipts = s.read_receipts
            linkPreview = s.link_preview
            safetyAlerts = s.safety_alerts
        } catch {}
    }

    func save() async {
        do {
            let updated = try await api.updateSettings(
                APISettings(
                    screen_lock: screenLock,
                    read_receipts: readReceipts,
                    link_preview: linkPreview,
                    safety_alerts: safetyAlerts
                )
            )
            screenLock = updated.screen_lock
            readReceipts = updated.read_receipts
            linkPreview = updated.link_preview
            safetyAlerts = updated.safety_alerts
        } catch {}
    }
}

// MARK: - App Shell (Tabs: Calls / Chats / Settings) — RTL visual order: Settings | Chats | Calls

struct SharkAppShell: View {
    @StateObject private var crypto = CryptoServicePlaceholder()
    @StateObject private var messaging = MessagingStore()
    @StateObject private var calls = CallsStore()
    @StateObject private var settings = SettingsStore()

    @State private var tab: Int = 1 // default Chats

    var body: some View {
        ZStack {
            SharkBackground()

            TabView(selection: $tab) {

                // LEFT (RTL): Calls
                CallsHomeView()
                    .environmentObject(crypto)
                    .environmentObject(calls)
                    .tag(2)
                    .tabItem { Label("Calls", systemImage: "phone.fill") }

                // MIDDLE: Chats
                ChatsHomeView()
                    .environmentObject(crypto)
                    .environmentObject(messaging)
                    .tag(1)
                    .tabItem { Label("Chats", systemImage: "bubble.left.and.bubble.right.fill") }

                // RIGHT (RTL): Settings
                SettingsView()
                    .environmentObject(crypto)
                    .environmentObject(settings)
                    .tag(0)
                    .tabItem { Label("Settings", systemImage: "gearshape.fill") }
            }
            .tint(SharkTheme.accent)
        }
        .task {
            messaging.start()
            await messaging.refreshChats()
            await calls.refresh()
            await settings.load()
        }
    }
}

// MARK: - Background

struct SharkBackground: View {
    var body: some View {
        LinearGradient(
            colors: [SharkTheme.bgTop, SharkTheme.bgBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            RadialGradient(colors: [
                SharkTheme.accent.opacity(0.20),
                .clear
            ], center: .topTrailing, startRadius: 40, endRadius: 420)
        )
        .overlay(
            RadialGradient(colors: [
                SharkTheme.accent2.opacity(0.14),
                .clear
            ], center: .bottomLeading, startRadius: 20, endRadius: 480)
        )
        .ignoresSafeArea()
    }
}

// MARK: - Reusable Glass Components

struct GlassCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder _ content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: SharkTheme.corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SharkTheme.corner, style: .continuous)
                    .stroke(SharkTheme.stroke, lineWidth: 1)
            )
    }
}

struct GlassPillButton: View {
    var title: String
    var systemImage: String
    var tint: Color = SharkTheme.accent
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(SharkTheme.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(SharkTheme.stroke, lineWidth: 1))
            .shadow(color: tint.opacity(0.25), radius: 12, x: 0, y: 8)
        }
    }
}

struct OvalIconButton: View {
    var system: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SharkTheme.text)
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(SharkTheme.stroke, lineWidth: 1))
        }
    }
}

struct VerifiedBadge: View {
    var body: some View {
        Image(systemName: "checkmark.seal.fill")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(SharkTheme.accent2)
    }
}

struct Avatar: View {
    var name: String
    var size: CGFloat = 44
    var body: some View {
        let initials = name.split(separator: " ").prefix(2).map { String($0.prefix(1)) }.joined().uppercased()
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(Circle().stroke(SharkTheme.stroke, lineWidth: 1))
            Text(initials.isEmpty ? "S" : initials)
                .font(.system(size: size * 0.33, weight: .bold))
                .foregroundStyle(SharkTheme.text)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - ENCRYPTION Banner

struct EncryptionBanner: View {
    var title: String = "End-to-end encrypted"
    var subtitle: String = "Messages & calls are protected."
    var body: some View {
        GlassCard {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(SharkTheme.accent.opacity(0.18))
                        .frame(width: 34, height: 34)
                    Image(systemName: "lock.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SharkTheme.accent2)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SharkTheme.text)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(SharkTheme.subtext)
                }
                Spacer()
            }
        }
    }
}

// MARK: - Chats Tab

struct ChatsHomeView: View {
    @EnvironmentObject var crypto: CryptoServicePlaceholder
    @EnvironmentObject var messaging: MessagingStore

    @State private var search: String = ""
    @State private var showContacts: Bool = false
    @State private var showCreator: Bool = false

    var filtered: [ChatPreview] {
        let s = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return messaging.chats }
        return messaging.chats.filter { $0.title.localizedCaseInsensitiveContains(s) || $0.last.localizedCaseInsensitiveContains(s) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SharkBackground()

                VStack(spacing: 12) {
                    if crypto.isEndToEndEnabled() {
                        EncryptionBanner(subtitle: "Shark protects your chats & calls.")
                            .padding(.horizontal, 16)
                            .padding(.top, 10)
                    }

                    GlassSearchBar(text: $search, placeholder: "Search")
                        .padding(.horizontal, 16)

                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(filtered) { chat in
                                NavigationLink {
                                    ChatDetailView(chat: chat)
                                } label: {
                                    ChatRow(chat: chat)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                }
            }
            .navigationTitle("Shark")
            .toolbar {
                // New Chat (top)
                ToolbarItem(placement: .topBarTrailing) {
                    OvalIconButton(system: "square.and.pencil") {
                        showContacts = true
                    }
                }
                ToolbarItem(placement: .topBarTrailing) { OvalIconButton(system: "camera.fill") {} }
                ToolbarItem(placement: .topBarTrailing) { OvalIconButton(system: "qrcode") {} }
            }
            .sheet(isPresented: $showContacts) {
                ContactsPickerView(
                    onPick: { contact in
                        Task {
                            await messaging.createDirect(from: contact)
                            showContacts = false
                        }
                    },
                    onCreateGroup: {
                        showContacts = false
                        showCreator = true
                    },
                    onCreateChannel: {
                        showContacts = false
                        showCreator = true
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(24)
            }
            .sheet(isPresented: $showCreator) {
                NewChatCreatorSheet { kind, title in
                    Task { await messaging.create(kind: kind, title: title) }
                }
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(24)
            }
            .refreshable { await messaging.refreshChats() }
        }
    }
}

struct ChatRow: View {
    let chat: ChatPreview

    var body: some View {
        GlassCard {
            HStack(spacing: 12) {
                Avatar(name: chat.title)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(chat.title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(SharkTheme.text)

                        if chat.verified { VerifiedBadge() }

                        Spacer()

                        Text(chat.time)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(SharkTheme.subtext)
                    }

                    HStack(spacing: 10) {
                        Text(chat.kind.rawValue)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(SharkTheme.accent2)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(SharkTheme.accent.opacity(0.14), in: Capsule())

                        Text(chat.last)
                            .font(.system(size: 13))
                            .foregroundStyle(SharkTheme.subtext)
                            .lineLimit(1)

                        Spacer()

                        if chat.unread > 0 {
                            Text("\(chat.unread)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(SharkTheme.accent, in: Capsule())
                        }
                    }
                }
            }
        }
    }
}

struct GlassSearchBar: View {
    @Binding var text: String
    var placeholder: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(SharkTheme.subtext)
            TextField(placeholder, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(SharkTheme.text)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(SharkTheme.subtext)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(SharkTheme.stroke, lineWidth: 1))
    }
}

// MARK: - Contacts Picker (from backend)

struct ContactsPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = ContactsStore()
    @State private var search: String = ""

    var onPick: (APIContact) -> Void
    var onCreateGroup: () -> Void
    var onCreateChannel: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                SharkBackground()

                VStack(spacing: 12) {
                    GlassSearchBar(text: $search, placeholder: "Search contacts")
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .onChange(of: search) { _, new in
                            Task { await store.load(q: new) }
                        }

                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(store.contacts) { c in
                                Button {
                                    onPick(c)
                                    dismiss()
                                } label: {
                                    GlassCard {
                                        HStack(spacing: 12) {
                                            Avatar(name: c.name)
                                            VStack(alignment: .leading, spacing: 4) {
                                                HStack(spacing: 6) {
                                                    Text(c.name)
                                                        .font(.system(size: 15, weight: .semibold))
                                                        .foregroundStyle(SharkTheme.text)
                                                    if c.verified { VerifiedBadge() }
                                                }
                                                Text(c.username)
                                                    .font(.system(size: 12))
                                                    .foregroundStyle(SharkTheme.subtext)
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .foregroundStyle(SharkTheme.subtext)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                }
            }
            .navigationTitle("New Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    OvalIconButton(system: "xmark") { dismiss() }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            dismiss()
                            onCreateGroup()
                        } label: { Label("New Group", systemImage: "person.3.fill") }

                        Button {
                            dismiss()
                            onCreateChannel()
                        } label: { Label("New Channel", systemImage: "megaphone.fill") }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(SharkTheme.accent2)
                    }
                }
            }
            .task { await store.load(q: nil) }
        }
    }
}

// MARK: - Creator Sheet (Group/Channel)

struct NewChatCreatorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var kind: ChatKind = .group
    @State private var title: String = ""

    var onCreate: (ChatKind, String) -> Void

    var body: some View {
        ZStack {
            SharkBackground()

            VStack(spacing: 14) {
                Capsule()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 46, height: 5)
                    .padding(.top, 10)

                Text("New")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(SharkTheme.text)

                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Type", selection: $kind) {
                            Text("Group").tag(ChatKind.group)
                            Text("Channel").tag(ChatKind.channel)
                        }
                        .pickerStyle(.segmented)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Title")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(SharkTheme.subtext)
                            TextField(kind == .channel ? "e.g. Shark Updates" : "e.g. Shark Team", text: $title)
                                .foregroundStyle(SharkTheme.text)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 12)
                                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(SharkTheme.stroke, lineWidth: 1))
                        }
                    }
                }
                .padding(.horizontal, 16)

                HStack(spacing: 10) {
                    GlassPillButton(title: "Cancel", systemImage: "xmark") { dismiss() }

                    GlassPillButton(title: "Create", systemImage: "checkmark.circle.fill", tint: SharkTheme.accent) {
                        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !t.isEmpty else { return }
                        onCreate(kind, t)
                        dismiss()
                    }
                }
                .padding(.horizontal, 16)

                Spacer()
            }
        }
    }
}

// MARK: - Chat Detail (history + send REST + receive WS)

struct ChatDetailView: View {
    let chat: ChatPreview
    @StateObject private var store: ChatDetailStore

    @State private var messageText: String = ""
    @State private var showActions: Bool = false

    init(chat: ChatPreview) {
        self.chat = chat
        _store = StateObject(wrappedValue: ChatDetailStore(chatId: chat.id))
    }

    var body: some View {
        ZStack {
            SharkBackground()

            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            EncryptionBanner(subtitle: "This \(chat.kind.rawValue.lowercased()) is protected by E2EE (UI demo).")
                                .padding(.bottom, 2)

                            ForEach(store.messages) { m in
                                BubbleRow(item: m).id(m.id)
                            }

                            Color.clear.frame(height: 10).id("BOTTOM")
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                    .onAppear {
                        Task {
                            await store.load()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("BOTTOM", anchor: .bottom) }
                            }
                        }
                    }
                    .onChange(of: store.messages.count) { _, _ in
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("BOTTOM", anchor: .bottom) }
                    }
                }

                Divider().opacity(0.35)

                if showActions {
                    QuickActionsRow()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.horizontal, 14)
                        .padding(.top, 10)
                }

                composer
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            }
        }
        .navigationTitle(chat.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { OvalIconButton(system: "phone.fill") {} }
            ToolbarItem(placement: .topBarTrailing) { OvalIconButton(system: "video.fill") {} }
        }
    }

    private var composer: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) { showActions.toggle() }
            } label: {
                Image(systemName: showActions ? "xmark.circle.fill" : "plus.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(SharkTheme.accent2)
            }

            ZStack(alignment: .leading) {
                if messageText.isEmpty {
                    Text("Message")
                        .foregroundStyle(SharkTheme.subtext)
                        .padding(.leading, 14)
                }
                TextField("", text: $messageText, axis: .vertical)
                    .lineLimit(1...5)
                    .foregroundStyle(SharkTheme.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: SharkTheme.corner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: SharkTheme.corner, style: .continuous).stroke(SharkTheme.stroke, lineWidth: 1))

            Button {
                let t = messageText
                messageText = ""
                Task { await store.send(text: t) }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(canSend ? SharkTheme.accent2 : SharkTheme.subtext)
            }
            .disabled(!canSend)
        }
    }

    private var canSend: Bool {
        !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct BubbleRow: View {
    let item: MessageItem

    var body: some View {
        let bubbleShape = RoundedRectangle(cornerRadius: SharkTheme.corner, style: .continuous)

        HStack {
            if item.mine { Spacer(minLength: 44) }

            VStack(alignment: .leading, spacing: 6) {
                Text(item.text)
                    .font(.system(size: 16))
                    .foregroundStyle(item.mine ? Color.white : SharkTheme.text)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    Text(item.time)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(item.mine ? Color.white.opacity(0.80) : SharkTheme.subtext)

                    if item.mine {
                        Text("• \(item.status)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.80))
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                bubbleShape.fill(
                    item.mine
                    ? AnyShapeStyle(LinearGradient(colors: [SharkTheme.accent, SharkTheme.accent2],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing))
                    : AnyShapeStyle(.ultraThinMaterial)
                )
            }
            .overlay { bubbleShape.stroke(item.mine ? Color.white.opacity(0.0) : SharkTheme.stroke, lineWidth: 1) }
            .shadow(color: SharkTheme.accent.opacity(item.mine ? 0.30 : 0.08), radius: 14, x: 0, y: 10)
            .frame(maxWidth: 320, alignment: item.mine ? .trailing : .leading)

            if !item.mine { Spacer(minLength: 44) }
        }
        .padding(.vertical, 2)
    }
}

struct QuickActionsRow: View {
    var body: some View {
        GlassCard {
            HStack(spacing: 12) {
                QuickAction(icon: "photo.fill", title: "Photo")
                QuickAction(icon: "video.fill", title: "Video")
                QuickAction(icon: "mic.fill", title: "Voice")
                QuickAction(icon: "doc.fill", title: "File")
            }
        }
    }
}

struct QuickAction: View {
    var icon: String
    var title: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(SharkTheme.accent2)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SharkTheme.text)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(SharkTheme.stroke, lineWidth: 1))
    }
}

// MARK: - Calls Tab (backend logs)

struct CallsHomeView: View {
    @EnvironmentObject var crypto: CryptoServicePlaceholder
    @EnvironmentObject var calls: CallsStore

    var body: some View {
        NavigationStack {
            ZStack {
                SharkBackground()

                VStack(spacing: 12) {
                    EncryptionBanner(subtitle: "Calls are designed for E2EE (logs are backend).")
                        .padding(.horizontal, 16)
                        .padding(.top, 10)

                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(calls.logs) { log in
                                CallRow(log: log)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                }
            }
            .navigationTitle("Calls")
            .refreshable { await calls.refresh() }
        }
    }
}

struct CallRow: View {
    var log: CallLogItem

    var icon: String {
        switch (log.type, log.direction) {
        case (.voice, .incoming): return "phone.arrow.down.left"
        case (.voice, .outgoing): return "phone.arrow.up.right"
        case (.voice, .missed): return "phone.badge.exclamationmark"
        case (.video, .incoming): return "video.badge.ellipsis"
        case (.video, .outgoing): return "video.fill"
        case (.video, .missed): return "video.badge.exclamationmark"
        }
    }

    var color: Color {
        log.direction == .missed ? SharkTheme.danger : SharkTheme.accent2
    }

    var body: some View {
        GlassCard {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(color.opacity(0.16)).frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(color)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(log.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SharkTheme.text)
                    Text(log.time)
                        .font(.system(size: 12))
                        .foregroundStyle(SharkTheme.subtext)
                }
                Spacer()
                Image(systemName: log.type == .voice ? "phone.fill" : "video.fill")
                    .foregroundStyle(SharkTheme.subtext)
            }
        }
    }
}

// MARK: - Settings Tab (backend GET/PUT)

struct SettingsView: View {
    @EnvironmentObject var crypto: CryptoServicePlaceholder
    @EnvironmentObject var store: SettingsStore

    var body: some View {
        NavigationStack {
            ZStack {
                SharkBackground()

                ScrollView {
                    VStack(spacing: 12) {
                        GlassCard {
                            HStack(spacing: 12) {
                                Avatar(name: "Shark")
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Shark")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(SharkTheme.text)
                                    Text("Privacy & Speed • Dark Blue")
                                        .font(.system(size: 12))
                                        .foregroundStyle(SharkTheme.subtext)
                                }
                                Spacer()
                                VerifiedBadge()
                            }
                        }

                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Image(systemName: "lock.fill").foregroundStyle(SharkTheme.accent2)
                                    Text("Privacy")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(SharkTheme.text)
                                    Spacer()
                                }

                                ToggleRow(title: "Screen Lock", subtitle: "FaceID / Passcode", isOn: $store.screenLock)
                                ToggleRow(title: "Read Receipts", subtitle: "On/Off", isOn: $store.readReceipts)
                                ToggleRow(title: "Link Previews", subtitle: "Disable for privacy", isOn: $store.linkPreview)
                                ToggleRow(title: "Safety Alerts", subtitle: "Security notifications", isOn: $store.safetyAlerts)

                                GlassPillButton(title: "Save", systemImage: "checkmark.circle.fill", tint: SharkTheme.accent) {
                                    Task { await store.save() }
                                }
                            }
                        }

                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Image(systemName: "shield.lefthalf.filled").foregroundStyle(SharkTheme.accent2)
                                    Text("Encryption")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(SharkTheme.text)
                                    Spacer()
                                }

                                HStack {
                                    Text("Status")
                                        .foregroundStyle(SharkTheme.subtext)
                                    Spacer()
                                    Text(crypto.isEndToEndEnabled() ? "E2EE Enabled (UI)" : "Off")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(crypto.isEndToEndEnabled() ? SharkTheme.accent2 : SharkTheme.danger)
                                }

                                Text("Backend MVP: chats, messages, contacts, calls logs, settings. E2EE to add later.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(SharkTheme.subtext)
                            }
                        }

                        Spacer(minLength: 20)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { OvalIconButton(system: "gearshape.fill") {} }
            }
        }
    }
}

struct ToggleRow: View {
    var title: String
    var subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SharkTheme.text)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(SharkTheme.subtext)
            }
            Spacer()
            Toggle("", isOn: $isOn).labelsHidden()
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Preview
#Preview {
    ContentView()
        .preferredColorScheme(.dark)
}


