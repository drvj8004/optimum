//
//  MainViews.swift   ▸ Optimum
//  Drop this SINGLE file into a new Xcode-15 iOS-16+ project
//  ──────────────────────────────────────────────────────────
//  · FoodDashboard   — camera → LogMeal API  → calorie chart & history
//  · MoneyDashboard  — manual spending tracker & chart
//  · Journal sheet   — text or audio, stored locally
//  · JSONStore       — generic on-disk persistence (per model)
//

import SwiftUI
import AVFoundation
import Charts

// ──────────────────────────────────────────────────────────
// MARK: LogMeal credentials (free tier)
// ──────────────────────────────────────────────────────────
fileprivate let LOGMEAL_USER_KEY = "47756"          // ← your API-User ID
fileprivate let LOGMEAL_TOKEN    = "959f25d8473a76052b484df8c1da43588cf17ade"

// ──────────────────────────────────────────────────────────
// MARK: Generic local JSON store
// ──────────────────────────────────────────────────────────
protocol Storable: Identifiable, Codable { var date: Date { get } }

@MainActor
final class JSONStore<T: Storable>: ObservableObject {
    @Published private(set) var items: [T] = []
    private let url: URL

    init(_ filename: String) {
        url = FileManager.default.urls(for: .documentDirectory,
                                       in: .userDomainMask)[0]
              .appendingPathComponent(filename)
        load()
    }

    func add(_ item: T) {
        items.insert(item, at: 0)
        save()
    }
    func update(_ item: T) {
        if let ix = items.firstIndex(where: { $0.id == item.id }) {
            items[ix] = item; save()
        }
    }
    func remove(at ix: IndexSet)          { items.remove(atOffsets: ix); save() }
    func remove(_ item: T)                { items.removeAll{ $0.id == item.id }; save() }

    private func load() {
        guard let d = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([T].self, from: d) else { return }
        items = list
    }

    private func save() {
        if let d = try? JSONEncoder().encode(items) { try? d.write(to: url) }
    }
}

// ──────────────────────────────────────────────────────────
// MARK: Models
// ──────────────────────────────────────────────────────────
struct JournalEntry: Storable {
    let id   = UUID()
    let date = Date()
    var text: String?
    var audioFile: String?
}

struct MoneyEntry: Storable {
    let id   = UUID()
    let date = Date()
    var amount:  Double
    var method:  String
    var note:    String
}

struct FoodEntry: Storable {
    let id   = UUID()
    let date = Date()
    var food:     String
    var calories: Int
}

struct Dish: Identifiable, Codable {
    let id   = UUID()
    let name: String
    let kcal: Int
}

@MainActor
final class DishStore: ObservableObject {
    @Published var all: [Dish] = []
    init() {
        if  let url  = Bundle.main.url(forResource:"dishes", withExtension:"json"),
            let data = try? Data(contentsOf: url),
            let list = try? JSONDecoder().decode([Dish].self, from:data)
        {  all = list  }
    }
}

// ──────────────────────────────────────────────────────────
// MARK: Re-usable UI bits
// ──────────────────────────────────────────────────────────
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
                               endPoint:   .bottomTrailing)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(radius: configuration.isPressed ? 2 : 10)
            )
            .foregroundColor(.white)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension View {
    func fontSize(_ s: CGFloat) -> some View {
        font(.system(size: s, weight: .bold, design: .rounded))
    }
}

/// plain colour (system) or wallpaper chosen in Settings
struct BackgroundView: View {
    @Environment(\.colorScheme) private var scheme
    @AppStorage("wallpaperSelection") private var wp = 0
    var body: some View {
        if wp == 0 {
            Color(scheme == .dark ? .black : .white).ignoresSafeArea()
        } else {
            GeometryReader { g in
                Image("wallpaper\(wp)")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: g.size.width, height: g.size.height)
                    .position(x: g.size.width/2, y: g.size.height/2)
                    .ignoresSafeArea()
            }
        }
    }
}

