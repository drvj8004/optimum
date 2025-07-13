//
//  MainViews.swift
//  Optimum
//

import SwiftUI
import AVFoundation

// MARK: ───────────── Journal data

struct JournalEntry: Identifiable, Codable {
    let id   = UUID()
    let date = Date()
    var text: String?
    var audioFile: String?
}

@MainActor
final class JournalStore: ObservableObject {
    @Published private(set) var entries: [JournalEntry] = []

    private let url: URL = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("journals.json")

    init() { load() }

    func add(_ e: JournalEntry) { entries.insert(e, at: 0); save() }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([JournalEntry].self, from: data)
        else { return }
        entries = list
    }
    private func save() {
        if let data = try? JSONEncoder().encode(entries) { try? data.write(to: url) }
    }
}

// MARK: ───────────── Global UI helpers

struct GradientButtonStyle: ButtonStyle {
    var colors: [Color]
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.weight(.semibold))
            .padding(.vertical, 14)
            .frame(maxWidth: min(UIScreen.main.bounds.width * 0.8, 350))
            .background(
                LinearGradient(colors: colors,
                               startPoint: .topLeading,
                               endPoint: .bottomTrailing)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(radius: configuration.isPressed ? 2 : 10)
            )
            .foregroundColor(.white)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

extension View {
    func fontSize(_ size: CGFloat) -> some View {
        self.font(.system(size: size, weight: .bold, design: .rounded))
    }
}

// MARK: ───────────── Background

struct BackgroundView: View {
    @Environment(\.colorScheme) private var scheme
    @AppStorage("wallpaperSelection") private var wp = 0        // 0 = system colour

    var body: some View {
        if wp == 0 {
            Color(scheme == .dark ? .black : .white).ignoresSafeArea()
        } else {
            GeometryReader { g in
                Image("wallpaper\(wp)")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: g.size.width, height: g.size.height)
                    .position(x: g.size.width / 2, y: g.size.height / 2)
                    .ignoresSafeArea()
            }
        }
    }
}

// MARK: ───────────── Animated headline

struct AnimatedGradientText: View {
    let text: String
    @State private var animate = false
    @Environment(\.colorScheme) private var scheme
    @AppStorage("wallpaperSelection") private var wp = 0

    var body: some View {
        Text(text)
            .foregroundColor(.clear)
            .overlay(
                LinearGradient(colors: palette,
                               startPoint: animate ? .leading : .trailing,
                               endPoint:   animate ? .trailing : .leading)
                    .animation(.linear(duration: 5).repeatForever(autoreverses: true),
                               value: animate)
                    .mask(Text(text))
            )
            .shadow(color: scheme == .dark ? .white.opacity(0.3)
                                           : .black.opacity(0.3),
                    radius: 4, x: 0, y: 2)
            .onAppear { animate = true }
    }

    private var palette: [Color] {
        switch wp {
        case 0:  return scheme == .dark
                     ? [.cyan, .mint, .green, .yellow]
                     : [.pink, .purple, .indigo, .blue]
        case 1:  return [.pink, .purple, .blue]
        case 2:  return [.teal, .cyan, .mint, .yellow]
        default: return [.pink, .purple, .blue, .green, .yellow]
        }
    }
}

// MARK: ───────────── Audio recorder

final class AudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var isRecording = false
    private var recorder: AVAudioRecorder?
    var fileURL: URL? { recorder?.url }

    func toggle() { isRecording ? stop() : start() }

    private func start() {
        let outURL = FileManager.default.urls(for: .documentDirectory,
                                              in: .userDomainMask)[0]
            .appendingPathComponent("journal-\(Date().timeIntervalSince1970).m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 12000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        recorder = try? AVAudioRecorder(url: outURL, settings: settings)
        recorder?.record()
        isRecording = true
    }

    private func stop() {
        recorder?.stop()
        isRecording = false
    }
}

// MARK: ───────────── Journal sheet  (includes History button)

struct JournalSheetView: View {
    enum Mode { case text, audio }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: JournalStore
    @State private var mode: Mode = .text
    @State private var text = ""
    @StateObject private var rec = AudioRecorder()
    @State private var showHistory = false

