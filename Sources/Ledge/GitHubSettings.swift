import AppKit
import SwiftUI
import GitHubService
import LedgeSettings
import SettingsKit

/// Settings › GitHub (2026-10-22; polished the same day at the user's
/// call): the preview strip, an account card (or a welcome card before
/// connecting), then the moments in two groups.
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
        let wantsTokenBinding = Binding(get: { wantsToken }, set: { wantsToken = $0 })
        return Form {
            Section {
                PreviewStrip(director: director, height: PreviewStrip.shortHeight) { model.previewContent() }
                    .asPaneHeader()
            }
            Section {
                TimelineView(.periodic(from: .now, by: 2)) { _ in
                    if settings.githubConnected {
                        GitHubAccountCard(model: model, wantsToken: wantsTokenBinding)
                    } else {
                        GitHubWelcomeCard(model: model, wantsToken: wantsTokenBinding)
                    }
                }
                if model.githubNeedsToken || wantsToken || model.githubStatus == .signInAgain {
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
            } footer: {
                Text("While connected, Ledge asks api.github.com every minute, or every 20 seconds while something runs, and fetches people's pictures from GitHub's image server. Your token stays with gh or in your Keychain.")
            }
            Section {
                moment("Checks running", "A ring that fills check by check, and a clock.",
                       symbol: "circle.dotted", color: .systemYellow, \.githubChecksRunning, .githubRunning)
                moment("Checks finished", "Passed or failed, once for each commit.",
                       symbol: "checkmark.circle.fill", color: .systemGreen, \.githubChecksFinished, .githubChecks)
                moment("Reviews and comments", "Approvals, change requests and comments, bots included.",
                       symbol: "bubble.left.fill", color: .systemOrange, \.githubReviews, .githubReviews)
                moment("Merges and closes", "When someone else merges or closes one.",
                       symbol: "arrow.triangle.merge", color: .systemPurple, \.githubMerges, .githubMerges)
            } header: {
                Text("Your pull requests")
            }
            .opacity(settings.githubConnected ? 1 : 0.55)
            Section {
                moment("Review requests", "When someone asks for your review.",
                       symbol: "eye.fill", color: .systemBlue, \.githubReviewRequests, .githubRequests)
                moment("Your runs outside PRs", "Runs you start with a push, a tag or a deploy.",
                       symbol: "play.circle.fill", color: .systemGray, \.githubMyRuns, .githubRuns)
            } header: {
                Text("Around you")
            }
            .opacity(settings.githubConnected ? 1 : 0.55)
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

/// Before connecting (2026-10-22): what this is, and the two ways in.
struct GitHubWelcomeCard: View {
    let model: AppModel
    let wantsToken: Binding<Bool>

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color(white: 0.22)))
            Text("Your pull requests on the island")
                .font(.headline)
                .padding(.top, 2)
            Text("Checks as they run and finish, reviews, merges and review requests, across all your repos. Ledge asks GitHub only once you connect.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            HStack(spacing: 10) {
                Button("Connect with gh") { model.connectGitHub() }
                    .buttonStyle(.borderedProminent)
                Button("Use a token…") { wantsToken.wrappedValue = true }
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }
}

/// Once connected (2026-10-22): who, how, when last checked, and the
/// buttons; then the line of what is going on, or what is wrong.
struct GitHubAccountCard: View {
    let model: AppModel
    let wantsToken: Binding<Bool>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                picture
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                HStack(spacing: 8) {
                    if model.githubSource == .gh, model.githubStatus != .signInAgain, !wantsToken.wrappedValue {
                        Button("Use a token") { wantsToken.wrappedValue = true }
                    }
                    if model.githubNeedsToken || model.githubStatus == .signInAgain {
                        Button("Try again") { model.checkGitHubNow() }
                    } else if model.githubStatus != .checking {
                        Button("Check now") { model.checkGitHubNow() }
                    }
                    Button("Disconnect") { model.disconnectGitHub() }
                }
            }
            if case .ok = model.githubStatus, let stats = model.githubStats {
                HStack(spacing: 14) {
                    stat(stats.open, stats.open == 1 ? "open PR" : "open PRs", nil)
                    stat(stats.failing, "failing", .systemRed)
                    stat(stats.running, "running", .systemYellow)
                    stat(stats.waiting, "waiting for your review", .systemBlue)
                }
                .font(.callout)
                .padding(.leading, 46)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var picture: some View {
        if let image = model.githubAvatar.flatMap(NSImage.init(data:)) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(width: 34, height: 34)
                .clipShape(Circle())
        } else {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color(white: 0.22)))
        }
    }

    private func stat(_ value: Int, _ label: String, _ color: NSColor?) -> some View {
        HStack(spacing: 4) {
            Text("\(value)")
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(color.map { Color(nsColor: $0) } ?? .primary)
            Text(label)
                .foregroundStyle(.secondary)
        }
    }

    private var title: String {
        if model.githubNeedsToken { return "No GitHub login found" }
        switch model.githubStatus {
        case .off, .checking: return "Connecting…"
        case .signInAgain: return "Sign in again"
        case .ok: return model.githubLogin ?? "Connected"
        case .failed: return model.githubLogin ?? "Could not connect"
        case .rateLimited: return model.githubLogin ?? "GitHub asked Ledge to wait"
        }
    }

    /// How the login came, once known (2026-10-22).
    private var via: String? {
        switch model.githubSource {
        case .gh?: "through gh"
        case .keychain?: "with a token"
        case nil: nil
        }
    }

    private var subtitle: String {
        if model.githubNeedsToken { return "Log in with gh auth login in Terminal, or paste a token, then Try again." }
        var lines: [String] = []
        switch model.githubStatus {
        case .off, .checking:
            switch model.githubSource {
            case .gh?: lines.append("Using your gh login.")
            case .keychain?: lines.append("Using your token.")
            case nil: lines.append("Looking for your gh login.")
            }
        case .ok(let at):
            lines.append(via.map { "Connected \($0) · checked at \(time(at))" } ?? "Checked at \(time(at))")
        case .failed:
            lines.append(model.githubLogin == nil ? "Ledge tries again shortly." : "Could not reach GitHub just now. Ledge tries again shortly.")
        case .rateLimited(let until):
            lines.append(model.githubLogin == nil ? "Ledge asks again at \(time(until))." : "GitHub asked Ledge to wait until \(time(until)).")
        case .signInAgain:
            lines.append("GitHub no longer takes this login. Log in again with gh auth login, or paste a new token, then Try again.")
        }
        if model.githubHidesOrganisations {
            lines.append("Some organisations hide their PRs from this token; authorise it for them on GitHub.")
        }
        return lines.joined(separator: " ")
    }

    private func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
