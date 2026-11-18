import AppKit

struct ScriptResult: Sendable {
    let string: String?
    let data: Data?
}

/// Runs AppleScript off the main thread on a single serial queue.
final class ScriptRunner: Sendable {
    static let shared = ScriptRunner()
    private let queue = DispatchQueue(label: "dynamicisland.applescript", qos: .userInitiated)

    func run(_ source: String) async -> ScriptResult? {
        await withCheckedContinuation { continuation in
            queue.async {
                var error: NSDictionary?
                guard let descriptor = NSAppleScript(source: source)?.executeAndReturnError(&error) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: ScriptResult(string: descriptor.stringValue, data: descriptor.data))
            }
        }
    }
}
