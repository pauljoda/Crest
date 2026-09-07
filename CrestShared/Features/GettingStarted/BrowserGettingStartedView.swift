#if os(macOS)
    import SwiftUI

    struct BrowserGettingStartedView: View {
        let openURL: (URL) -> Void
        @State private var practice = BrowserGettingStartedPractice()
        @State private var chapter = 0
        @State private var lesson = 0
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            GeometryReader { geometry in
                let wide = geometry.size.width >= 820
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        masthead
                        chapterPicker
                        if chapter == 2 {
                            heading
                            BrowserGettingStartedExtensions(openURL: openURL)
                        } else {
                            practiceStage(wide: wide, height: max(560, min(680, geometry.size.height - 175)))
                        }
                        footer
                    }
                    .padding(geometry.size.width < 600 ? 20 : 30)
                    .frame(maxWidth: 1240)
                    .frame(maxWidth: .infinity)
                }
                .contentMargins(.trailing, 8, for: .scrollContent)
                .background(CrestBrandTheme.canvas)
            }
            .font(CrestTypography.sans(14))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: chapter)
        }

        /// One window keeps its identity as its position and width change between
        /// chapters. The sidebar can overhang in the tabs lesson; Split View brings
        /// the entire window back into the available canvas.
        private func practiceStage(wide: Bool, height: CGFloat) -> some View {
            GeometryReader { stage in
                let instructionsWidth: CGFloat = wide ? 280 : 220
                let windowX: CGFloat = chapter == 0 && wide ? instructionsWidth + 28 : 0
                let windowY: CGFloat = chapter == 0 && !wide ? 310 : 0
                ZStack(alignment: .topLeading) {
                    if chapter == 0 {
                        VStack(alignment: .leading, spacing: 24) {
                            heading
                            tabLesson
                        }
                        .frame(width: wide ? instructionsWidth : stage.size.width, alignment: .leading)
                        .frame(height: wide ? height : 290, alignment: .center)
                        .transition(.opacity)
                    }
                    BrowserGettingStartedPracticeWindow(practice: practice, showsSplit: chapter == 1)
                        .frame(
                            width: chapter == 0 && wide ? max(760, stage.size.width - windowX) : stage.size.width,
                            height: height
                        )
                        .offset(x: windowX, y: windowY)
                }
                .animation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.9), value: chapter)
            }
            .frame(height: height + (chapter == 0 && !wide ? 310 : 0))
            .clipped()
        }

        private var heading: some View {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(CrestTypography.display(34))
                Text(introduction).font(CrestTypography.sans(14)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        private var masthead: some View {
            HStack(spacing: 9) {
                CrestStartPageMark().frame(width: 24, height: 28)
                Text("Getting Started").font(CrestTypography.sans(13, weight: .semibold))
                Spacer()
                if chapter < 2 {
                    Button("Reset practice", systemImage: "arrow.counterclockwise") {
                        practice.reset()
                        lesson = 0
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
        }

        private var chapterPicker: some View {
            HStack(spacing: 8) {
                chapterButton("01", "Tabs & folders", index: 0)
                chapterButton("02", "Split View", index: 1)
                chapterButton("03", "Extensions", index: 2)
            }
        }

        private func chapterButton(_ number: String, _ title: LocalizedStringKey, index: Int) -> some View {
            Button {
                selectChapter(index)
            } label: {
                HStack(spacing: 7) {
                    Text(number).font(.caption.monospacedDigit()).opacity(0.6)
                    Text(title).font(CrestTypography.sans(13, weight: .semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 42)
                .foregroundStyle(chapter == index ? CrestBrandPalette.ink : .primary)
                .background(
                    chapter == index ? CrestBrandPalette.butter : .primary.opacity(0.04), in: .rect(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(chapter == index ? .isSelected : [])
        }

        private var title: LocalizedStringKey {
            switch chapter {
            case 0: "Tabs and folders"
            case 1: "Split View"
            default: "Extensions"
            }
        }

        private var introduction: LocalizedStringKey {
            switch chapter {
            case 0: "Pinned apps stay at the top, saved tabs above the line, and open tabs below it."
            case 1: "View pages side by side, change focus, and rearrange cards."
            default: "Install compatible Safari, Chrome, and Firefox extensions on Mac."
            }
        }

        private var tabLesson: some View {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("TRY IT").font(CrestTypography.sans(10, weight: .bold)).tracking(1.5).foregroundStyle(
                        .secondary)
                    Spacer()
                    Text("\(lesson + 1) / 4").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Text(lessonTitle).font(CrestTypography.display(25))
                Text(lessonDetail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                ViewThatFits(in: .horizontal) {
                    HStack {
                        lessonActions
                        Spacer()
                        nextLesson
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        lessonActions
                        nextLesson
                    }
                }
            }

        }

        private var lessonTitle: LocalizedStringKey {
            switch lesson {
            case 0: "Pin everyday apps"
            case 1: "Save a tab"
            case 2: "Create folders and nested folders"
            default: "Clear open tabs"
            }
        }

        private var lessonDetail: LocalizedStringKey {
            switch lesson {
            case 0:
                "Pinned tabs live at the top and are for your everyday apps. Right-click Gmail and choose Pin Tab, or use the button below."
            case 1:
                "Saved tabs stay below your pins until you delete them. Save A weekend away and watch it move above the line."
            case 2:
                "Folders can hold tabs and other folders. Add Weekends, then put Ideas inside it. You can also use folders below the line for open tabs."
            default:
                "Below the line are open tabs. They close automatically on your Space's cleanup schedule. Clear sends them to Archive in one click; your pinned and saved tabs stay put."
            }
        }

        @ViewBuilder private var lessonActions: some View {
            switch lesson {
            case 0:
                Button("Pin Gmail", systemImage: "pin.fill") { practice.browser.pinTab(practice.mailID) }
                    .buttonStyle(.crestPrimary(tint: CrestBrandPalette.butter))
            case 1:
                Button("Save this tab", systemImage: "bookmark.fill") { practice.browser.saveTab(practice.trailID) }
                    .buttonStyle(.crestPrimary(tint: CrestBrandPalette.butter))
            case 2:
                HStack {
                    Button("Add folder", systemImage: "folder.badge.plus") { practice.addFolder(nested: false) }
                    Button("Nest a folder", systemImage: "folder") { practice.addFolder(nested: true) }
                }.buttonStyle(.crestSecondary)
            default:
                Text("Use Clear on the line in the practice sidebar.")
                    .font(CrestTypography.sans(12)).foregroundStyle(.secondary)
            }
        }

        private var nextLesson: some View {
            Button(lesson == 3 ? "Try Split View" : "Next", systemImage: "arrow.right") {
                if lesson < 3 {
                    lesson += 1
                } else {
                    selectChapter(1)
                }
            }.buttonStyle(.crestSecondary)
        }

        private func selectChapter(_ index: Int) {
            if index == 1 && chapter != 1 { practice.reset() }
            chapter = index
        }

        private var footer: some View {
            HStack {
                Text("Practice changes affect only this example Space.").font(CrestTypography.sans(12)).foregroundStyle(
                    .secondary)
                Spacer()
                if chapter < 2 {
                    Button("Next chapter", systemImage: "arrow.right") { selectChapter(chapter + 1) }.buttonStyle(
                        .plain)
                } else {
                    Text("This guide stays in your Saved tabs.").font(CrestTypography.sans(12, weight: .semibold))
                }
            }
        }
    }

#endif