    var body: some View {
        NavigationStack {
            VStack {
                Picker("", selection: $mode) {
                    Label("Write",  systemImage: "square.and.pencil").tag(Mode.text)
                    Label("Audio", systemImage: "mic.fill")        .tag(Mode.audio)
                }
                .pickerStyle(.segmented)
                .padding()

                if mode == .text {
                    ZStack(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("Start typing…")
                                .foregroundColor(.secondary)
                                .padding(12)
                        }
                        TextEditor(text: $text)
                            .padding(4)
                    }
                    .frame(maxHeight: 250)
                    .background(.ultraThinMaterial,
                                in: RoundedRectangle(cornerRadius: 12))
                    .padding()
                } else {
                    VStack(spacing: 16) {
                        Text(rec.isRecording ? "Recording…" : "Tap to Start")
                            .font(.title3)
                        Button(rec.isRecording ? "Stop Recording" : "Start Recording") {
                            rec.toggle()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                }

                Spacer()
            }
            .navigationTitle("Journal")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("History") { showHistory = true }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save(); dismiss() }
                        .disabled(disabled)
                }
            }
            .navigationDestination(isPresented: $showHistory) {
                JournalListView()
            }
        }
    }

    private var disabled: Bool {
        (mode == .text && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        || (mode == .audio && rec.fileURL == nil)
    }

    private func save() {
        var entry = JournalEntry()
        if mode == .text { entry.text = text }
        if mode == .audio, let url = rec.fileURL { entry.audioFile = url.lastPathComponent }
        store.add(entry)
    }
}

// MARK: ───────────── Journal list

struct JournalListView: View {
    @EnvironmentObject private var store: JournalStore

    var body: some View {
        List {
            ForEach(store.entries) { entry in
                if let t = entry.text {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(date(entry.date)).font(.headline)
                        Text(t).lineLimit(3)
                    }
                } else if let f = entry.audioFile {
                    AudioRow(file: f, date: entry.date)
                }
            }
        }
        .navigationTitle("My Journals")
    }

    private func date(_ d: Date) -> String {
        DateFormatter.localizedString(from: d, dateStyle: .medium, timeStyle: .short)
    }

    struct AudioRow: View {
        let file: String
        let date: Date
        @State private var player: AVAudioPlayer?

        var body: some View {
            HStack {
                Label(dateString, systemImage: "waveform.circle")
                Spacer()
                Button {
                    play()
                } label: {
                    Image(systemName: "play.circle").font(.title2)
                }
            }
            .padding(.vertical, 4)
        }

        private var dateString: String {
            DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
        }

        private func play() {
            let url = FileManager.default.urls(for: .documentDirectory,
                                               in: .userDomainMask)[0]
                .appendingPathComponent(file)
            player = try? AVAudioPlayer(contentsOf: url)
            player?.play()
        }
    }
}

// MARK: ───────────── Home

struct HomeView: View {
    @AppStorage("nickname") private var nick = "Friend"
    @State private var showJournal = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                BackgroundView().ignoresSafeArea()

                VStack(spacing: 40) {
                    AnimatedGradientText(
                        text: "Welcome \(nick),\nHow are you feeling today?"
                    )
                    .fontSize(42)
                    .frame(maxWidth: .infinity,
                           maxHeight: geo.size.height * 0.33,
                           alignment: .bottomLeading)
                    .padding(.horizontal, 24)

                    VStack(spacing: 22) {
                        Button("Journal Now") { showJournal = true }
                            .buttonStyle(GradientButtonStyle(colors: [.purple, .pink, .orange]))

                        NavigationLink("Reminders") { RemindersView() }
                            .buttonStyle(GradientButtonStyle(colors: [.blue, .cyan, .mint]))

                        NavigationLink("General")   { GeneralMenuView() }
                            .buttonStyle(GradientButtonStyle(colors: [.teal, .green, .yellow]))
                    }

                    Spacer()
                }
            }
        }
        .sheet(isPresented: $showJournal) { JournalSheetView() }
    }
}

// MARK: ───────────── Reminders

struct RemindersView: View {
    struct Item: Identifiable { let id = UUID(); var title: String; var done = false }
    @State private var items: [Item] = []
    @State private var newTitle = ""

    var body: some View {
        ZStack {
            BackgroundView().ignoresSafeArea()

            VStack {
                HStack {
                    TextField("New reminder", text: $newTitle)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        add()
                    } label: {
                        Image(systemName: "plus.circle.fill").font(.title2)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()

                List {
                    ForEach(items) { item in
                        HStack {
                            Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(item.done ? .green : .secondary)
                                .onTapGesture { toggle(item) }
                            Text(item.title)
                        }
                    }
                    .onDelete(perform: delete)
                }
            }
            .navigationTitle("Reminders")
        }
    }

    private func add() {
        guard !newTitle.isEmpty else { return }
        items.insert(Item(title: newTitle), at: 0)
        newTitle = ""
    }
    private func toggle(_ item: Item) {
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx].done.toggle()
        }
    }
    private func delete(at offsets: IndexSet) { items.remove(atOffsets: offsets) }
}

