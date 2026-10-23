import AppKit
import SwiftUI
import AgentService
import LedgeSettings
import SettingsKit

/// Settings › Agents (2026-10-23): the preview strip, the switch that puts
/// Ledge's hooks into Claude Code's settings and the line saying whether it
/// is listening, then the moments the island tells.
struct AgentSettings: View {
    let settings: AppSettings
    let model: AppModel
    private var _director: State<PreviewDirector>
    private var director: PreviewDirector { _director.wrappedValue }

    private static let orange = Color(red: AgentNotice.orange.red, green: AgentNotice.orange.green, blue: AgentNotice.orange.blue)

    init(settings: AppSettings, model: AppModel) {
        self.settings = settings
        self.model = model
        _director = State(initialValue: PreviewDirector(
            scenes: [.agentWaiting, .agentWorking, .agentFinished, .agentFailed],
            isOn: { $0.isOn(in: settings) }
        ))
    }

    var body: some View {
        Form {
            Section {
                PreviewStrip(director: director, height: PreviewStrip.shortHeight) { model.previewContent() }
                    .asPaneHeader()
            }
            Section {
                SettingsRow("Show Claude Code sessions",
                            detail: "Adds Ledge's hooks to ~/.claude/settings.json. Switching off takes them out.",
                            symbol: "asterisk", color: Self.orange) {
                    Toggle("Show Claude Code sessions", isOn: Binding(
                        get: { settings.agentsEnabled },
                        set: { settings.agentsEnabled = $0 }
                    ))
                    .labelsHidden()
                }
                // Switched off, hooks that would not come out stay a problem (2026-10-23).
                if settings.agentsEnabled || model.agentsHooksLeftBehind {
                    // Inside a timeline: the model is not observable.
                    TimelineView(.periodic(from: .now, by: 2)) { context in
                        status(model.agentsStatus, now: context.date)
                    }
                }
            } footer: {
                Text("Each hook runs a small helper that tells Ledge what happened, over a socket only you can use. Nothing leaves this Mac, and Claude never waits for Ledge.")
            }
            Section {
                moment("Waiting for you", "Permission prompts, questions and plans to approve.",
                       symbol: "hand.raised.fill", color: .systemYellow, \.agentWaiting, .agentWaiting)
                moment("Working", "A turning asterisk and a clock while a session works. Under music.",
                       symbol: "asterisk", color: nil, \.agentWorking, .agentWorking)
                moment("Finished its turn", "Done, and how long it took.",
                       symbol: "checkmark.circle.fill", color: .systemGreen, \.agentFinished, .agentFinished)
                moment("Failed", "A turn that ended on an error.",
                       symbol: "exclamationmark.triangle.fill", color: .systemRed, \.agentFailed, .agentFailed)
            } header: {
                Text("Moments")
            }
            .opacity(settings.agentsEnabled ? 1 : 0.55)
        }
    }

    @ViewBuilder private func status(_ status: AgentMonitor.Status, now: Date) -> some View {
        switch status {
        case .off:
            EmptyView()
        case .ready(let lastHeard):
            Text(readyLine(lastHeard, now: now))
                .font(.callout)
                .foregroundStyle(.secondary)
        case .problem(let text):
            HStack {
                Text(text)
                    .font(.callout)
                    .foregroundStyle(Color(nsColor: .systemRed))
                Spacer(minLength: 8)
                Button("Repair") { model.repairAgents() }
            }
        }
    }

    private func readyLine(_ lastHeard: Date?, now: Date) -> String {
        let hooks = "Hooks in ~/.claude/settings.json"
        guard let lastHeard else { return "\(hooks) · Nothing heard yet: it starts with a session's next step" }
        let ago = RelativeDateTimeFormatter()
        ago.unitsStyle = .abbreviated
        return "\(hooks) · Last heard from a session \(ago.localizedString(for: lastHeard, relativeTo: now))"
    }

    /// `color` nil is Claude's orange.
    private func moment(_ title: String, _ detail: String, symbol: String, color: NSColor?,
                        _ keyPath: ReferenceWritableKeyPath<AppSettings, Bool>, _ scene: PreviewScene) -> some View {
        SettingsRow(title, detail: detail, symbol: symbol, color: color.map { Color(nsColor: $0) } ?? Self.orange,
                    scene: scene, director: director) {
            Toggle(title, isOn: playing(keyPath, scene, settings: settings, director: director))
                .labelsHidden()
        }
    }
}
