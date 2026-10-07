import SwiftUI

/// The build at a glance over Settings: Crest's icon, its version and build,
/// and the engine version it runs pages in.
struct BrowserSettingsBuildSummary: View {
    let icon: Image
    let engine: String?
    private let build = BrowserAboutBuildInformation.current

    var body: some View {
        HStack(spacing: 10) {
            icon
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Crest Browser")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Group {
                    Text("Version \(build.version) (\(build.build))")
                    if let engine {
                        Text(engine)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settings-build-header")
    }
}
