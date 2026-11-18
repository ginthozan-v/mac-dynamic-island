import AppKit

@MainActor
@Observable
final class TimerService {
    private(set) var endDate: Date?
    private(set) var pausedRemaining: TimeInterval?
    private(set) var duration: TimeInterval = 0
    private(set) var justFinished = false

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var finishedTask: Task<Void, Never>?

    var isRunning: Bool { endDate != nil }
    var isPaused: Bool { pausedRemaining != nil }
    /// Running or paused: a timer exists that hasn't finished or been cancelled.
    var isActive: Bool { isRunning || isPaused }

    func remaining(at date: Date = .now) -> TimeInterval {
        if let pausedRemaining { return pausedRemaining }
        guard let endDate else { return 0 }
        return max(0, endDate.timeIntervalSince(date))
    }

    func progress(at date: Date = .now) -> Double {
        guard duration > 0 else { return 0 }
        return 1 - remaining(at: date) / duration
    }

    func start(minutes: Double) {
        justFinished = false
        pausedRemaining = nil
        duration = minutes * 60
        endDate = Date().addingTimeInterval(duration)
        schedule()
    }

    func pause() {
        guard let endDate else { return }
        pausedRemaining = max(0, endDate.timeIntervalSinceNow)
        self.endDate = nil
        timer?.invalidate()
        timer = nil
    }

    func resume() {
        guard let pausedRemaining else { return }
        self.pausedRemaining = nil
        endDate = Date().addingTimeInterval(pausedRemaining)
        schedule()
    }

    func add(seconds: TimeInterval) {
        if let pausedRemaining {
            self.pausedRemaining = pausedRemaining + seconds
        } else if let endDate {
            self.endDate = endDate.addingTimeInterval(seconds)
            schedule()
        } else {
            return
        }
        duration += seconds
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        endDate = nil
        pausedRemaining = nil
    }

    private func schedule() {
        timer?.invalidate()
        guard let endDate else { return }
        let t = Timer(fire: endDate, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func finish() {
        timer = nil
        endDate = nil
        justFinished = true
        NSSound(named: "Glass")?.play()
        finishedTask?.cancel()
        finishedTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.justFinished = false
        }
    }
}
