import AppKit
import Combine
import Foundation

// MARK: - Script

struct Script: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var body: String
    var savedProgress: Double = 0 // 0...1 fraction of the prompter scroll
    var modifiedAt = Date()

    var wordCount: Int {
        body.split(whereSeparator: \.isWhitespace).count
    }

    static let welcome = Script(
        title: "Welcome to Hailer",
        body: """
        Welcome to Hailer, your Mac's speaking trumpet.

        Write or paste a script here in the editor, then press Command-P to raise the prompter. \
        The prompter floats above every other window, so your notes stay in view while you record.

        Press SPACE to start the scroll and again to pause. Nudge the pace with the arrow keys: \
        right or up goes faster, left or down eases off. If you drift from the text, scrub with \
        the scroll wheel or a two-finger swipe; Hailer pauses while you grab the script and picks \
        the scroll back up a moment after you let go.

        Press R to return to the top at any time. Press F for true fullscreen. Press M to mirror \
        the text horizontally for a beam-splitter rig, and watch for the eye-line arrows that mark \
        your reading height.

        Press T to collapse the prompter into a one-line ticker, a thin strip that sits happily \
        just under your camera while the script streams by at the same pace. Press T again to \
        open it back out.

        When you close the prompter, Hailer remembers where you stopped, so the next take starts \
        exactly where you left off. Press ESCAPE to lower the prompter and come back to this \
        editor. Fair winds and clean takes.
        """
    )
}

// MARK: - Store

@MainActor
final class ScriptStore: ObservableObject {
    @Published var scripts: [Script] = [] {
        didSet { scheduleSave() }
    }

    private var saveTask: Task<Void, Never>?
    private var loading = false

    private var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Hailer", isDirectory: true)
    }

    private var fileURL: URL { directory.appendingPathComponent("scripts.json") }

    init() {
        load()
        if scripts.isEmpty {
            scripts = [.welcome]
        }
    }

    func script(_ id: UUID?) -> Script? {
        guard let id else { return nil }
        return scripts.first { $0.id == id }
    }

    @discardableResult
    func newScript() -> Script {
        let script = Script(title: "Untitled Script", body: "")
        scripts.insert(script, at: 0)
        return script
    }

    func duplicate(_ id: UUID) {
        guard let index = scripts.firstIndex(where: { $0.id == id }) else { return }
        var copy = scripts[index]
        copy.id = UUID()
        copy.title += " Copy"
        copy.modifiedAt = Date()
        copy.savedProgress = 0
        scripts.insert(copy, at: index + 1)
    }

    func delete(_ id: UUID) {
        scripts.removeAll { $0.id == id }
    }

    func updateProgress(_ id: UUID, fraction: Double) {
        guard let index = scripts.firstIndex(where: { $0.id == id }) else { return }
        scripts[index].savedProgress = min(1, max(0, fraction))
    }

    /// Write immediately (used on app termination).
    func flush() {
        saveTask?.cancel()
        saveNow()
    }

    private func scheduleSave() {
        guard !loading else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    private func saveNow() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(scripts).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Hailer: failed to save scripts: \(error)")
        }
    }

    private func load() {
        loading = true
        defer { loading = false }
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        scripts = (try? decoder.decode([Script].self, from: data)) ?? []
    }
}

// MARK: - Settings

@MainActor
final class PrompterSettings: ObservableObject {
    @Published var speed: Double { didSet { save(speed, "speed") } }               // points/second
    @Published var fontSize: Double { didSet { save(fontSize, "fontSize") } }
    @Published var lineSpacingFactor: Double { didSet { save(lineSpacingFactor, "lineSpacing") } }
    @Published var marginFraction: Double { didSet { save(marginFraction, "margin") } }
    @Published var mirrored: Bool { didSet { save(mirrored, "mirrored") } }
    @Published var showEyeline: Bool { didSet { save(showEyeline, "eyeline") } }

    init() {
        let d = UserDefaults.standard
        speed = d.object(forKey: "prompter.speed") as? Double ?? 70
        fontSize = d.object(forKey: "prompter.fontSize") as? Double ?? 56
        lineSpacingFactor = d.object(forKey: "prompter.lineSpacing") as? Double ?? 1.4
        marginFraction = d.object(forKey: "prompter.margin") as? Double ?? 0.12
        mirrored = d.object(forKey: "prompter.mirrored") as? Bool ?? false
        showEyeline = d.object(forKey: "prompter.eyeline") as? Bool ?? true
    }

    private func save(_ value: Any, _ key: String) {
        UserDefaults.standard.set(value, forKey: "prompter.\(key)")
    }
}
