import Foundation

/// Private resources must never match an extension's web-accessible wildcards:
/// a website that could fetch this script could steal its clipboard capability.
enum BrowserExtensionClipboardCompatibility {
    static let resourcePrefix = "crest-webextension-clipboard"
    static let tokenResource = resourcePrefix + "-capability"

    static func script(token: String) -> String {
        // UUID-only tokens can safely be embedded in a JavaScript string.
        precondition(UUID(uuidString: token) != nil)
        return #"""
            (() => {
                if (typeof document === 'undefined' || !(globalThis.chrome ?? globalThis.browser)?.runtime?.id) return;
                const nativePrompt = globalThis.prompt.bind(globalThis);
                const nativeExec = Document.prototype.execCommand;
                const read = () => {
                    const value = nativePrompt('crest-extension-clipboard:\#(token)', '');
                    if (value === null) throw new DOMException('The clipboardRead permission is not granted.', 'NotAllowedError');
                    return value;
                };
                Object.defineProperty(Document.prototype, 'execCommand', {
                    configurable: true, writable: true,
                    value: function(command, ...args) {
                        if (String(command).toLowerCase() !== 'paste') return Reflect.apply(nativeExec, this, [command, ...args]);
                        const target = this.activeElement;
                        if (!(target instanceof HTMLTextAreaElement || target instanceof HTMLInputElement)
                            || target.disabled || target.readOnly || target.selectionStart === null) return false;
                        let text;
                        try { text = read(); } catch { return false; }
                        const data = new DataTransfer();
                        data.setData('text/plain', text);
                        const event = new ClipboardEvent('paste', {bubbles: true, cancelable: true, clipboardData: data});
                        if (!target.dispatchEvent(event)) return true;
                        const before = new InputEvent('beforeinput', {bubbles: true, cancelable: true, inputType: 'insertFromPaste', data: text});
                        if (!target.dispatchEvent(before)) return true;
                        target.setRangeText(text, target.selectionStart, target.selectionEnd, 'end');
                        target.dispatchEvent(new InputEvent('input', {bubbles: true, inputType: 'insertFromPaste', data: text}));
                        return true;
                    }
                });
                if (globalThis.navigator.clipboard) {
                    Object.defineProperty(globalThis.navigator.clipboard, 'readText', {
                        configurable: true, value: async () => read()
                    });
                }
            })();
            """#
    }

    static func protectResources(in manifest: inout [String: Any], resourceURL: URL) throws {
        guard let declarations = manifest["web_accessible_resources"] as? [Any] else { return }
        guard
            let enumerator = FileManager.default.enumerator(
                at: resourceURL, includingPropertiesForKeys: [.isRegularFileKey])
        else {
            throw CocoaError(.fileReadUnknown)
        }
        var publicPaths: [String] = []
        let rootPath = resourceURL.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            let absolutePath = url.resolvingSymlinksInPath().standardizedFileURL.path
            guard absolutePath.hasPrefix(rootPath) else { continue }
            let path = String(absolutePath.dropFirst(rootPath.count))
            guard !path.hasPrefix(resourcePrefix) else { continue }
            publicPaths.append(path)
        }
        func expand(_ patterns: [String]) -> [String] {
            let expressions = patterns.compactMap { pattern in
                try? NSRegularExpression(
                    pattern: "^"
                        + NSRegularExpression.escapedPattern(
                            for: pattern.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                        ).replacingOccurrences(of: "\\*", with: ".*") + "$")
            }
            return publicPaths.filter { path in
                expressions.contains { $0.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)) != nil }
            }.sorted()
        }
        if let patterns = declarations as? [String] {
            manifest["web_accessible_resources"] = expand(patterns)
        } else {
            manifest["web_accessible_resources"] = declarations.compactMap { value -> [String: Any]? in
                guard var entry = value as? [String: Any], let patterns = entry["resources"] as? [String] else {
                    return nil
                }
                entry["resources"] = expand(patterns)
                return entry
            }
        }
    }
}