/// animated rainbow headline
struct AnimatedGradientText: View {
    let text: String
    @State private var anim = false
    @Environment(\.colorScheme) private var scheme
    @AppStorage("wallpaperSelection") private var wp = 0
    var body: some View {
        Text(text)
            .foregroundColor(.clear)
            .overlay(
                LinearGradient(colors: palette,
                               startPoint: anim ? .leading : .trailing,
                               endPoint:   anim ? .trailing : .leading)
                    .animation(.linear(duration: 5).repeatForever(autoreverses: true),
                               value: anim)
                    .mask(Text(text))
            )
            .shadow(color: scheme == .dark ? .white.opacity(0.3) : .black.opacity(0.3),
                    radius: 4, x: 0, y: 2)
            .onAppear { anim = true }
    }
    private var palette: [Color] {
        switch wp {
        case 0: return scheme == .dark ? [.cyan,.mint,.green,.yellow] : [.pink,.purple,.indigo,.blue]
        case 1: return [.pink,.purple,.blue]
        case 2: return [.teal,.cyan,.mint,.yellow]
        default:return [.pink,.purple,.blue,.green,.yellow]
        }
    }
}

// ──────────────────────────────────────────────────────────
// MARK: Camera-picker
// ──────────────────────────────────────────────────────────
struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = .camera
        p.delegate   = context.coordinator
        return p
    }
    func updateUIViewController(_: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coord { Coord(self) }
    final class Coord: NSObject,
        UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ p: CameraPicker) { parent = p }
        func imagePickerController(_ p: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info:[UIImagePickerController.InfoKey:Any]) {
            if let img = info[.originalImage] as? UIImage { parent.onImage(img) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_: UIImagePickerController) { parent.dismiss() }
    }
}

// ──────────────────────────────────────────────────────────
// MARK: UIImage helper  → JPEG  ≤ 1 MB
// ──────────────────────────────────────────────────────────
extension UIImage {
    /// resize + recompress ⇒  ≤1 048 576 bytes or nil
    func jpegUnder1MB() -> Data? {
        let maxSide: CGFloat = 1024
        let scale = min(1, maxSide / max(size.width, size.height))
        let tgt   = CGSize(width: size.width*scale, height: size.height*scale)
        let rend  = UIGraphicsImageRenderer(size: tgt)
        let small = rend.image { _ in draw(in: CGRect(origin: .zero, size: tgt)) }

        var q: CGFloat = 0.7
        var step: CGFloat = 0.1
        var data = small.jpegData(compressionQuality: q)!
        while data.count > 950_000 && q > 0.2 {
            q -= step; step *= 0.5
            if let d = small.jpegData(compressionQuality: q) { data = d }
        }
        return data.count > 1_048_576 ? nil : data
    }
}

// ──────────────────────────────────────────────────────────
// MARK: LogMeal helpers
// ──────────────────────────────────────────────────────────
fileprivate func fetchCalories(id: Int, _ done:@escaping(Double?)->Void) {
    var r = URLRequest(url: URL(string:"https://api.logmeal.es/v2/dish/\(id)/info")!)
    r.setValue("Token \(LOGMEAL_TOKEN)", forHTTPHeaderField:"Authorization")
    URLSession.shared.dataTask(with:r){ d,_,_ in
        guard
            let d,
            let j = try? JSONSerialization.jsonObject(with:d) as? [String:Any],
            let n = j["nutritional_info"] as? [String:Any],
            let c = n["calories"] as? Double
        else { return done(nil) }
        done(c)
    }.resume()
}

fileprivate func recogniseFood(image: UIImage,
                               done:@escaping(Result<FoodEntry,Error>)->Void) {
    guard let jpg = image.jpegUnder1MB() else {
        return done(.failure(NSError(domain:"ImageTooBig",code:0)))
    }

    // multipart body
    let bound = UUID().uuidString
    var body = Data()
    func add(_ s:String){ body.append(Data(s.utf8)) }
    add("--\(bound)\r\nContent-Disposition: form-data; name=\"user_key\"\r\n\r\n\(LOGMEAL_USER_KEY)\r\n")
    add("--\(bound)\r\nContent-Disposition: form-data; name=\"image\"; filename=\"m.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n")
    body.append(jpg)
    add("\r\n--\(bound)--\r\n")

    var r = URLRequest(url: URL(string:"https://api.logmeal.es/v2/recognition/dish")!)
    r.httpMethod = "POST"
    r.httpBody   = body
    r.setValue("multipart/form-data; boundary=\(bound)", forHTTPHeaderField:"Content-Type")
    r.setValue("Token \(LOGMEAL_TOKEN)",                  forHTTPHeaderField:"Authorization")

    URLSession.shared.dataTask(with:r){ d,_,e in
        if let e { return done(.failure(e)) }
        guard let d,
              let j = try? JSONSerialization.jsonObject(with:d) as? [String:Any],
              let arr = j["recognition_results"] as? [[String:Any]],
              let first = arr.first,
              let name  = first["name"] as? String,
              let id    = first["id"]   as? Int
        else { return done(.failure(NSError(domain:"Parse",code:0))) }

        // immediate kcal if present
        if let info = first["nutritional_info"] as? [String:Any],
           let kcal = info["calories"] as? Double {
            return done(.success(FoodEntry(food:name, calories:Int(kcal))))
        }

        // fallback: detail endpoint
        fetchCalories(id:id){ real in
            done(.success(FoodEntry(food:name, calories:Int(real ?? 0))))
        }
    }.resume()
}

