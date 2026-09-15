import SwiftUI

struct BrowserSystemPermissionRow: View {
    let permission: BrowserSystemPermission
    let status: BrowserSystemPermissionStatus
    let error: String?
    let isWorking: Bool
    let spaceName: String?
    let request: () -> Void
    let openSettings: () -> Void
    let chooseFolder: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: permission.symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(permission.tint)
                .frame(width: 32, height: 32)
                .background(permission.tint.opacity(0.12), in: .rect(cornerRadius: 8))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(permission.title).font(.headline)
                Text(description).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = status.detail, permission != .files || spaceName != nil {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let error {
                    Text(error).font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Label(status.state.title, systemImage: status.state.symbol)
                .font(.callout.weight(.medium))
                .foregroundStyle(status.state.tint)
                .accessibilityLabel("\(String(localized: permission.title)): \(String(localized: status.state.title))")
                .frame(width: 130, alignment: .leading)
            HStack {
                Spacer(minLength: 0)
                if isWorking {
                    ProgressView().controlSize(.small)
                } else if permission == .files, spaceName != nil {
                    Menu("Manage…") {
                        Button("Check Access", action: request)
                        Button("Choose Folder…", action: chooseFolder)
                        Button("System Settings…", action: openSettings)
                    }
                    .fixedSize()
                } else {
                    primaryAction
                }
            }
            .frame(width: 120)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("system-permission-\(permission.rawValue)")
    }

    private var description: String {
        guard permission == .files else { return String(localized: permission.explanation) }
        guard let spaceName else { return String(localized: "Select an unlocked Space to check its download folder.") }
        return String(
            localized: "Checks the download folder for \(spaceName). Other files are approved when you choose them.")
    }

    @ViewBuilder private var primaryAction: some View {
        switch status.state {
        case .notRequested:
            if error != nil {
                Button("Open Settings", action: openSettings)
            } else {
                Button("Allow…", action: request).buttonStyle(.borderedProminent)
            }
        case .notChecked:
            Button("Check Access", action: request)
        case .blocked, .restricted:
            Button("Open Settings", action: openSettings)
        case .allowed:
            Button(
                permission == .files ? "Check Again" : "Settings…",
                action: permission == .files ? request : openSettings)
        case .checking, .unavailable, .chooseEachTime:
            EmptyView()
        }
    }
}
