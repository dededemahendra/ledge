import AppKit
import SwiftUI
import GitHubService
import LedgeSettings
import SettingsKit

/// Settings › GitHub (2026-10-22): the connection, then one switch for each
/// moment the island tells, with the preview strip.
struct GitHubSettings: View {
    let settings: AppSettings
    let model: AppModel
    private var _director: State<PreviewDirector>
    private var director: PreviewDirector { _director.wrappedValue }
    private var _token: State<String>
    private var token: String {
        get { _token.wrappedValue }
        nonmutating set { _token.wrappedValue = newValue }
    }
    private var _wantsToken: State<Bool>
    private var wantsToken: Bool {
        get { _wantsToken.wrappedValue }
        nonmutating set { _wantsToken.wrappedValue = newValue }
    }

    init(settings: AppSettings, model: AppModel) {
        self.settings = settings
        self.model = model
        _director = State(initialValue: PreviewDirector(
            scenes: [.githubRunning, .githubChecks, .githubReviews, .githubMerges, .githubRequests, .githubRuns],
            isOn: { $0.isOn(in: settings) }
        ))
        _token = State(initialValue: "")
        _wantsToken = State(initialValue: false)
    }

    var body: some View {
        Form {
            Section {
                PreviewStrip(director: director, height: PreviewStrip.shortHeight) { model.previewContent() }
                    .asPaneHeader()
            }
            Section {
                TimelineView(.periodic(from: .now, by: 2)) { _ in
                    GitHubConnectionRow(settings: settings, model: model, wantsToken: Binding(
                        get: { wantsToken }, set: { wantsToken = $0 }
                    ))
                }
                if model.githubNeedsToken || wantsToken {
                    SettingsRow("Token", detail: "A token with the repo and read:org scopes, from github.com › Settings › Developer settings.",
                                symbol: "key.fill", color: Color(nsColor: .systemYellow)) {
                        HStack(spacing: 8) {
                            SecureField("Token", text: Binding(get: { token }, set: { token = $0 }))
                                .labelsHidden()
                                .frame(width: 180)
                            Button("Save") {
                                model.saveGitHubToken(token)
                                token = ""
                                wantsToken = false
                            }
                            .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            } header: {
                Text("Connection")
            } footer: {
                Text("While connected, Ledge asks api.github.com every minute, or every 20 seconds while something runs. Your token stays with gh or in your Keychain.")
            }
            Section {
                moment("Checks running", "An amber ring and a clock while checks run on your PRs.",
                       symbol: "circle.dotted", color: .systemYellow, \.githubChecksRunning, .githubRunning)
                moment("Checks finished", "Passed or failed, once for each commit.",
                       symbol: "checkmark.circle.fill", color: .systemGreen, \.githubChecksFinished, .githubChecks)
                moment("Reviews and comments", "Approvals, change requests and comments on your PRs, bots included.",
                       symbol: "bubble.left.fill", color: .systemOrange, \.githubReviews, .githubReviews)
                moment("Merges and closes", "When someone else merges or closes one of your PRs.",
                       symbol: "arrow.triangle.merge", color: .systemPurple, \.githubMerges, .githubMerges)
                moment("Review requests", "When someone asks for your review.",
                       symbol: "eye.fill", color: .systemBlue, \.githubReviewRequests, .githubRequests)
                moment("Your runs outside PRs", "Workflow runs you start with a push, a tag or a deploy.",
                       symbol: "play.circle.fill", color: .systemGray, \.githubMyRuns, .githubRuns)
            } header: {
                Text("Tell me when")
            }
        }
    }

    private func moment(_ title: String, _ detail: String, symbol: String, color: NSColor,
                        _ keyPath: ReferenceWritableKeyPath<AppSettings, Bool>, _ scene: PreviewScene) -> some View {
        SettingsRow(title, detail: detail, symbol: symbol, color: Color(nsColor: color), scene: scene, director: director) {
            Toggle(title, isOn: playing(keyPath, scene, settings: settings, director: director))
                .labelsHidden()
        }
    }
}

/// What the connection is doing, and the buttons for it.
struct GitHubConnectionRow: View {
    let settings: AppSettings
    let model: AppModel
    let wantsToken: Binding<Bool>

    var body: some View {
        SettingsRow(title, detail: detail, symbol: "arrow.triangle.branch", color: Color(white: 0.2)) {
            HStack(spacing: 8) {
                if !settings.githubConnected {
                    Button("Use a token") { wantsToken.wrappedValue = true }
                    Button("Connect") { model.connectGitHub() }
                } else {
                    if model.githubNeedsToken || model.githubStatus == .signInAgain {
                        Button("Try again") { model.checkGitHubNow() }
                    } else if model.githubStatus != .checking {
                        Button("Check now") { model.checkGitHubNow() }
                    }
                    Button("Disconnect") { model.disconnectGitHub() }
                }
            }
        }
    }

    private var title: String {
        guard settings.githubConnected else { return "Not connected" }
        if model.githubNeedsToken { return "No GitHub login found" }
        switch model.githubStatus {
        case .off, .checking:
            return "Connecting…"
        case .signInAgain:
            return "Sign in again"
        case .ok, .failed, .rateLimited:
            let via = model.githubSource == .gh ? "from gh" : "with a token"
            return model.githubLogin.map { "Connected as \($0) (\(via))" } ?? "Connected (\(via))"
        }
    }

    private var detail: String? {
        guard settings.githubConnected else { return "Ledge uses your gh login, or a token you paste here." }
        if model.githubNeedsToken { return "Log in with gh auth login in Terminal, or paste a token, then Try again." }
        var lines: [String] = []
        switch model.githubStatus {
        case .ok(let at): lines.append("Last checked at \(time(at)).")
        case .failed: lines.append("Could not reach GitHub just now. Ledge tries again shortly.")
        case .rateLimited(let until): lines.append("GitHub asked Ledge to wait until \(time(until)).")
        case .signInAgain: lines.append("GitHub no longer takes this login. Log in again with gh auth login, or paste a new token, then Try again.")
        case .off, .checking: break
        }
        if model.githubHidesOrganisations {
            lines.append("Some organisations hide their PRs from this token; authorise it for them on GitHub.")
        }
        return lines.isEmpty ? nil : lines.joined(separator: " ")
    }

    private func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