// ──────────────────────────────────────────────────────────
// MARK: Journal sheet   (text / audio)
// ──────────────────────────────────────────────────────────
final class AudioRecorder: NSObject, ObservableObject {
    @Published var recording = false
    private var rec: AVAudioRecorder?
    var url: URL? { rec?.url }
    func toggle(){ recording ? stop() : start() }
    private func start(){
        let dest = FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
                  .appendingPathComponent("journal-\(Date().timeIntervalSince1970).m4a")
        let set:[String:Any] = [ AVFormatIDKey:Int(kAudioFormatMPEG4AAC),
                                 AVSampleRateKey:12000,
                                 AVNumberOfChannelsKey:1,
                                 AVEncoderAudioQualityKey:AVAudioQuality.high.rawValue ]
        rec = try? AVAudioRecorder(url:dest, settings:set); rec?.record()
        recording = true
    }
    private func stop(){ rec?.stop(); recording=false }
}

struct JournalSheetView: View {
    enum Mode { case text, audio }
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var journal: JSONStore<JournalEntry>
    @State private var mode: Mode = .text
    @State private var text = ""
    @StateObject private var mic = AudioRecorder()
    @State private var showHistory = false

    var body: some View {
        NavigationStack {
            VStack {
                Picker("", selection: $mode) {
                    Label("Write",  systemImage:"square.and.pencil").tag(Mode.text)
                    Label("Audio", systemImage:"mic.fill")        .tag(Mode.audio)
                }
                .pickerStyle(.segmented).padding()

                if mode == .text {
                    ZStack(alignment:.topLeading){
                        if text.isEmpty {
                            Text("Start typing…")
                                .foregroundColor(.secondary)
                                .padding(12)
                        }
                        TextEditor(text:$text).padding(4)
                    }
                    .frame(maxHeight:250)
                    .background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:12))
                    .padding()
                } else {
                    VStack(spacing:16){
                        Text(mic.recording ? "Recording…" : "Tap to Start")
                        Button(mic.recording ? "Stop Recording" : "Start Recording") { mic.toggle() }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding()
                }
                Spacer()
            }
            .navigationTitle("Journal")
            .toolbar {
                ToolbarItem(placement:.navigationBarLeading) {
                    Button("History"){ showHistory = true }
                }
                ToolbarItem(placement:.confirmationAction) {
                    Button("Save"){ save(); dismiss() }
                        .disabled(disabled)
                }
            }
            .navigationDestination(isPresented:$showHistory){ JournalListView() }
        }
    }
    private var disabled: Bool {
        (mode == .text  && text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty) ||
        (mode == .audio && mic.url == nil)
    }
    private func save() {
        var e = JournalEntry()
        if mode == .text          { e.text      = text }
        else if let u = mic.url   { e.audioFile = u.lastPathComponent }
        journal.add(e)
    }
}

