import Combine
import Foundation
import QuartzCore

/// Drives the prompter's motion: a 60 fps tick with sub-pixel accumulation
/// (offset is a Double that advances by speed × dt each frame, so fractional
/// pixels carry over and the scroll stays silky at any speed).
@MainActor
final class PrompterEngine: ObservableObject {
    @Published private(set) var offset: CGFloat = 0
    @Published private(set) var maxOffset: CGFloat = 0
    @Published var isPlaying = false {
        didSet {
            guard oldValue != isPlaying else { return }
            if isPlaying {
                lastTick = CACurrentMediaTime()
            } else {
                onPersist?(progressFraction)
            }
        }
    }

    /// Set before layout settles to restore a saved position; consumed the
    /// next time the content size is reported.
    var pendingFraction: Double?
    var onPersist: ((Double) -> Void)?

    private let settings: PrompterSettings
    private var timerSub: AnyCancellable?
    private var lastTick: CFTimeInterval = 0
    private var resumeAfterScrub = false
    private var scrubSettleTask: Task<Void, Never>?

    init(settings: PrompterSettings) {
        self.settings = settings
    }

    var progressFraction: Double {
        maxOffset > 0 ? Double(offset / maxOffset) : 0
    }

    var elapsedSeconds: Double {
        settings.speed > 0 ? Double(offset) / settings.speed : 0
    }

    var remainingSeconds: Double {
        settings.speed > 0 ? Double(maxOffset - offset) / settings.speed : 0
    }

    // MARK: Lifecycle

    func start() {
        lastTick = CACurrentMediaTime()
        timerSub = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
    }

    func stop() {
        timerSub = nil
        scrubSettleTask?.cancel()
        scrubSettleTask = nil
        resumeAfterScrub = false
        isPlaying = false
    }

    func reset(fraction: Double) {
        offset = 0
        maxOffset = 0
        pendingFraction = fraction
        isPlaying = false
    }

    // MARK: Transport

    func togglePlay() {
        if !isPlaying, maxOffset > 0, offset >= maxOffset {
            offset = 0 // play again from the top when finished
        }
        isPlaying.toggle()
    }

    func restart() {
        offset = 0
    }

    func nudgeSpeed(_ delta: Double) {
        settings.speed = min(400, max(10, settings.speed + delta))
    }

    /// Manual scroll-wheel / trackpad scrub. Pauses the auto-scroll while the
    /// user has hold of the script and resumes a beat after they let go.
    func scrub(by delta: CGFloat) {
        scrubSettleTask?.cancel()
        if isPlaying {
            resumeAfterScrub = true
            isPlaying = false
        }
        offset = min(maxOffset, max(0, offset + delta))
        scrubSettleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 750_000_000)
            guard !Task.isCancelled, let self else { return }
            if self.resumeAfterScrub {
                self.resumeAfterScrub = false
                self.isPlaying = true
            } else {
                self.onPersist?(self.progressFraction)
            }
        }
    }

    /// Called by the views whenever the measured content length changes
    /// (text edits, window resize, mode flips).
    func setMaxOffset(_ value: CGFloat) {
        maxOffset = max(0, value)
        if let fraction = pendingFraction, maxOffset > 0 {
            offset = CGFloat(fraction) * maxOffset
            pendingFraction = nil
        } else {
            offset = min(offset, maxOffset)
        }
    }

    // MARK: Tick

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(now - lastTick, 0.1) // clamp hiccups so we never jump
        lastTick = now
        guard isPlaying else { return }
        offset = min(maxOffset, offset + CGFloat(settings.speed * dt))
        if maxOffset > 0, offset >= maxOffset {
            isPlaying = false // reached the end; didSet persists position
        }
    }
}
