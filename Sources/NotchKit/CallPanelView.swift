import AppKit
import SwiftUI

/// The call card (2026-10-22): the app and its mic, the call's clock and
/// the mute button on one row; "Not a call" at the foot. Two rows, so it
/// sits in the open island's fixed budget like the other cards.
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                reveal(app, order: 0)
                Spacer(minLength: 8)
                reveal(clock, order: 1)
                reveal(muteButton, order: 2)
            }
            HStack {
                if !data.canMute {
                    Text("This mic can't be muted from here")
                        .font(.system(size: 11))
                        .foregroundStyle(contentColor.opacity(0.5))
                }
                Spacer(minLength: 8)
                reveal(Button { emit(.hideCallApp) } label: {
                    Text("Not a call")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(contentColor.opacity(0.55))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain), order: 3)
            }
        }
        .padding(.horizontal, 4)
        .onAppear { revealed = true }
    }

    /// The app's icon and name, a click bringing it forward, over the mic.
    private var app: some View {
        Button {
            if let url = URL(string: "ledge://call") { emit(.open(url)) }
        } label: {
            HStack(spacing: 8) {
                if let icon = data.icon.flatMap(NSImage.init(data:)) {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 28, height: 28)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(data.appName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(contentColor)
                        .lineLimit(1)
                    if let mic = data.micName {
                        Text(mic)
                            .font(.system(size: 11))
                            .foregroundStyle(contentColor.opacity(0.55))
                            .lineLimit(1)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var clock: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(GitHubPanelView.clock(context.date.timeIntervalSince(data.since)))
                .font(.system(size: 28, weight: .semibold))
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
