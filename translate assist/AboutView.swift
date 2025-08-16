import SwiftUI
import AppKit

struct AboutView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 48, height: 48)
                    .cornerRadius(8)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Translate Assist")
                        .font(.title3)
                        .bold()
                    Text("Version \(appVersion) (\(buildNumber))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Divider()

            Text("Attributions")
                .font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                Text("• Wiktionary — CC BY-SA 3.0")
                Text("• Tatoeba — CC BY 2.0")
                Text("• Google Cloud Translation — Machine Translation")
                Text("• SF Symbols — Apple")
            }
            .font(.callout)

            Divider()

            Text("Privacy & Notes")
                .font(.headline)
            Text("Keys are stored locally. Data remains on-device except requests to providers. No telemetry beyond local counters in MVP.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer()

            HStack(spacing: 12) {
                Link("Wiktionary", destination: URL(string: "https://www.wiktionary.org")!)
                Link("Tatoeba", destination: URL(string: "https://tatoeba.org")!)
                Link("Google Translate API", destination: URL(string: "https://cloud.google.com/translate")!)
                Spacer()
                Button("Close") { NSApp.keyWindow?.close() }
            }
        }
        .padding(16)
        .frame(minWidth: 420, minHeight: 320)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}

#Preview("About – Light") {
    AboutView()
}

#Preview("About – RTL Dark") {
    AboutView()
        .environment(\.layoutDirection, .rightToLeft)
        .preferredColorScheme(.dark)
}


