#if os(iOS)
    import SwiftUI

    /// A touch tour backed by the same isolated store and real sidebar as the Mac guide.
    struct BrowserMobileGettingStartedView: View {
        var showsCompactNavigation = false
        @State private var practice = BrowserGettingStartedPractice()
        @State private var lesson = 0
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            GeometryReader { geometry in
                let wide = geometry.size.width >= 700
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(spacing: 10) {
                            CrestStartPageMark().frame(width: 24, height: 28)
                            Text("Getting Started").font(.headline)
                            Spacer()
                            Button("Reset practice", systemImage: "arrow.counterclockwise") {
                                practice.reset()
                                lesson = 0
                            }
                            .labelStyle(.iconOnly)
                            .frame(width: 44, height: 44)
                        }
                        if wide {
                            HStack(alignment: .top, spacing: 28) {
                                tabLesson.frame(maxWidth: 300)
                                sidebar.frame(maxWidth: 380).frame(height: 510)
                            }
                        } else {
                            tabLesson
                            sidebar.frame(height: 470)
                        }
                        Text("Practice uses an example Space. Your tabs are unchanged.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Text("This guide stays in your Saved tabs.")
                            .font(.footnote).foregroundStyle(.secondary)
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "hand.draw")
                                .font(.title2)
                                .foregroundStyle(CrestBrandPalette.coral)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Return to your tabs").font(.headline)
                                Text(
                                    showsCompactNavigation
                                        ? "Swipe up on the URL bar or tap the tabs button on its right to return to your Space and start browsing."
                                        : "Select a tab in the sidebar, or choose New Tab to start browsing."
                                )
                                .font(.subheadline).foregroundStyle(.secondary)
                                Image(systemName: "square.on.square").font(.title3)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(CrestBrandTheme.surface, in: .rect(cornerRadius: 16))
                        .accessibilityIdentifier("getting-started-navigation-hint")
                    }
                    .padding(20)
                    .frame(maxWidth: 980)
                    .frame(maxWidth: .infinity)
                    .id("mobile-guide-top")
                }
                .background(CrestBrandTheme.canvas)
            }
            .animation(reduceMotion ? nil : CrestMotion.collection, value: practice.space.tabs)

        }

        private var sidebar: some View {
            BrowserGettingStartedPracticeSidebar(
                practice: practice,
                capabilities: BrowserInteractionCapabilities(
                    supportsHover: false, supportsTouch: true, pairsRowWithPromotedSurface: false)
            )
            .clipShape(.rect(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(CrestBrandTheme.line))
            .accessibilityIdentifier("getting-started-practice-sidebar")
        }

        private var tabLesson: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Tabs & folders").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(lesson + 1) / 4").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Text(lessonTitle).font(CrestTypography.display(28))
                Text(lessonDetail).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { lessonActions }
                    VStack(alignment: .leading, spacing: 12) { lessonActions }
                }
                HStack {
                    if lesson > 0 {
                        Button("Previous") { lesson -= 1 }.frame(minHeight: 44)
                    }
                    Spacer()
                    Button(lesson == 3 ? "Practice again" : "Next", systemImage: "arrow.right") {
                        if lesson < 3 {
                            lesson += 1
                        } else {
                            practice.reset()
                            lesson = 0
                        }
                    }
                    .frame(minHeight: 44)
                }
                .font(.subheadline.weight(.semibold))
            }
        }

        private var lessonTitle: LocalizedStringKey {
            switch lesson {
            case 0: "Pin everyday apps"
            case 1: "Save a tab"
            case 2: "Organize with folders"
            default: "Clear open tabs"
            }
        }

        private var lessonDetail: LocalizedStringKey {
            switch lesson {
            case 0: "Touch and hold Gmail, then choose Pin Tab. Pinned tabs stay at the top for your everyday apps."
            case 1:
                "Saved tabs stay above the line until you delete them. The minus button unloads a saved tab while keeping it in your sidebar."
            case 2:
                "Folders hold tabs and other folders. Add Weekends, then nest Ideas inside it. Folders also work below the line with open tabs."
            default:
                "Tabs below the line close automatically on your Space’s cleanup schedule. Open the Space’s ••• menu and choose Clean Up Current Tabs to archive them now. Pinned and saved tabs stay."
            }
        }

        @ViewBuilder private var lessonActions: some View {
            switch lesson {
            case 0:
                Button("Pin Gmail", systemImage: "pin.fill") { practice.browser.pinTab(practice.mailID) }
                    .buttonStyle(.crestPrimary(tint: CrestBrandPalette.butter))
            case 1:
                Button("Save A weekend away", systemImage: "bookmark") { practice.browser.saveTab(practice.trailID) }
                    .buttonStyle(.crestPrimary(tint: CrestBrandPalette.butter))
            case 2:
                Button("Add folder", systemImage: "folder.badge.plus") { practice.addFolder(nested: false) }
                    .buttonStyle(.crestSecondary)
                Button("Nest a folder", systemImage: "folder") { practice.addFolder(nested: true) }
                    .buttonStyle(.crestSecondary)
            default:
                Button("Clean Up Current Tabs", systemImage: "sparkles") {
                    _ = practice.tabActions.clearCurrentTabs()
                }
                .buttonStyle(.crestPrimary(tint: CrestBrandPalette.butter))
            }
        }

    }
#endif
