import SwiftData
import SwiftUI

/// 小小诗人简版 (P2): pick a theme → pick imagery words → write two or four lines with sentence
/// patterns and library examples → gentle checks, a title, and save to 我的诗集. Local only; no
/// online generation and no scoring. Same storybook shell as the other screens.
struct PoetWorkshopView: View {
    let destination: PoetWorkshopDestination

    private enum Step: Int, CaseIterable {
        case theme, words, write, finish
    }

    @Environment(AppSettings.self) private var settings
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var step: Step = .theme
    @State private var themeID: String?
    @State private var wordIDs: [String] = []
    @State private var lineCount = 2
    @State private var lines = Array(repeating: "", count: 4)
    @State private var title = ""
    @State private var editingID: UUID?
    @State private var savedTitle: String?
    @State private var loaded = false
    @FocusState private var focusedLine: Int?

    private let library = PoemLibrary.shared
    private let cardOverlap: CGFloat = 40
    private let maxWords = 4

    private var theme: PoetWorkshopTheme? { themeID.flatMap(PoetWorkshopContent.theme) }
    private var words: [ImageryWord] {
        wordIDs.compactMap { id in theme?.words.first { $0.id == id } }
    }
    private var activeLines: [String] { Array(lines.prefix(lineCount)) }
    private var check: PoetWorkshopCheck {
        PoetWorkshopCheck.check(lines: activeLines, words: words, normalizer: library.normalizer)
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let safeTop = geo.safeAreaInsets.top
            ScrollView {
                VStack(spacing: 0) {
                    scene(width: width, safeTop: safeTop)
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
                        if let savedTitle {
                            savedCard(savedTitle)
                        } else {
                            stepIndicator
                            switch step {
                            case .theme: themeStep
                            case .words: wordsStep
                            case .write: writeStep
                            case .finish: finishStep
                            }
                            navigation
                        }
                    }
                    .padding(.horizontal, width < 380 ? AppTheme.Spacing.pageCompact : AppTheme.Spacing.page)
                    .padding(.top, -cardOverlap)
                    .padding(.bottom, AppTheme.Spacing.pageBottom)
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                }
            }
            .ignoresSafeArea(edges: .top)
            .scrollDismissesKeyboard(.interactively)
        }
        .pageBackground()
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .onAppear(perform: load)
    }

    // MARK: Scene

    private func scene(width: CGFloat, safeTop: CGFloat) -> some View {
        let height = step == .theme && savedTitle == nil ? min(width * 0.6, 290) : min(width * 0.46, 220)
        return IllustratedSceneHeader(
            asset: ArtworkAsset.workshopScene,
            height: height,
            fade: 0.3,
            imageAlignment: .top,
            textScrim: AppTheme.Colors.backgroundCream.opacity(0.5),
            pendingDelivery: true
        ) {
            HStack(alignment: .top, spacing: 12) {
                Button {
                    focusedLine = nil
                    router.pop()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.bold))
                        .frame(width: 40, height: 40)
                        .background(AppTheme.Colors.surfacePaper.opacity(0.92), in: Circle())
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                }
                .accessibilityLabel(settings.t("返回", "返回"))
                VStack(alignment: .leading, spacing: 4) {
                    Text(settings.t("小小詩人", "小小诗人"))
                        .font(AppTheme.Typography.screenTitle)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Text(editingID == nil ? settings.t("用學過的意象，寫自己的詩", "用学过的意象，写自己的诗")
                                          : settings.t("修改我的作品", "修改我的作品"))
                        .font(.body.weight(.medium))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
            }
            .padding(.top, safeTop + 8)
            .padding(.horizontal, width < 380 ? AppTheme.Spacing.pageCompact : AppTheme.Spacing.page)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Steps

    private var stepIndicator: some View {
        let titles = [settings.t("選主題", "选主题"), settings.t("選意象", "选意象"),
                      settings.t("寫一寫", "写一写"), settings.t("起名字", "起名字")]
        return HStack(spacing: 6) {
            ForEach(Array(Step.allCases.enumerated()), id: \.offset) { index, item in
                let done = item.rawValue < step.rawValue
                let current = item == step
                HStack(spacing: 5) {
                    ZStack {
                        Circle()
                            .fill(done || current ? AppTheme.Colors.primaryGold : AppTheme.Colors.backgroundCream)
                            .overlay(Circle().strokeBorder(AppTheme.Colors.borderWarm, lineWidth: 1))
                        if done {
                            Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                        } else {
                            Text("\(index + 1)").font(.caption.weight(.bold))
                        }
                    }
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .frame(width: 22, height: 22)
                    if current {
                        Text(titles[index])
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                            .fixedSize()
                    }
                }
                if index < titles.count - 1 {
                    Rectangle().fill(AppTheme.Colors.borderWarm).frame(height: 1).frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .card(padding: 0, radius: AppTheme.CornerRadius.card)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(settings.t("第 \(step.rawValue + 1) 步，共 4 步：\(titles[step.rawValue])", "第 \(step.rawValue + 1) 步，共 4 步：\(titles[step.rawValue])"))
    }

    private var themeStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: settings.t("今天想寫什麼？", "今天想写什么？"),
                          subtitle: settings.t("選一個主題，貝貝會給你一些意象。", "选一个主题，贝贝会给你一些意象。"))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: AppTheme.Spacing.item)], spacing: AppTheme.Spacing.item) {
                ForEach(PoetWorkshopContent.themes) { item in
                    let selected = item.id == themeID
                    Button {
                        if themeID != item.id { wordIDs = [] }
                        themeID = item.id
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(settings.t(item.name))
                                    .font(.cardTitle)
                                    .foregroundStyle(AppTheme.Colors.textPrimary)
                                Spacer()
                                if selected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(AppTheme.Colors.accentOrange)
                                }
                            }
                            Text(item.words.prefix(4).map { settings.t($0.text) }.joined(separator: "・"))
                                .font(.footnote)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                                .lineLimit(1)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
                        .background(selected ? AppTheme.Colors.highlightCream : AppTheme.Colors.backgroundCream,
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(selected ? AppTheme.Colors.primaryGold : AppTheme.Colors.borderWarm, lineWidth: selected ? 2 : 1))
                        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .card(padding: AppTheme.Spacing.cardInset, radius: AppTheme.CornerRadius.container)
    }

    private var wordsStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let theme {
                HStack(alignment: .top, spacing: 10) {
                    MascotIllustration(size: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(settings.t(theme.invitation))
                            .font(.headline)
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(settings.t("選 1 到 \(maxWords) 個意象，放進你的詩裏。", "选 1 到 \(maxWords) 个意象，放进你的诗里。"))
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 10)], spacing: 10) {
                    ForEach(theme.words) { word in
                        let selected = wordIDs.contains(word.id)
                        CharacterDisc(text: settings.t(word.text), isSelected: selected, size: 56) {
                            if selected {
                                wordIDs.removeAll { $0 == word.id }
                            } else if wordIDs.count < maxWords {
                                wordIDs.append(word.id)
                            }
                        }
                        .opacity(!selected && wordIDs.count >= maxWords ? 0.45 : 1)
                    }
                }
                Text(wordIDs.isEmpty
                     ? settings.t("還沒選意象。", "还没选意象。")
                     : settings.t("已選：", "已选：") + words.map { settings.t($0.text) }.joined(separator: "、"))
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
        }
        .card(padding: AppTheme.Spacing.cardInset, radius: AppTheme.CornerRadius.container)
    }

    private var writeStep: some View {
        let examples = PoetWorkshopContent.exampleLines(for: words, in: examplePoems, normalizer: library.normalizer)
        return Group {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionHeader(title: settings.t("寫一寫", "写一写"))
                    PillPicker(selection: $lineCount, options: [(2, settings.t("兩句", "两句")), (4, settings.t("四句", "四句"))])
                        .frame(width: 150)
                }
                if !words.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(words) { word in
                            Chip(title: settings.t(word.text), isSelected: true, tint: AppTheme.Colors.primaryGold,
                                 selectedText: AppTheme.Colors.textPrimary)
                        }
                    }
                }
                VStack(spacing: 8) {
                    ForEach(0..<lineCount, id: \.self) { index in
                        HStack(spacing: 10) {
                            Text("\(index + 1)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                                .frame(width: 18)
                            TextField(settings.t("第 \(index + 1) 句", "第 \(index + 1) 句"), text: $lines[index])
                                .font(.title3)
                                .focused($focusedLine, equals: index)
                                .submitLabel(index + 1 < lineCount ? .next : .done)
                                .onSubmit { focusedLine = index + 1 < lineCount ? index + 1 : nil }
                                .autocorrectionDisabled()
                        }
                        .padding(.horizontal, 12)
                        .frame(minHeight: 48)
                        .background(AppTheme.Colors.backgroundCream, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(focusedLine == index ? AppTheme.Colors.primaryGold : AppTheme.Colors.borderWarm, lineWidth: 1.5))
                    }
                }
                Text(settings.t("每句五個字或七個字會更像詩，不過先寫出來最重要。", "每句五个字或七个字会更像诗，不过先写出来最重要。"))
                    .font(.footnote)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .card(padding: AppTheme.Spacing.cardInset, radius: AppTheme.CornerRadius.container)

            VStack(alignment: .leading, spacing: 10) {
                Label(settings.t("可以借用的句式", "可以借用的句式"), systemImage: "text.quote")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(PoetWorkshopContent.patterns, id: \.hans) { pattern in
                        Chip(title: settings.t(pattern))
                    }
                }
                if !examples.isEmpty {
                    Divider().overlay(AppTheme.Colors.borderWarm)
                    Label(settings.t("詩人是這樣寫的", "诗人是这样写的"), systemImage: "book")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                    ForEach(examples, id: \.line.id) { example in
                        Button {
                            focusedLine = nil
                            router.push(.poem(example.poem.id))
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(example.line.text(settings.script).withoutTrailingPunctuation)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(AppTheme.Colors.textPrimary)
                                    Text("《\(settings.t(example.poem.title))》" + example.poem.byline(settings))
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.Colors.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(AppTheme.Colors.accentOrange)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .card()
        }
    }

    private var finishStep: some View {
        let check = check
        return Group {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: settings.t("檢查一下", "检查一下"))
                checkRow(check.hasLines, settings.t("每一句都寫好了", "每一句都写好了"))
                checkRow(check.usesWord, settings.t("用到了選的意象", "用到了选的意象"))
                checkRow(check.evenLength, settings.t("每句字數一樣（五或七個字）", "每句字数一样（五或七个字）")
                         + (check.hasLines ? "　" + check.lengths.map(String.init).joined(separator: "／") : ""))
                Text(settings.t("後兩項只是提醒，不影響保存。", "后两项只是提醒，不影响保存。"))
                    .font(.footnote)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            .card()

            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: settings.t("給作品起個名字", "给作品起个名字"))
                TextField(PoetWorkshopCheck.suggestedTitle(from: activeLines, normalizer: library.normalizer)
                              .nilIfEmpty ?? settings.t("作品名", "作品名"), text: $title)
                    .font(.title3.weight(.semibold))
                    .padding(.horizontal, 14)
                    .frame(minHeight: 50)
                    .background(AppTheme.Colors.backgroundCream, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(AppTheme.Colors.borderWarm, lineWidth: 1.5))
                    .submitLabel(.done)
                VStack(spacing: 6) {
                    ForEach(0..<lineCount, id: \.self) { index in
                        Text(lines[index].isEmpty ? "……" : lines[index])
                            .font(.title3.weight(.medium))
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(AppTheme.Colors.surfacePaper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(AppTheme.Colors.borderWarm, lineWidth: 1))
                Button(action: save) {
                    Label(editingID == nil ? settings.t("收進我的詩集", "收进我的诗集") : settings.t("保存修改", "保存修改"),
                          systemImage: "books.vertical.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!check.canSave)
            }
            .card(padding: AppTheme.Spacing.cardInset, radius: AppTheme.CornerRadius.container)
        }
    }

    private func checkRow(_ ok: Bool, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(ok ? AppTheme.Colors.successGreen : AppTheme.Colors.textSecondary.opacity(0.6))
            Text(text)
                .font(.body)
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(ok ? settings.t("完成", "完成") : settings.t("未完成", "未完成"))
    }

    private func savedCard(_ savedTitle: String) -> some View {
        VStack(spacing: 12) {
            MascotIllustration(size: 100)
            Text(settings.t("《\(savedTitle)》已收進我的詩集", "《\(savedTitle)》已收进我的诗集"))
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .multilineTextAlignment(.center)
            VStack(spacing: 6) {
                ForEach(Array(activeLines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                }
            }
            .padding(.vertical, 6)
            Button {
                router.replaceTop(with: .myPoems)
            } label: {
                Label(settings.t("看我的詩集", "看我的诗集"), systemImage: "books.vertical")
            }
            .buttonStyle(PrimaryButtonStyle(showsChevron: true))
            Button {
                reset()
            } label: {
                Text(settings.t("再寫一首", "再写一首"))
            }
            .buttonStyle(SoftButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .card(padding: AppTheme.Spacing.cardInset, radius: AppTheme.CornerRadius.container)
    }

    // MARK: Navigation

    private var canAdvance: Bool {
        switch step {
        case .theme: themeID != nil
        case .words: !wordIDs.isEmpty
        case .write: check.hasLines
        case .finish: false
        }
    }

    private var navigation: some View {
        HStack(spacing: AppTheme.Spacing.item) {
            if step != .theme {
                Button {
                    focusedLine = nil
                    step = Step(rawValue: step.rawValue - 1) ?? .theme
                } label: {
                    Label(settings.t("上一步", "上一步"), systemImage: "chevron.left")
                }
                .buttonStyle(SoftButtonStyle())
                .frame(maxWidth: .infinity)
            }
            if step != .finish {
                Button {
                    focusedLine = nil
                    step = Step(rawValue: step.rawValue + 1) ?? .finish
                } label: {
                    Text(settings.t("下一步", "下一步"))
                }
                .buttonStyle(PrimaryButtonStyle(showsChevron: true))
                .disabled(!canAdvance)
            }
        }
    }

    // MARK: Data

    private var examplePoems: [Poem] {
        guard let preferred = theme?.libraryThemeID else { return library.poems }
        return library.poems(inTheme: preferred) + library.poems.filter { $0.theme != preferred }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        switch destination {
        case .new(let themeID):
            if let themeID, PoetWorkshopContent.theme(themeID) != nil {
                self.themeID = themeID
                step = .words
            }
        case .edit(let id):
            guard let draft = ProgressStore(context: context).draft(id) else { return }
            editingID = draft.id
            themeID = draft.themeID
            wordIDs = draft.wordIDs
            lineCount = PoetWorkshopContent.lineCounts.contains(draft.lines.count) ? draft.lines.count : 2
            for (index, line) in draft.lines.prefix(4).enumerated() { lines[index] = line }
            title = draft.title
            step = .write
        }
    }

    private func save() {
        guard let themeID else { return }
        focusedLine = nil
        let finalTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? PoetWorkshopCheck.suggestedTitle(from: activeLines, normalizer: library.normalizer).nilIfEmpty
            ?? settings.t("無題", "无题")
        let draft = ProgressStore(context: context).saveDraft(
            id: editingID, title: finalTitle, themeID: themeID, wordIDs: wordIDs,
            lines: activeLines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        editingID = draft.id
        savedTitle = finalTitle
    }

    private func reset() {
        step = .theme
        themeID = nil
        wordIDs = []
        lineCount = 2
        lines = Array(repeating: "", count: 4)
        title = ""
        editingID = nil
        savedTitle = nil
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
