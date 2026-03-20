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
