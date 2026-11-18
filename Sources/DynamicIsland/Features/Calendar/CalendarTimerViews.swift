import SwiftUI

// MARK: - Calendar card (native calendar control)

struct CalendarCard: View {
    let calendar: CalendarService
    @State private var selection = Date()

    var body: some View {
        HStack(spacing: 6) {
            TimelineView(.everyMinute) { context in
                summary(context.date)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.vertical, 4)

            NativeCalendarPicker(date: $selection)
                .frame(width: NativeCalendarPicker.naturalSize.width * NativeCalendarPicker.scale,
                       height: NativeCalendarPicker.naturalSize.height * NativeCalendarPicker.scale)
        }
        .onAppear { selection = Date() }
    }

    private func summary(_ now: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text("\(Calendar.current.component(.day, from: now))")
                    .font(DS.rounded(32, .bold))
                VStack(alignment: .leading, spacing: 0) {
                    Text(now.formatted(.dateTime.weekday(.wide)))
                        .font(DS.rounded(11, .bold))
                        .textCase(.uppercase)
                        .foregroundStyle(Color(red: 1, green: 0.27, blue: 0.23))
                    Text(now.formatted(.dateTime.month(.wide)))
                        .font(DS.rounded(11, .medium))
                        .foregroundStyle(DS.secondaryText)
                }
            }
            events
        }
    }

    @ViewBuilder
    private var events: some View {
        switch calendar.access {
        case .unknown:
            Button { calendar.requestAccess() } label: {
                Text("Show today's events")
                    .font(DS.rounded(11, .bold))
                    .foregroundStyle(Color(red: 0.55, green: 0.7, blue: 0.85))
            }
            .buttonStyle(.plain)
        case .denied:
            Text("Calendar access off")
                .font(DS.rounded(11, .medium))
                .foregroundStyle(DS.secondaryText)
        case .granted:
            if calendar.todayEvents.isEmpty {
                Text("Nothing else today")
                    .font(DS.rounded(11, .medium))
                    .foregroundStyle(DS.secondaryText)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(calendar.todayEvents.enumerated()), id: \.offset) { _, e in
                        HStack(spacing: 7) {
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(e.color)
                                .frame(width: 3, height: 22)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(e.title)
                                    .font(DS.rounded(11, .bold))
                                    .lineLimit(1)
                                Group {
                                    if e.isAllDay {
                                        Text("All-day")
                                    } else {
                                        Text(e.start, format: .dateTime.hour().minute())
                                    }
                                }
                                .font(DS.rounded(9.5, .medium).monospacedDigit())
                                .foregroundStyle(DS.secondaryText)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Apple's own month calendar (NSDatePicker, clock-and-calendar style), dark and borderless.
struct NativeCalendarPicker: NSViewRepresentable {
    @Binding var date: Date

    /// The control's fixed natural size, and how much we shrink it to fit the shorter island.
    static let naturalSize = CGSize(width: 139, height: 148)
    static let scale: CGFloat = 0.86

    func makeNSView(context: Context) -> ScaledPickerHost {
        let picker = FirstMouseDatePicker()
        picker.datePickerStyle = .clockAndCalendar
        picker.datePickerElements = .yearMonthDay
        picker.isBordered = false
        picker.isBezeled = false
        picker.drawsBackground = false
        picker.appearance = NSAppearance(named: .darkAqua)
        picker.dateValue = date
        picker.target = context.coordinator
        picker.action = #selector(Coordinator.changed(_:))
        return ScaledPickerHost(picker: picker, naturalSize: Self.naturalSize)
    }

    func updateNSView(_ host: ScaledPickerHost, context: Context) {
        context.coordinator.date = $date
        if host.picker.dateValue != date { host.picker.dateValue = date }
    }

    func makeCoordinator() -> Coordinator { Coordinator(date: $date) }

    @MainActor
    final class Coordinator: NSObject {
        var date: Binding<Date>
        init(date: Binding<Date>) { self.date = date }
        @objc func changed(_ sender: NSDatePicker) { date.wrappedValue = sender.dateValue }
    }
}

/// Shrinks the picker by giving it a smaller frame than its bounds: AppKit then draws it
/// scaled as vectors (crisp text), and click coordinates are converted automatically.
final class ScaledPickerHost: NSView {
    let picker: NSDatePicker
    private let naturalSize: CGSize

    init(picker: NSDatePicker, naturalSize: CGSize) {
        self.picker = picker
        self.naturalSize = naturalSize
        super.init(frame: .zero)
        addSubview(picker)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        picker.frame = bounds
        picker.setBoundsSize(naturalSize)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The island panel never becomes key, so the picker must react to the very first click.
private final class FirstMouseDatePicker: NSDatePicker {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct EventCountdownText: View {
    let calendar: CalendarService

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            if let e = calendar.nextEvent {
                let minutes = Int((e.start.timeIntervalSince(context.date) / 60).rounded(.up))
                if minutes <= 0 {
                    Text("now")
                } else if minutes < 60 {
                    Text("in \(minutes)m")
                } else {
                    Text("in \(minutes / 60)h \(minutes % 60)m")
                }
            }
        }
    }
}

struct TimerRing: View {
    let timer: TimerService
    var lineWidth: CGFloat = 3
    /// 30 fps sweep for the large ring; the tiny compact ring is fine at 4 Hz.
    var smooth = false

    var body: some View {
        TimelineView(smooth
                     ? .animation(minimumInterval: 1.0 / 30.0, paused: !timer.isRunning)
                     : .animation(minimumInterval: 0.25, paused: !timer.isRunning)) { context in
            let progress = timer.isActive ? timer.progress(at: context.date) : 0
            ZStack {
                Circle().stroke(.orange.opacity(0.2), lineWidth: lineWidth)
                Circle()
                    .trim(from: progress, to: 1)
                    .stroke(.orange, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .opacity(timer.isRunning ? 1 : (timer.isPaused ? 0.5 : 0.35))
            }
        }
    }
}

struct TimerCountdownText: View {
    let timer: TimerService

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            Text(formatDuration(timer.remaining(at: context.date)))
        }
    }
}

func formatDuration(_ t: TimeInterval) -> String {
    let s = Int(t.rounded(.up))
    return s >= 3600
        ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
        : String(format: "%d:%02d", s / 60, s % 60)
}

// MARK: - Timer tab

/// Timer page laid out like the music page: tile + title/subtitle on top, a progress
/// (or preset) row, and centred transport-style controls.
struct TimerTabView: View {
    let timer: TimerService
    @AppStorage("timer.customMinutes") private var customMinutes = 5

    private let presets = [1, 5, 10, 15, 25, 45, 60]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                TimerTile(timer: timer)
                VStack(alignment: .leading, spacing: 2) {
                    title
                        .font(DS.rounded(16, .bold).monospacedDigit())
                        .lineLimit(1)
                    subtitle
                        .font(DS.rounded(12, .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
                .frame(height: 66)
                Spacer(minLength: 0)
            }

            Group {
                if timer.isActive {
                    TimerProgressRow(timer: timer)
                } else {
                    presetRow
                }
            }
            .frame(height: 14)
            .padding(.top, 8)

            controls
                .frame(height: 30)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.smooth(duration: 0.3), value: timer.isActive)
        .animation(.smooth(duration: 0.3), value: timer.isPaused)
    }

    // MARK: Text

    @ViewBuilder
    private var title: some View {
        if timer.isActive {
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                Text(clock(timer.remaining(at: context.date)))
                    .contentTransition(.numericText(countsDown: true))
            }
        } else if timer.justFinished {
            Text("Time's up")
        } else {
            Text(durationLabel(customMinutes))
                .contentTransition(.numericText(value: Double(customMinutes)))
                .animation(.snappy, value: customMinutes)
        }
    }

    @ViewBuilder
    private var subtitle: some View {
        if timer.isPaused {
            Text("Paused")
        } else if timer.isRunning, let end = timer.endDate {
            Text("Ends at ") + Text(end, format: .dateTime.hour().minute())
        } else if timer.justFinished {
            Text("Timer finished")
        } else {
            Text("Ready")
        }
    }

    // MARK: Middle row

    /// Preset durations as plain text, styled like the progress row's time labels.
    private var presetRow: some View {
        HStack(spacing: 0) {
            ForEach(presets, id: \.self) { m in
                Button {
                    customMinutes = m
                } label: {
                    Text(m == 60 ? "1h" : "\(m)m")
                        .font(DS.rounded(13, customMinutes == m ? .bold : .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(customMinutes == m ? 1 : 0.45))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressScaleStyle())
            }
        }
        .animation(.easeOut(duration: 0.15), value: customMinutes)
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 30) {
            if timer.isActive {
                GlyphButton(icon: "stop.fill", size: 16) { timer.cancel() }
                    .frame(width: 30, height: 30)
                    .help("Cancel timer")
                GlyphButton(icon: timer.isPaused ? "play.fill" : "pause.fill", size: 21) {
                    timer.isPaused ? timer.resume() : timer.pause()
                }
                .frame(width: 34, height: 32)
                .contentTransition(.symbolEffect(.replace))
                GlyphButton(icon: "goforward.60", size: 17) { timer.add(seconds: 60) }
                    .frame(width: 30, height: 30)
                    .help("Add 1 minute")
            } else {
                GlyphButton(icon: "minus", size: 16) {
                    customMinutes = max(1, customMinutes - stepSize(down: true))
                }
                .frame(width: 30, height: 30)
                .help("Shorter")
                GlyphButton(icon: "play.fill", size: 21) { timer.start(minutes: Double(customMinutes)) }
                    .frame(width: 34, height: 32)
                    .help("Start \(durationLabel(customMinutes)) timer")
                GlyphButton(icon: "plus", size: 16) {
                    customMinutes = min(180, customMinutes + stepSize(down: false))
                }
                .frame(width: 30, height: 30)
                .help("Longer")
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Helpers

    /// 1-minute steps up to 10 min, 5-minute steps beyond.
    private func stepSize(down: Bool) -> Int {
        (down ? customMinutes > 10 : customMinutes >= 10) ? 5 : 1
    }

    private func durationLabel(_ minutes: Int) -> String {
        minutes >= 60
            ? (minutes % 60 == 0 ? "\(minutes / 60) hr" : "\(minutes / 60) hr \(minutes % 60) min")
            : "\(minutes) min"
    }
}

/// "04:59" / "1:04:59", matching the music page's time format.
func clock(_ t: TimeInterval) -> String {
    let s = Int(t.rounded(.up))
    return s >= 3600
        ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
        : String(format: "%02d:%02d", s / 60, s % 60)
}

/// Stand-in for the album cover: a dark tile with a white progress ring.
struct TimerTile: View {
    let timer: TimerService

    var body: some View {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
            .fill(.white.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(.white.opacity(0.06), lineWidth: 1)
            )
            .overlay {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !timer.isRunning)) { context in
                    let progress = timer.isActive ? timer.progress(at: context.date) : 0
                    ZStack {
                        Circle().stroke(.white.opacity(0.15), lineWidth: 4)
                        Circle()
                            .trim(from: progress, to: 1)
                            .stroke(.white.opacity(timer.isPaused ? 0.5 : 0.95),
                                    style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .opacity(timer.isActive ? 1 : 0)
                        Image(systemName: timer.justFinished ? "bell.fill" : "timer")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(timer.justFinished ? .orange : .white.opacity(0.85))
                            .symbolEffect(.bounce, value: timer.justFinished)
                    }
                    .frame(width: 42, height: 42)
                }
            }
            .frame(width: 66, height: 66)
    }
}

/// "00:01 ━━━━──────── -04:59", same look as the music progress row.
struct TimerProgressRow: View {
    let timer: TimerService

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let remaining = timer.remaining(at: context.date)
            let elapsed = max(0, timer.duration - remaining)
            HStack(spacing: 10) {
                Text(clock(elapsed.rounded(.down)))
                    .frame(width: 42, alignment: .leading)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.2))
                        Capsule().fill(.white.opacity(timer.isPaused ? 0.5 : 0.9))
                            .frame(width: max(4, geo.size.width * timer.progress(at: context.date)))
                    }
                    .frame(height: 4)
                    .frame(maxHeight: .infinity)
                }
                Text("-" + clock(remaining))
                    .frame(width: 48, alignment: .trailing)
            }
            .font(DS.rounded(13, .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.85))
        }
    }
}
