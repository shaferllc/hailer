import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: ScriptStore
    @EnvironmentObject var settings: PrompterSettings

    @State private var pendingDelete: Script?

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selectedID) {
                ForEach(store.scripts) { script in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(script.title.isEmpty ? "Untitled" : script.title)
                            .lineLimit(1)
                        Text("\(script.wordCount) words · \(script.modifiedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(script.id)
                    .contextMenu {
                        Button("Duplicate") { store.duplicate(script.id) }
                        Button("Delete…", role: .destructive) { pendingDelete = script }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 230)
            .onDeleteCommand {
                if let script = store.script(model.selectedID) { pendingDelete = script }
            }
            .toolbar {
                ToolbarItem {
                    Button {
                        model.newScript()
                    } label: {
                        Label("New Script", systemImage: "plus")
                    }
                    .help("New script (⌘N)")
                }
            }
        } detail: {
            if let id = model.selectedID,
               let index = store.scripts.firstIndex(where: { $0.id == id }) {
                EditorView(script: $store.scripts[index])
                    .id(id)
            } else {
                ContentUnavailableView(
                    "No Script Selected",
                    systemImage: "text.alignleft",
                    description: Text("Create a script with ⌘N, then press ⌘P to raise the prompter.")
                )
            }
        }
        .toolbar {
            ToolbarItemGroup {
                AppearanceButton(settings: settings)
                Button {
                    model.openPrompter()
                } label: {
                    Label("Start Prompter", systemImage: "play.rectangle.fill")
                }
                .disabled(model.selectedID == nil)
                .help("Start Prompter (⌘P)")
            }
        }
        .alert(
            "Delete “\(pendingDelete?.title ?? "")”?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            )
        ) {
            Button("Delete", role: .destructive) {
                if let script = pendingDelete { model.delete(script.id) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("This can't be undone.")
        }
    }
}

// MARK: - Editor

private struct EditorView: View {
    @Binding var script: Script

    var body: some View {
        VStack(spacing: 0) {
            TextField("Title", text: $script.title)
                .textFieldStyle(.plain)
                .font(.title2.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)
            Divider()
            TextEditor(text: $script.body)
                .font(.system(size: 16))
                .lineSpacing(5)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            Divider()
            HStack(spacing: 12) {
                Text("\(script.wordCount) words")
                Text("≈ \(readTimeText) at 140 wpm")
                Spacer()
                if script.savedProgress > 0.001 && script.savedProgress < 0.999 {
                    Text("resumes at \(Int(script.savedProgress * 100))%")
                    Button("Reset position") { script.savedProgress = 0 }
                        .buttonStyle(.link)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .onChange(of: script.body) { _, _ in script.modifiedAt = Date() }
        .onChange(of: script.title) { _, _ in script.modifiedAt = Date() }
    }

    private var readTimeText: String {
        let minutes = Double(script.wordCount) / 140.0
        return minutes < 1 ? "\(max(1, Int((minutes * 60).rounded()))) s" : timeString(minutes * 60)
    }
}

// MARK: - Appearance popover

private struct AppearanceButton: View {
    @ObservedObject var settings: PrompterSettings
    @State private var shown = false

    var body: some View {
        Button {
            shown.toggle()
        } label: {
            Label("Prompter Style", systemImage: "textformat.size")
        }
        .help("Prompter appearance")
        .popover(isPresented: $shown, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 14) {
                labeledSlider(
                    "Font size", value: $settings.fontSize, in: 24...120,
                    text: "\(Int(settings.fontSize)) pt"
                )
                labeledSlider(
                    "Line spacing", value: $settings.lineSpacingFactor, in: 1.0...2.2,
                    text: String(format: "%.1f×", settings.lineSpacingFactor)
                )
                labeledSlider(
                    "Side margin", value: $settings.marginFraction, in: 0...0.3,
                    text: "\(Int(settings.marginFraction * 100)) %"
                )
                labeledSlider(
                    "Speed", value: $settings.speed, in: 10...400,
                    text: "\(Int(settings.speed)) pt/s"
                )
                Divider()
                Toggle("Mirror flip (beam-splitter)", isOn: $settings.mirrored)
                Toggle("Eye-line marker", isOn: $settings.showEyeline)
            }
            .padding(16)
            .frame(width: 300)
        }
    }

    private func labeledSlider(
        _ title: String, value: Binding<Double>, in range: ClosedRange<Double>, text: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(text).foregroundStyle(.secondary).font(.caption.monospacedDigit())
            }
            Slider(value: value, in: range)
        }
    }
}
