import Foundation

/// Returns a human-readable countdown string from `from` to `to`.
/// - Returns `nil` when `from >= to` (i.e. the target date has passed).
func countdownString(from: Date = .now, to target: Date) -> String? {
    guard target > from else { return nil }
    let components = Calendar.current.dateComponents([.day, .hour, .minute, .second], from: from, to: target)
    let d = components.day ?? 0
    let h = components.hour ?? 0
    let m = components.minute ?? 0
    let s = components.second ?? 0
    return "\(d)d \(h)h \(m)m \(s)s"
}

// MARK: - Countdown Timer

/// Manages a 1-second countdown tick towards a target date.
/// Extracts the duplicated timer logic from HomeViewModel and RaceDetailViewModel.
@MainActor
final class CountdownTimer {
    var text: String = ""

    private var task: Task<Void, Never>?
    private var targetDateProvider: () -> Date?
    private var onExpired: (() -> Void)?

    /// - Parameters:
    ///   - targetDateProvider: Closure returning the target date (re-evaluated each tick).
    ///   - onExpired: Optional callback fired once when the countdown reaches zero.
    init(targetDateProvider: @escaping () -> Date?, onExpired: (() -> Void)? = nil) {
        self.targetDateProvider = targetDateProvider
        self.onExpired = onExpired
    }

    func start() {
        task?.cancel()
        tick() // Populate immediately so the UI never shows an empty string on first render.
        task = Task { [weak self] in
            while !Task.isCancelled, let self {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                self.tick()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func tick() {
        guard let target = targetDateProvider() else {
            text = ""
            return
        }
        if let countdown = countdownString(to: target) {
            text = countdown
        } else {
            text = ""
            onExpired?()
            stop()
        }
    }
}