// MARK: ───────────── General menu & inputs

struct GeneralMenuView: View {
    var body: some View {
        List {
            NavigationLink("Monetary Input") { MonetaryInputView() }
            NavigationLink("Food Input")     { FoodInputView() }
            NavigationLink("Sleep Input")    { SleepInputView() }
        }
        .navigationTitle("General")
        .background(BackgroundView().ignoresSafeArea())
    }
}

struct MonetaryInputView: View {
    @State private var amount = ""
    @State private var note   = ""
    @State private var method = "WeChat"
    private let methods = ["WeChat", "Alipay", "Cash", "Card", "Other"]

    var body: some View {
        Form {
            Section(header: Text("Amount")) {
                TextField("¥0.00", text: $amount)
                    .keyboardType(.decimalPad)
            }
            Section(header: Text("Payment Method")) {
                Picker("Method", selection: $method) {
                    ForEach(methods, id: \.self, content: Text.init)
                }
            }
            Section(header: Text("Note")) {
                TextField("Description (optional)", text: $note)
            }
            Button("Save") { }
                .buttonStyle(GradientButtonStyle(colors: [.purple, .pink]))
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .navigationTitle("Monetary")
        .background(BackgroundView().ignoresSafeArea())
    }
}

struct FoodInputView: View {
    @State private var food     = ""
    @State private var calories = ""

    var body: some View {
        Form {
            Section(header: Text("Food")) {
                TextField("What did you eat?", text: $food)
            }
            Section(header: Text("Calories")) {
                TextField("kcal", text: $calories)
                    .keyboardType(.numberPad)
            }
            Button("Save") { }
                .buttonStyle(GradientButtonStyle(colors: [.green, .yellow]))
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .navigationTitle("Food")
        .background(BackgroundView().ignoresSafeArea())
    }
}

struct SleepInputView: View {
    @State private var hours = 8.0
    var body: some View {
        Form {
            Section(header: Text("Hours Slept")) {
                Stepper(value: $hours, in: 0...24, step: 0.5) {
                    Text("\(hours, specifier: "%.1f") h")
                }
            }
            Button("Save") { }
                .buttonStyle(GradientButtonStyle(colors: [.blue, .indigo]))
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .navigationTitle("Sleep")
        .background(BackgroundView().ignoresSafeArea())
    }
}

// MARK: ───────────── Profile / Settings / Notifications

struct ProfileView: View {
    @AppStorage("nickname") private var nick = "Friend"
    @State private var email = ""
    var body: some View {
        ZStack {
            BackgroundView().ignoresSafeArea()
            NavigationStack {
                Form {
                    Section(header: Text("Personal Details")) {
                        TextField("Nickname", text: $nick)
                        TextField("Email", text: $email)
                            .keyboardType(.emailAddress)
                    }
                }
                .navigationTitle("Your Profile")
            }
        }
    }
}

struct SettingsView: View {
    @AppStorage("wallpaperSelection") private var wp = 0
    var body: some View {
        ZStack {
            BackgroundView().ignoresSafeArea()
            NavigationStack {
                Form {
                    Section(header: Text("Appearance")) {
                        Picker("Background", selection: $wp) {
                            Text("System").tag(0)
                            Text("Wallpaper 1").tag(1)
                            Text("Wallpaper 2").tag(2)
                        }
                    }
                    Section(header: Text("Notifications")) {
                        Toggle("Enable notifications",
                               isOn: .constant(true))
                        .disabled(true)
                    }
                }
                .navigationTitle("Settings")
            }
        }
    }
}

struct NotificationsView: View {
    var body: some View {
        ZStack {
            BackgroundView().ignoresSafeArea()
            Text("Notifications coming soon…")
        }
    }
}

// MARK: ───────────── Root

struct ContentView: View {
    @StateObject private var store = JournalStore()
    var body: some View {
        TabBarView()
            .environmentObject(store)
    }
}

struct TabBarView: View {
    var body: some View {
        NavigationStack {
            TabView {
                HomeView()
                    .tabItem { Label("Home", systemImage: "house.fill") }
                NotificationsView()
                    .tabItem { Label("Alerts", systemImage: "bell.badge.fill") }
                ProfileView()
                    .tabItem { Label("Profile", systemImage: "person.crop.circle.fill") }
                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape.2.fill") }
            }
        }
    }
}
