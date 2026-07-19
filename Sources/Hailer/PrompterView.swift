import SwiftUI

// MARK: - Root

struct PrompterRootView: View {
    @ObservedObject var controller: PrompterController
    @ObservedObject var engine: PrompterEngine
    @ObservedObject var settings: PrompterSettings
    @ObservedObject var store: ScriptStore
    let scriptID: UUID

    @State private var stripHover = false

    private let eyeFraction: CGFloat = 0.35

    private var script: Script? { store.script(scriptID) }

    private var tickerText: String {
        let body = script?.body ?? ""
        let joined = body.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return joined.isEmpty ? "— this script is empty —" : joined
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if controller.isTicker {
                TickerLayer(engine: engine, settings: settings, text: tickerText)

                HStack {
                    Spacer()
                    TickerControls(controller: controller, engine: engine, settings: settings)
                        .padding(.trailing, 10)
                }
                .opacity(stripHover || !engine.isPlaying ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: stripHover)
                .animation(.easeInOut(duration: 0.2), value: engine.isPlaying)

                VStack {
                    Spacer()
                    ProgressStrip(engine: engine).frame(height: 2)
                }
            } else {
                ScrollLayer(
                    engine: engine,
                    settings: settings,
                    text: (script?.body.isEmpty ?? true) ? "— this script is empty —" : script!.body,
                    eyeFraction: eyeFraction
                )

                if settings.showEyeline {
                    EyelineMarker(fraction: eyeFraction)
                }

                VStack(spacing: 0) {
                    ProgressStrip(engine: engine).frame(height: 3)
                    Spacer()
                    PrompterControls(controller: controller, engine: engine, settings: settings)
                        .padding(.bottom, 14)
                }
            }
        }
        .onHover { stripHover = $0 }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Scrolling script layer

private struct ScrollLayer: View {
    @ObservedObject var engine: PrompterEngine
    @ObservedObject var settings: PrompterSettings
    let text: String
    let eyeFraction: CGFloat

    var body: some View {
        GeometryReader { geo in
            let vh = geo.size.height
            let columnWidth = max(60, geo.size.width * (1 - 2 * CGFloat(settings.marginFraction)))
            VStack(spacing: 0) {
                // Lead-in: at offset 0 the first line sits on the eye-line.
                Color.clear.frame(height: vh * eyeFraction)
                Text(text)
                    .font(.system(size: settings.fontSize, weight: .semibold))
                    .lineSpacing(settings.fontSize * max(0, settings.lineSpacingFactor - 1))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color(white: 0.95))
                    .frame(width: columnWidth)
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { height in
                        // With these paddings maxOffset == text height exactly:
                        // the last line crosses the eye-line at the end.
                        engine.setMaxOffset(height)
                    }
                Color.clear.frame(height: vh * (1 - eyeFraction))
            }
            .frame(width: geo.size.width)
            .offset(y: -engine.offset)
        }
        .scaleEffect(x: settings.mirrored ? -1 : 1, y: 1)
        .clipped()
    }
}

// MARK: - Ticker layer

private struct TickerLayer: View {
    @ObservedObject var engine: PrompterEngine
    @ObservedObject var settings: PrompterSettings
    let text: String

    @State private var textWidth: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let vw = geo.size.width
            let fontSize = min(max(22, geo.size.height * 0.5), 80)
            HStack(spacing: 0) {
                Color.clear.frame(width: vw, height: 1)
                Text(text)
                    .font(.system(size: fontSize, weight: .bold))
                    .foregroundStyle(Color(white: 0.95))
                    .lineLimit(1)
                    .fixedSize()
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.width
                    } action: { width in
                        textWidth = width
                        engine.setMaxOffset(width + vw)
                    }
                Color.clear.frame(width: vw, height: 1)
            }
            .frame(height: geo.size.height)
            .offset(x: -engine.offset)
            .onChange(of: vw) { _, newWidth in
                engine.setMaxOffset(textWidth + newWidth)
            }
        }
        .scaleEffect(x: settings.mirrored ? -1 : 1, y: 1)
        .clipped()
    }
}

// MARK: - Chrome

private struct ProgressStrip: View {
    @ObservedObject var engine: PrompterEngine

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(.white.opacity(0.08))
                Rectangle()
                    .fill(Color.orange)
                    .frame(width: geo.size.width * CGFloat(engine.progressFraction))
            }
        }
        .allowsHitTesting(false)
    }
}

private struct EyelineMarker: View {
    let fraction: CGFloat

