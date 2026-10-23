import AppKit
import SwiftUI

/// The call card (2026-10-22): the app and its state, the call's clock and
/// the mute button on one row; the mic and "Not a call" under a hairline.
/// Two rows, in a card only as tall as they are.
struct CallPanelView: View {
    let data: CallPanelData
    let contentColor: Color
    let reduceMotion: Bool
    let emit: (NotchIntent) -> Void

    /// Spelled-out `State`, as elsewhere here.
    private var _revealed: State<Bool> = State(initialValue: false)
    private var revealed: Bool {
        get { _revealed.wrappedValue }
        nonmutating set { _revealed.wrappedValue = newValue }
    }

    init(data: CallPanelData, contentColor: Color, reduceMotion: Bool, emit: @escaping (NotchIntent) -> Void) {
        self.data = data
        self.contentColor = contentColor
        self.reduceMotion = reduceMotion
        self.emit = emit
    }

    private func reveal<V: View>(_ view: V, order: Int) -> some View {
        view
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed ? 0 : 3)
            .animation(
                reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 1.0).delay(Double(order) * 0.022),
                value: revealed
            )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                reveal(app, order: 0)
                Spacer(minLength: 8)
                reveal(clock, order: 1)
                reveal(muteButton, order: 2)
            }
            .frame(height: 44)
            Rectangle()
                .fill(contentColor.opacity(0.1))
                .frame(height: 1)
            HStack(spacing: 4) {
                reveal(micLine, order: 3)
                Spacer(minLength: 8)
                reveal(Button { emit(.hideCallApp) } label: {
                    Text("Not a call")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(contentColor.opacity(0.55))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain), order: 4)
            }
            .frame(height: 14)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .onAppear { revealed = true }
    }

    /// The app's icon and name, a click bringing it forward, over the
    /// call's state in a word: the card may speak where the ears don't.
    private var app: some View {
        Button {
            if let url = URL(string: "ledge://call") { emit(.open(url)) }
        } label: {
            HStack(spacing: 9) {
                if let icon = data.icon.flatMap(NSImage.init(data:)) {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 30, height: 30)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(data.meetingTitle ?? data.appName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(contentColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    status
                        .font(.system(size: 11, weight: .medium))
                        .contentTransition(.opacity)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .snappy, value: data.isMuted)
    }

    /// The call's state in a word, or a meeting's time left (2026-10-22):
    /// "12m left", "+3m" in red once over, "Muted · " in red before either.
    @ViewBuilder
    private var status: some View {
        let red = Color(nsColor: .systemRed)
        let quiet = contentColor.opacity(0.55)
        if let end = data.meetingEnd {
            TimelineView(.periodic(from: data.since, by: 1)) { context in
                let left = CallMeetingText.timeLeft(end: end, now: context.date)
                HStack(spacing: 0) {
                    if data.isMuted { Text(data.mutedInMeet ? "Muted in Meet · " : "Muted · ").foregroundStyle(red) }
                    Text(left.text).foregroundStyle(left.isOver ? red : quiet)
                }
                .lineLimit(1)
            }
        } else {
            Text(data.isMuted ? (data.mutedInMeet ? "Muted in Meet" : "Muted") : "On a call")
                .foregroundStyle(data.isMuted ? red : quiet)
        }
    }

    /// The camera while it is on, then the first that applies: why the
    /// button can't mute, the next meeting, the mic in use (2026-10-22).
    private var micLine: some View {
        HStack(spacing: 6) {
            if data.isCameraOn {
                Image(systemName: "video.fill")
                    .font(.system(size: 9, weight: .medium))
            }
            if !data.canMute {
                Text("This mic can't be muted from here")
                    .font(.system(size: 11))
                    .lineLimit(1)
            } else if let next = data.nextMeeting {
                Text("Next: \(next)")
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else if let mic = data.micName {
                HStack(spacing: 4) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 9, weight: .medium))
                    Text(mic)
                        .font(.system(size: 11))
                        .lineLimit(1)
                }
            }
        }
        .foregroundStyle(contentColor.opacity(0.55))
    }

    /// Ticks on the call's own whole seconds, so it turns over when the
    /// call does rather than when the card opened.
    private var clock: some View {
        TimelineView(.periodic(from: data.since, by: 1)) { context in
            Text(GitHubPanelView.clock(context.date.timeIntervalSince(data.since)))
                .font(.system(size: 26, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Color(nsColor: .systemGreen))
                .contentTransition(.numericText())
        }
    }

    private var muteButton: some View {
        Button { emit(.toggleMute) } label: {
            Image(systemName: data.isMuted ? "mic.slash.fill" : "mic.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(contentColor)
                .frame(width: 44, height: 44)
                .background(Circle().fill(data.isMuted ? Color(nsColor: .systemRed) : contentColor.opacity(0.15)))
                .contentTransition(.symbolEffect(.replace.downUp))
        }
        .buttonStyle(.plain)
        .disabled(!data.canMute)
        .opacity(data.canMute ? 1 : 0.4)
        .animation(reduceMotion ? nil : .snappy, value: data.isMuted)
    }
}
