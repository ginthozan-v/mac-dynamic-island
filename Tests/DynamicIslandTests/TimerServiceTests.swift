import Foundation
import Testing
@testable import DynamicIsland

@MainActor
@Suite("Timer")
struct TimerServiceTests {
    @Test func startsWithFullDuration() {
        let timer = TimerService()
        timer.start(minutes: 1)
        #expect(timer.isRunning)
        #expect(timer.isActive)
        #expect(!timer.isPaused)
        #expect(abs(timer.remaining() - 60) < 1)
        #expect(timer.progress() < 0.05)
        timer.cancel()
    }

    @Test func pauseFreezesRemainingTime() {
        let timer = TimerService()
        timer.start(minutes: 2)
        timer.pause()
        #expect(timer.isPaused)
        #expect(!timer.isRunning)
        #expect(timer.isActive)
        let frozen = timer.remaining()
        #expect(timer.remaining(at: .now.addingTimeInterval(30)) == frozen)
        timer.cancel()
    }

    @Test func resumeContinuesFromPausedTime() {
        let timer = TimerService()
        timer.start(minutes: 2)
        timer.pause()
        let paused = timer.remaining()
        timer.resume()
        #expect(timer.isRunning)
        #expect(abs(timer.remaining() - paused) < 1)
        timer.cancel()
    }

    @Test func addingTimeExtendsRunningAndPausedTimers() {
        let timer = TimerService()
        timer.start(minutes: 1)
        timer.add(seconds: 60)
        #expect(abs(timer.remaining() - 120) < 1)
        #expect(timer.duration == 120)

        timer.pause()
        timer.add(seconds: 30)
        #expect(abs(timer.remaining() - 150) < 1)
        timer.cancel()
    }

    @Test func cancelClearsEverything() {
        let timer = TimerService()
        timer.start(minutes: 5)
        timer.cancel()
        #expect(!timer.isActive)
        #expect(timer.remaining() == 0)
    }

    @Test func addingTimeWithoutATimerDoesNothing() {
        let timer = TimerService()
        timer.add(seconds: 60)
        #expect(!timer.isActive)
        #expect(timer.duration == 0)
    }
}

@Suite("Time formatting")
struct ClockFormattingTests {
    @Test(arguments: [
        (0.0, "00:00"), (59.0, "00:59"), (61.2, "01:02"), (600.0, "10:00"), (3599.0, "59:59"), (3600.0, "1:00:00"),
    ])
    func formatsLikeTheMusicPage(seconds: Double, expected: String) {
        #expect(clock(seconds) == expected)
    }
}
