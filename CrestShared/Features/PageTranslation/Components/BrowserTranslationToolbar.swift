import SwiftUI

struct BrowserTranslationToolbar: View {
    let translation: BrowserPageTranslation
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.browserInteractionCapabilities) private var capabilities
    @State private var availableWidth: CGFloat = 0

    private var usesCompactControls: Bool {
        availableWidth < 560 || dynamicTypeSize.isAccessibilitySize
    }

    private var showsInlineStatus: Bool {
        availableWidth >= 900 && !dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        BrowserPageToolbarSurface(label: "Page Translation", identifier: "page-translation-toolbar") {
            VStack(alignment: .leading, spacing: 5) {
                toolbarRow(inlineStatus: showsInlineStatus)
                if !showsInlineStatus {
                    translationStatus
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, CrestSpacing.extraSmall)
                }
            }
            .font(.callout.weight(.medium))
        } background: {
            CrestSurfaceLayer(shape: Rectangle())
        }
        // Read only the externally proposed width. Nested ViewThatFits probes
        // repeatedly measured menus during floating-sidebar transitions and
        // exhausted the iOS scene-update watchdog. Each width now has one tree.
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            availableWidth = $0
        }
    }

    private func toolbarRow(inlineStatus: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "translate")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(translation.isTranslated ? CrestBrandTheme.accent : .primary)
                .frame(width: controlHeight, height: controlHeight)
                .accessibilityHidden(true)
            toolbarDivider
            if usesCompactControls {
                Menu {
                    BrowserTranslationLanguagePickers(translation: translation)
                        .crestMenuActionLabelStyle()
                } label: {
                    Image(systemName: "globe")
                        .frame(width: controlHeight, height: controlHeight)
                }
                .buttonStyle(BrowserTranslationToolbarControlStyle(isGrouped: true))
                .accessibilityLabel("Languages")
                .help("Languages")
            } else {
                HStack(spacing: CrestSpacing.extraSmall) {
                    languageMenu(isSource: true)
                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                    languageMenu(isSource: false)
                }
            }
            if inlineStatus && !translation.status.isEmpty {
                toolbarDivider
                translationStatus
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: CrestSpacing.small)
            primaryAction
            toolbarDivider
            Menu {
                BrowserTranslationActions(translation: translation)
                    .crestMenuActionLabelStyle()
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: controlHeight, height: controlHeight)
                    .contentShape(.rect)
            }
            .buttonStyle(BrowserTranslationToolbarControlStyle())
            .help("Translation Options")
            .accessibilityLabel("Translation Options")
            Button(action: translation.dismiss) {
                Image(systemName: "xmark")
                    .frame(width: controlHeight, height: controlHeight)
                    .contentShape(.rect)
            }
            .buttonStyle(BrowserTranslationToolbarControlStyle())
            .help("Dismiss Translation Bar")
            .accessibilityLabel("Dismiss Translation Bar")
            .accessibilityIdentifier("dismiss-translation-bar")
        }
        #if os(macOS)
            .menuStyle(.button)
            .menuIndicator(.hidden)
        #endif
    }

    private func languageMenu(isSource: Bool) -> some View {
        let name = isSource ? translation.languageName(translation.sourceID) : translation.targetName
        return Menu {
            if isSource {
                BrowserTranslationLanguagePickers(translation: translation).sourcePicker
                    .pickerStyle(.inline)
            } else {
                BrowserTranslationLanguagePickers(translation: translation).targetPicker
                    .pickerStyle(.inline)
            }
        } label: {
            HStack(spacing: 6) {
                BrowserTranslationLanguageIcon(identifier: isSource ? translation.sourceID : translation.targetID)
                    .accessibilityHidden(true)
                Text(name).lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, CrestSpacing.small)
            .frame(minHeight: controlHeight)
            .contentShape(.rect)
        }
        .buttonStyle(BrowserTranslationToolbarControlStyle(isGrouped: true))
        .disabled(translation.isWorking)
        .accessibilityLabel(isSource ? Text("From") : Text("To"))
        .accessibilityValue(name)
        .help(isSource ? Text("Translate From") : Text("Translate To"))
    }

    private var primaryAction: some View {
        Button {
            if translation.isWorking {
                translation.cancel()
            } else if translation.hasSelectedTranslation {
                translation.showOriginal()
            } else {
                translation.start()
            }
        } label: {
            Group {
                if usesCompactControls {
                    Image(systemName: actionSymbol)
                } else {
                    Label(actionTitle, systemImage: actionSymbol).fixedSize()
                }
            }
            .padding(.horizontal, usesCompactControls ? 0 : 9)
            .frame(minWidth: controlHeight, minHeight: controlHeight)
            .contentShape(.rect)
        }
        .buttonStyle(
            BrowserTranslationToolbarControlStyle(
                isGrouped: true,
                isProminent: !translation.isWorking && !translation.hasSelectedTranslation
            )
        )
        .disabled(!translation.isWorking && !translation.hasSelectedTranslation && !translation.canTranslate)
        .accessibilityLabel(actionTitle)
        .help(actionTitle)
    }

    private var actionTitle: String {
        if translation.isWorking { return String(localized: "Cancel Translation") }
        return translation.hasSelectedTranslation ? String(localized: "Show Original") : String(localized: "Translate")
    }

    private var actionSymbol: String {
        if translation.isWorking { return "stop.fill" }
        return translation.hasSelectedTranslation ? "arrow.uturn.backward" : "translate"
    }

    @ViewBuilder private var translationStatus: some View {
        if !translation.status.isEmpty {
            HStack(spacing: 6) {
                if translation.isWorking {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: translation.isTranslated ? "checkmark.circle.fill" : "info.circle")
                        .accessibilityHidden(true)
                }
                Text(translation.status)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
        }
    }

    private var toolbarDivider: some View {
        Divider().frame(height: 22).padding(.horizontal, CrestSpacing.extraExtraSmall).accessibilityHidden(true)
    }

    private var controlHeight: CGFloat { capabilities.minimumHitTarget }
}
