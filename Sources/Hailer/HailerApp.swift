import AppKit
import Combine
import SwiftUI

@main
struct HailerApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("Hailer", id: "main") {
            ContentView()
                .environmentObject(model)
                .environmentObject(model.store)
                .environmentObject(model.settings)
                .frame(minWidth: 720, minHeight: 440)
        }
        .defaultSize(width: 980, height: 640)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Script") { model.newScript() }
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandMenu("Prompter") {
                Button("Start Prompter") { model.openPrompter() }
                    .keyboardShortcut("p", modifiers: .command)
                    .disabled(model.selectedID == nil)
            }
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    let settings: PrompterSettings
    let store: ScriptStore
    let prompter: PrompterController

    @Published var selectedID: UUID?

    private var terminateSub: AnyCancellable?

    init() {
        let settings = PrompterSettings()
        self.settings = settings
        self.store = ScriptStore()
        self.prompter = PrompterController(settings: settings)
        self.selectedID = store.scripts.first?.id

        // Flush the per-script position and any pending edits on quit.
        terminateSub = NotificationCenter.default
            .publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.prompter.persistPosition()
                    self?.store.flush()
                }
            }
    }

    func newScript() {
        let script = store.newScript()
        selectedID = script.id
    }

    func openPrompter() {
        guard let id = selectedID else { return }
        prompter.present(scriptID: id, store: store)
    }

    func delete(_ id: UUID) {
        if prompter.scriptID == id {
            prompter.closeWindow()
        }
        store.delete(id)
        if selectedID == id {
            selectedID = store.scripts.first?.id
        }
    }
}