struct JournalListView: View {
    @EnvironmentObject private var journal: JSONStore<JournalEntry>
    var body: some View {
        List {
            ForEach(journal.items) { e in
                if let t = e.text {
                    VStack(alignment:.leading) {
                        Text(date(e.date)).font(.headline)
                        Text(t).lineLimit(3)
                    }
                } else if let f = e.audioFile {
                    AudioRow(file:f, date:e.date)
                }
            }
        }
        .navigationTitle("My Journals")
    }
    private func date(_ d:Date)->String{
        DateFormatter.localizedString(from:d,
                                      dateStyle:.medium,
                                      timeStyle:.short)
    }
    struct AudioRow: View {
        let file: String
        let date: Date
        @State private var player: AVAudioPlayer?
        var body: some View {
            HStack {
                Label(dateStr, systemImage:"waveform.circle")
                Spacer()
                Button { play() } label: {
                    Image(systemName:"play.circle").font(.title2)
                }
            }
            .padding(.vertical,4)
        }
        private var dateStr: String {
            DateFormatter.localizedString(from:date,
                                           dateStyle:.medium,
                                           timeStyle:.short)
        }
        private func play() {
            let u = FileManager.default.urls(for:.documentDirectory,
                                             in:.userDomainMask)[0]
                    .appendingPathComponent(file)
            player = try? AVAudioPlayer(contentsOf:u); player?.play()
        }
    }
}

// ──────────────────────────────────────────────────────────
// MARK: Money dashboard
// ──────────────────────────────────────────────────────────
struct MoneyDashboard: View {
    @EnvironmentObject private var store: JSONStore<MoneyEntry>
    @State private var amount = ""
    @State private var note   = ""
    @State private var method = "WeChat"
    private let methods = ["WeChat","Alipay","Cash","Card","Other"]

    var body: some View {
        ScrollView {
            VStack(spacing:24) {
                // input
                VStack(spacing:12) {
                    TextField("Amount (¥)", text:$amount)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)

                    Picker("Method", selection:$method) {
                        ForEach(methods, id:\.self, content:Text.init)
                    }
                    .pickerStyle(.segmented)

                    TextField("Note (optional)", text:$note)
                        .textFieldStyle(.roundedBorder)

                    Button("Add") {
                        guard let v = Double(amount) else { return }
                        store.add(MoneyEntry(amount:v, method:method, note:note))
                        amount=""; note=""
                    }
                    .buttonStyle(GradientButtonStyle(colors:[.purple,.pink]))
                }
                .padding()
                .background(.ultraThinMaterial,
                            in: RoundedRectangle(cornerRadius:16))

                // chart
                Chart {
                    ForEach(dailyTotals, id:\.0) { d,v in
                        BarMark(x:.value("Day",d,unit:.day),
                                y:.value("¥", v))
                    }
                }
                .frame(height:200)
                .padding()

                // history
                ForEach(store.items) { e in
                    HStack {
                        VStack(alignment:.leading) {
                            Text("¥\(e.amount, specifier:"%.2f") • \(e.method)")
                            if !e.note.isEmpty { Text(e.note).font(.caption) }
                        }
                        Spacer()
                        Text(short(e.date)).foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.vertical,4)
                }
            }
            .padding()
        }
        .navigationTitle("Spending")
    }

    private var dailyTotals:[(Date,Double)] {
        let c = Calendar.current
        let last7 = c.date(byAdding:.day,
                           value:-6,
                           to:Date())!
        let g = Dictionary(grouping:store.items.filter{$0.date>=last7}) {
            c.startOfDay(for:$0.date)
        }
        return g.map{($0.key,$0.value.reduce(0){$0+$1.amount})}
                .sorted{$0.0<$1.0}
    }
    private func short(_ d:Date)->String {
        DateFormatter.localizedString(from:d,
                                      dateStyle:.short,
                                      timeStyle:.none)
    }
}

// ──────────────────────────────────────────────────────────
// MARK: Food dashboard   (camera + LogMeal)
// ──────────────────────────────────────────────────────────
struct FoodDashboard: View {
    @EnvironmentObject private var store: JSONStore<FoodEntry>
    @State private var showPicker = false          // dish browser
    @State private var editing    : FoodEntry?     // row being edited

    @State private var food = ""
    @State private var kcal = ""

    @State private var camera    = false
    @State private var uploading = false

