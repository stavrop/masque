import SwiftUI
import AppKit

/// The About / welcome screen — shown on launch (toggleable) and from the menu.
struct WelcomeView: View {
    @AppStorage("masque.showWelcome") private var showAtStartup = true

    var body: some View {
        VStack(spacing: 16) {
            header

            Text("Create, search, and manage your Apple Hide My Email addresses without ever leaving the menu bar.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 8) {
                Button {
                    NSWorkspace.shared.open(Links.githubStar)
                } label: {
                    Label("Star it on GitHub", systemImage: "star.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    NSWorkspace.shared.open(Links.buyMeACoffee)
                } label: {
                    Label("Buy me a coffee", systemImage: "cup.and.saucer.fill")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .tint(.orange)
            }

            Text("Masque is free and open-source. If it saves you a few clicks, a ⭐️ on GitHub genuinely helps it reach other people — thank you!")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Text("Independent, unofficial tool — not affiliated with Apple. Talks to private iCloud endpoints that may change at any time.")
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 14) {
                Button("Privacy Policy") { NSWorkspace.shared.open(Links.privacy) }
                Button("Terms of Service") { NSWorkspace.shared.open(Links.terms) }
            }
            .buttonStyle(.link)
            .font(.caption2)

            HStack {
                Toggle("Show at startup", isOn: $showAtStartup)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                Spacer()
                Button("View on GitHub") { NSWorkspace.shared.open(Links.github) }
                    .buttonStyle(.link)
                    .font(.caption)
                Button("Get Started") { WelcomeWindowController.shared.close() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    private var header: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.65)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 84, height: 84)
                    .shadow(color: Color.accentColor.opacity(0.35), radius: 8, y: 4)
                Image(systemName: "envelope.badge.shield.half.filled")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(.white)
            }
            Text("Masque").font(.system(size: 22, weight: .bold))
            Text("Hide My Email, from your menu bar")
                .font(.subheadline).foregroundStyle(.secondary)
            Text("Version \(AppInfo.version) (\(AppInfo.build))")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.top, 6)
    }
}
