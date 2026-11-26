import SwiftUI
import AppKit
import iStatsCore

/// About: app icon and version, privacy statement, links, acknowledgements, and support tools.
struct AboutSettingsPage: View {
    @ObservedObject var coordinator: MetricsCoordinator

    @State private var didCopyDiagnostics = false

    static let repositoryURL = URL(string: "https://github.com/cubewin07/iStats")!
    static let issuesURL = URL(string: "https://github.com/cubewin07/iStats/issues")!

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "Version \(version) (\(build))"
    }

    private var appIcon: NSImage {
        NSApp?.applicationIconImage ?? NSImage(named: NSImage.applicationIconName) ?? NSImage()
    }

    var body: some View {
        Form {
            SwiftUI.Section {
                HStack(spacing: 16) {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 64, height: 64)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("iStats")
                            .font(.title2.weight(.bold))
                        Text(versionText)
                            .foregroundStyle(.secondary)
                        Text("A native macOS system monitor for the menu bar.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            }

            SwiftUI.Section {
                Text("Metrics stay in memory while iStats runs. Nothing is written to disk or sent over the network. Only your settings are saved.")
            } header: {
                Text("Privacy")
            }

            SwiftUI.Section("Links") {
                Link("Source code on GitHub", destination: Self.repositoryURL)
                Link("Report an issue", destination: Self.issuesURL)
            }

            SwiftUI.Section {
                Text("Inspired by iStat Menus from Bjango. Built with SwiftUI and AppKit using only Apple frameworks and SF Symbols.")
            } header: {
                Text("Acknowledgements")
            }

            SwiftUI.Section {
                LabeledContent("Diagnostics") {
                    HStack(spacing: 8) {
                        if didCopyDiagnostics {
                            Text("Copied")
                                .foregroundStyle(.secondary)
                        }
                        Button("Copy Diagnostics") { copyDiagnostics() }
                    }
                }

                LabeledContent("Welcome") {
                    Button("Show Welcome Again") {
                        NotificationCenter.default.post(name: SettingsSection.showWelcomeNotificationName, object: nil)
                    }
                }
            } header: {
                Text("Support")
            } footer: {
                Text("Diagnostics list your Mac model, macOS version, and which sensors are available. They never include metric values.")
            }
        }
        .formStyle(.grouped)
    }

    /// Reads the Mac model off the main thread, then copies the report.
    private func copyDiagnostics() {
        let availability = coordinator.categoryAvailability
        Task {
            let text = await Task.detached(priority: .utility) {
                DiagnosticsReport.current(availability: availability).render()
            }.value
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            didCopyDiagnostics = true
        }
    }
}