    @State private var showError = false
    @State private var errorMsg  = ""
    
    
    var body: some View {
        ScrollView {
            VStack(spacing:24) {

                // camera button
                Button {
                    camera = true
                } label: {
                    HStack {
                        Image(systemName:"camera")
                        Text("Snap meal photo")
                    }
                }
                .buttonStyle(GradientButtonStyle(colors:[.cyan,.blue]))
                .overlay(alignment:.trailing) {
                    if uploading {
                        ProgressView()
                            .padding(.trailing,8)
                    }
                }
                .padding(.top,10)

                // manual card
                VStack(spacing:12) {
                    TextField("Food", text:$food)
                        .textFieldStyle(.roundedBorder)
                    TextField("Calories", text:$kcal)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        guard let c = Int(kcal) else { return }
                        store.add(FoodEntry(food:food, calories:c))
                        food=""; kcal=""
                    }
                    .buttonStyle(GradientButtonStyle(colors:[.green,.yellow]))
                }
                .padding()
                .background(.ultraThinMaterial,
                            in: RoundedRectangle(cornerRadius:16))

                // header / hint
                if store.items.isEmpty {
                    Text("No entries yet • Snap a photo or add manually!")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .padding(.top,20)
                } else {
                    Text("Recent entries")
                        .font(.headline)
                        .frame(maxWidth:.infinity,
                               alignment:.leading)
                        .padding(.horizontal)
                }

                // chart
                Chart {
                    ForEach(dailyCalories, id:\.0) { d,v in
                        BarMark(x:.value("Day",d,unit:.day),
                                y:.value("kcal",v))
                    }
                }
                .frame(height:200)
                .padding()

                // history list
                ForEach(store.items) { e in
                    HStack {
                        VStack(alignment:.leading) {
                            Text(e.food)
                            Text("\(e.calories) kcal")
                                .font(.caption)
                        }
                        Spacer()
                        Text(short(e.date))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.vertical,4)
                    .onTapGesture { editing = e }
                }
            }
            .padding()
        }
        .sheet(isPresented:$camera) {
            CameraPicker { img in
                uploading = true
                DispatchQueue.global(qos:.userInitiated).async {
                    recogniseFood(image: img) { result in
                        DispatchQueue.main.async {
                            uploading = false
                            switch result {
                            case .success(let entry):
                                store.add(entry)
                            case .failure(let err):
                                errorMsg = err.localizedDescription
                                showError = true
                            }
                        }
                    }
                }
            }
        }
        // dish browser
        .sheet(isPresented:$showPicker) {
            DishPicker()
                .environmentObject(store)          // for the add()
                .environmentObject(DishStore())    // its own loader
        }

        // edit sheet
        .sheet(item:$editing) { entry in
            EditFoodSheet(entry: entry) { updated in
                store.update(updated)
            }
        }
        .alert("LogMeal error", isPresented:$showError) {
            Button("OK",role:.cancel){}
        } message: {
            Text(errorMsg)
        }
        .navigationTitle("Food Log")
    }

    private var dailyCalories:[(Date,Int)] {
        let c = Calendar.current
        let last7 = c.date(byAdding:.day, value:-6, to:Date())!
        let g = Dictionary(grouping:store.items.filter{$0.date>=last7}) {
            c.startOfDay(for:$0.date)
        }
        return g.map{($0.key,$0.value.reduce(0){$0+$1.calories})}
                .sorted{$0.0<$1.0}
    }
    private func short(_ d:Date)->String {
        DateFormatter.localizedString(from:d,
                                      dateStyle:.short,
                                      timeStyle:.none)
    }
}

// ──────────────────────────────────────────────────────────
// MARK: Dish picker  (NEW)
// ──────────────────────────────────────────────────────────
struct DishPicker: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dishes: DishStore
    @EnvironmentObject private var foodStore: JSONStore<FoodEntry>
    @State private var search = ""

    var body: some View {
        NavigationStack {
            List(filtered) { dish in
                Button {
                    foodStore.add(FoodEntry(food:dish.name, calories:dish.kcal))
                    dismiss()
                } label: {
                    HStack {
                        Text(dish.name)
                        Spacer()
                        Text("\(dish.kcal) kcal").foregroundColor(.secondary)
                    }
                }
            }
            .searchable(text:$search, prompt:"Search dishes")
            .navigationTitle("Pick a Dish")
        }
    }

    private var filtered: [Dish] {
        if search.isEmpty { return dishes.all }
        return dishes.all.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }
}