    var body: some View {
        GeometryReader { geo in
            let y = geo.size.height * fraction
            ZStack {
                Rectangle()
                    .fill(.white.opacity(0.06))
                    .frame(width: geo.size.width, height: 2)
                    .position(x: geo.size.width / 2, y: y)
                Image(systemName: "arrowtriangle.right.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.orange.opacity(0.85))
                    .position(x: 16, y: y)
                Image(systemName: "arrowtriangle.left.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.orange.opacity(0.85))
                    .position(x: geo.size.width - 16, y: y)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Controls (full prompter)

private struct PrompterControls: View {
    @ObservedObject var controller: PrompterController
    @ObservedObject var engine: PrompterEngine
    @ObservedObject var settings: PrompterSettings

    @State private var hovering = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            fullBar
            compactBar
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .onHover { hovering = $0 }
        .opacity(engine.isPlaying && !hovering ? 0.12 : 1)
        .animation(.easeInOut(duration: 0.25), value: engine.isPlaying)
        .animation(.easeInOut(duration: 0.15), value: hovering)
    }

    private var fullBar: some View {
        HStack(spacing: 14) {
            transport
            speedSlider
            Divider().frame(height: 16)
            fontButtons
            iconToggle("arrow.left.and.right", active: settings.mirrored, help: "Mirror flip (M)") {
                settings.mirrored.toggle()
            }
            iconToggle("arrow.right.to.line", active: settings.showEyeline, help: "Eye-line marker") {
                settings.showEyeline.toggle()
            }
            iconButton("rectangle.compress.vertical", help: "Ticker mode (T)") {
                controller.toggleTicker()
            }
            iconButton("arrow.up.left.and.arrow.down.right", help: "Fullscreen (F)") {
                controller.toggleFullscreen()
            }
            Divider().frame(height: 16)
            timeLabel
            iconButton("xmark", help: "Close (Esc)") { controller.closeWindow() }
        }
    }

    private var compactBar: some View {
        HStack(spacing: 12) {
            transport
            speedSlider
            timeLabel
            iconButton("xmark", help: "Close (Esc)") { controller.closeWindow() }
        }
    }

    private var transport: some View {
        HStack(spacing: 12) {
            iconButton(engine.isPlaying ? "pause.fill" : "play.fill", help: "Play / pause (Space)") {
                engine.togglePlay()
            }
            iconButton("backward.end.fill", help: "Restart (R)") { engine.restart() }
        }
    }

    private var speedSlider: some View {
        HStack(spacing: 6) {
            Image(systemName: "tortoise.fill").font(.system(size: 10)).foregroundStyle(.secondary)
            Slider(value: $settings.speed, in: 10...400).frame(width: 130)
            Image(systemName: "hare.fill").font(.system(size: 10)).foregroundStyle(.secondary)
            Text("\(Int(settings.speed))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .trailing)
        }
    }

    private var fontButtons: some View {
        HStack(spacing: 10) {
            iconButton("textformat.size.smaller", help: "Smaller text") {
                settings.fontSize = max(20, settings.fontSize - 4)
            }
            iconButton("textformat.size.larger", help: "Larger text") {
                settings.fontSize = min(160, settings.fontSize + 4)
            }
        }
    }

    private var timeLabel: some View {
        Text("\(timeString(engine.elapsedSeconds)) · −\(timeString(engine.remainingSeconds))")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
    }
}

// MARK: - Controls (ticker)

private struct TickerControls: View {
    @ObservedObject var controller: PrompterController
    @ObservedObject var engine: PrompterEngine
    @ObservedObject var settings: PrompterSettings

    var body: some View {
        HStack(spacing: 12) {
            iconButton(engine.isPlaying ? "pause.fill" : "play.fill", help: "Play / pause (Space)") {
                engine.togglePlay()
            }
            iconButton("backward.end.fill", help: "Restart (R)") { engine.restart() }
            Slider(value: $settings.speed, in: 10...400).frame(width: 90)
            iconButton("rectangle.expand.vertical", help: "Back to prompter (T)") {
                controller.toggleTicker()
            }
            iconButton("xmark", help: "Close (Esc)") { controller.closeWindow() }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

// MARK: - Small helpers

private func iconButton(_ systemName: String, help: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .contentShape(Rectangle())
    }
    .help(help)
}

private func iconToggle(
    _ systemName: String, active: Bool, help: String, action: @escaping () -> Void
) -> some View {
    Button(action: action) {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(active ? Color.orange : Color.white)
            .frame(width: 18, height: 18)
            .contentShape(Rectangle())
    }
    .help(help)
}

func timeString(_ seconds: Double) -> String {
    let total = max(0, Int(seconds.rounded()))
    return String(format: "%d:%02d", total / 60, total % 60)
}
