import Foundation
import Observation

struct BrowserExtensionCommandSettingsRoute:
    Equatable,
    Sendable
{
    let extensionID: String?
    let commandID: String?

    init?(url: URL) {
        guard url.scheme?.lowercased() == "chrome",
            url.host?.lowercased() == "extensions"
        else {
            return nil
        }
        let path = url.path.lowercased()
        guard path == "/configurecommands" || path == "/shortcuts" else {
            return nil
        }
        let compositeCommand = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        )?.queryItems?.first(where: { $0.name == "command" })?.value
        guard let compositeCommand, compositeCommand.count > 33 else {
            extensionID = nil
            commandID = nil
            return
        }
        let identifierEnd = compositeCommand.index(
            compositeCommand.startIndex,
            offsetBy: 32
        )
        let identifier = String(compositeCommand[..<identifierEnd])
        guard
            identifier.unicodeScalars.allSatisfy({
                (0x61...0x70).contains($0.value)
            }),
            compositeCommand[identifierEnd] == "-"
        else {
            extensionID = nil
            commandID = nil
            return
        }
        let commandStart = compositeCommand.index(after: identifierEnd)
        let command = String(compositeCommand[commandStart...])
        extensionID = identifier
        commandID = command.isEmpty ? nil : command
    }
}