// ──────────────────────────────────────────────────────────
// MARK: Edit food sheet  (NEW)
// ──────────────────────────────────────────────────────────
struct EditFoodSheet: View, Identifiable {
    let id = UUID()                        // for sheet presentation
    @Environment(\.dismiss) private var dismiss
    private let original: FoodEntry
    var onSave: (FoodEntry) -> Void

    @State private var food: String
    @State private var kcal: String

    init(entry: FoodEntry, onSave: @escaping (FoodEntry) -> Void) {
        self.original = entry
        self.onSave   = onSave
        _food = State(initialValue: entry.food)
        _kcal = State(initialValue: "\(entry.calories)")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header:Text("Food")) {
                    TextField("Food", text:$food)
                }
                Section(header:Text("Calories")) {
                    TextField("kcal", text:$kcal)
                        .keyboardType(.numberPad)
                }
            }
            .navigationTitle("Edit Entry")
            .toolbar {
                ToolbarItem(placement:.cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement:.confirmationAction) {
                    Button("Save") { save() }
                        .disabled(Int(kcal) == nil || food.trimmingCharacters(in:.whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        guard let c = Int(kcal) else { return }
        var updated = original
        updated.food = food
        updated.calories = c
        onSave(updated)
        dismiss()
    }
}

// ──────────────────────────────────────────────────────────
// MARK: Home + swipe-root  (Money ← → Food)
// ──────────────────────────────────────────────────────────
struct HomeCenterView: View {
    @AppStorage("nickname") private var nick = "Friend"
    @State private var showJournal = false
    var body: some View {
        GeometryReader { g in
            VStack(spacing:40) {
                AnimatedGradientText(
                    text:"Welcome \(nick),\nHow are you feeling today?"
                )
                .fontSize(42)
                .frame(maxWidth:.infinity,
                       maxHeight:g.size.height*0.33,
                       alignment:.bottomLeading)
                .padding(.horizontal,24)

                VStack(spacing:22) {
                    Button("Journal Now") { showJournal = true }
                        .buttonStyle(GradientButtonStyle(colors:[.purple,.pink,.orange]))
                    NavigationLink("Reminders") { RemindersView() }
                        .buttonStyle(GradientButtonStyle(colors:[.blue,.cyan,.mint]))
                    NavigationLink("General")   { GeneralMenuView() }
                        .buttonStyle(GradientButtonStyle(colors:[.teal,.green,.yellow]))
                }
                Spacer()
            }
            .sheet(isPresented:$showJournal){ JournalSheetView() }
            .padding(.top,60)
        }
    }
}

struct SwipeRootView: View {
    var body: some View {
        BackgroundView()
            .overlay(
                TabView {
                    NavigationStack { MoneyDashboard() }
                    HomeCenterView()
                    NavigationStack { FoodDashboard() }
                }
                .tabViewStyle(.page(indexDisplayMode:.never))
            )
    }
}

// ──────────────────────────────────────────────────────────
// MARK: Simple in-memory reminders
// ──────────────────────────────────────────────────────────
struct RemindersView: View {
    struct Item: Identifiable { let id = UUID(); var title:String; var done = false }
    @State private var items:[Item] = []
    @State private var new = ""
    var body: some View {
        ZStack { BackgroundView().ignoresSafeArea()
            VStack {
                HStack {
                    TextField("New reminder", text:$new)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        guard !new.isEmpty else { return }
                        items.insert(Item(title:new), at:0)
                        new = ""
                    } label: {
                        Image(systemName:"plus.circle.fill").font(.title2)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()

                List {
                    ForEach(items) { i in
                        HStack {
                            Image(systemName:i.done ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(i.done ? .green : .secondary)
                                .onTapGesture {
                                    if let idx = items.firstIndex(where:{$0.id == i.id}) {
                                        items[idx].done.toggle()
                                    }
                                }
                            Text(i.title)
                        }
                    }
                    .onDelete { items.remove(atOffsets:$0) }
                }
            }
            .navigationTitle("Reminders")
        }
    }
}

// ──────────────────────────────────────────────────────────
// MARK: Manual input forms  (General menu)
// ──────────────────────────────────────────────────────────
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
    private let methods = ["WeChat","Alipay","Cash","Card","Other"]
    var body: some View {
        Form {
            Section(header:Text("Amount")) {
                TextField("¥0.00", text:$amount)
                    .keyboardType(.decimalPad)
            }
            Section(header:Text("Payment Method")) {
                Picker("Method", selection:$method) {
                    ForEach(methods, id:\.self, content:Text.init)
                }
                .pickerStyle(.segmented)
            }
            Section(header:Text("Note")) {
                TextField("Description (optional)", text:$note)
            }
            Button("Save"){}      // stub
                .buttonStyle(GradientButtonStyle(colors:[.purple,.pink]))
                .frame(maxWidth:.infinity, alignment:.center)
        }
        .navigationTitle("Monetary")
        .background(BackgroundView().ignoresSafeArea())
    }
}

struct FoodInputView: View {
    @State private var food = ""
    @State private var kcal = ""
    var body: some View {
        Form {
            Section(header:Text("Food")) {
                TextField("What did you eat?", text:$food)
            }
            Section(header:Text("Calories")) {
                TextField("kcal", text:$kcal)
                    .keyboardType(.numberPad)
            }
            Button("Save"){}      // stub
                .buttonStyle(GradientButtonStyle(colors:[.green,.yellow]))
                .frame(maxWidth:.infinity, alignment:.center)
        }
        .navigationTitle("Food")
        .background(BackgroundView().ignoresSafeArea())
    }
}

struct SleepInputView: View {
    @State private var hrs = 8.0
    var body: some View {
        Form {
            Section(header:Text("Hours Slept")) {
                Stepper(value:$hrs, in:0...24, step:0.5) {
                    Text("\(hrs, specifier:"%.1f") h")
                }
            }
            Button("Save"){}      // stub
                .buttonStyle(GradientButtonStyle(colors:[.blue,.indigo]))
                .frame(maxWidth:.infinity, alignment:.center)
        }
        .navigationTitle("Sleep")
        .background(BackgroundView().ignoresSafeArea())
    }
}

// ──────────────────────────────────────────────────────────
// MARK: Profile / Settings / Notifications (stubs)
// ──────────────────────────────────────────────────────────
struct ProfileView: View {
    @AppStorage("nickname") private var nick = "Friend"
    @State private var email = ""
    var body: some View {
        ZStack { BackgroundView().ignoresSafeArea()
            NavigationStack {
                Form {
                    Section(header:Text("Personal Details")) {
                        TextField("Nickname", text:$nick)
                        TextField("Email", text:$email)
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
        ZStack { BackgroundView().ignoresSafeArea()
            NavigationStack {
                Form {
                    Section(header:Text("Appearance")) {
                        Picker("Background", selection:$wp) {
                            Text("System").tag(0)
                            Text("Wallpaper 1").tag(1)
                            Text("Wallpaper 2").tag(2)
                        }
                    }
                    Section(header:Text("Notifications")) {
                        Toggle("Enable notifications",
                               isOn:.constant(true)).disabled(true)
                    }
                }
                .navigationTitle("Settings")
            }
        }
    }
}

struct NotificationsView: View {
    var body: some View {
        ZStack { BackgroundView().ignoresSafeArea()
            Text("Notifications coming soon…") }
    }
}

// ──────────────────────────────────────────────────────────
// MARK: Root + tab bar
// ──────────────────────────────────────────────────────────
struct ContentView: View {
    @StateObject private var journals = JSONStore<JournalEntry>("journals.json")
    @StateObject private var money    = JSONStore<MoneyEntry>  ("money.json")
    @StateObject private var food     = JSONStore<FoodEntry>   ("food.json")
    var body: some View {
        TabBarView()
            .environmentObject(journals)
            .environmentObject(money)
            .environmentObject(food)
    }
}

struct TabBarView: View {
    var body: some View {
        NavigationStack {
            TabView {
                SwipeRootView()
                    .tabItem { Label("Home", systemImage:"house.fill") }
                NotificationsView()
                    .tabItem { Label("Alerts", systemImage:"bell.badge.fill") }
                ProfileView()
                    .tabItem { Label("Profile", systemImage:"person.crop.circle.fill") }
                SettingsView()
                    .tabItem { Label("Settings", systemImage:"gearshape.2.fill") }
            }
        }
    }
}

// ──────────────────────────────────────────────────────────
// MARK: Preview
// ──────────────────────────────────────────────────────────
#Preview {
    ContentView()
}
