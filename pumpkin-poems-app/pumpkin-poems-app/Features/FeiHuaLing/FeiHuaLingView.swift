import SwiftData
import SwiftUI

/// 单人飞花令 (P1). Entry mode picks from four lines; challenge mode types lines from memory with
/// first-character hints and no timer. Scope is the built-in library, and lines outside it are
/// shown as "暂未收录", never as wrong. Styled like the main screens: a scene on top, warm paper
/// below, gold for the action and the chosen character.
struct FeiHuaLingView: View {
    private enum Phase {
        case setup
        case entry(rounds: [FeiHuaLingEngine.Round], index: Int, picked: Int?, score: Int)
        case challenge
        case finished(score: Int, previousBest: Int)

        var isPlaying: Bool {
            switch self {
            case .entry, .challenge: true
            default: false
            }
        }
    }

    @Environment(AppSettings.self) private var settings
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query private var records: [GameRecord]

    @State private var character: LocalizedText
    @State private var mode: FeiHuaLingMode = .entry
    @State private var phase: Phase = .setup
    @State private var engine: FeiHuaLingEngine
    @State private var input = ""
    @State private var verdict: FeiHuaLingEngine.Verdict?
    @State private var hint: String?
    @FocusState private var inputFocused: Bool

    private let library = PoemLibrary.shared
    /// How far the first card rides up over the scene's fade.
    private let cardOverlap: CGFloat = 40

    init(initialCharacter: String?) {
        let library = PoemLibrary.shared
        let character = library.feiHuaLingCharacters.first { $0.hans == initialCharacter }
            ?? library.feiHuaLingCharacters[0]
        _character = State(initialValue: character)
        _engine = State(initialValue: FeiHuaLingEngine(character: character, poems: library.poems, normalizer: library.normalizer))
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let safeTop = geo.safeAreaInsets.top
            ScrollView {
                VStack(spacing: 0) {
                    scene(width: width, safeTop: safeTop)
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
                        switch phase {
                        case .setup:
                            setup
                        case let .entry(rounds, index, picked, score):
                            entryRound(rounds: rounds, index: index, picked: picked, score: score)
                        case .challenge:
                            challenge
                        case let .finished(score, previousBest):
                            finished(score: score, previousBest: previousBest)
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
        .animation(.easeOut(duration: 0.2), value: phase.isPlaying)
    }

    // MARK: Scene

    /// Spring-garden scene (pending artwork) with the back button and title; shorter while playing so
    /// a whole question fits on one screen.
    private func scene(width: CGFloat, safeTop: CGFloat) -> some View {
        let height = phase.isPlaying ? min(width * 0.46, 220) : min(width * 0.62, 300)
        return IllustratedSceneHeader(
            asset: ArtworkAsset.gameScene,
            height: height,
            fade: 0.3,
            imageAlignment: .top,
            textScrim: AppTheme.Colors.backgroundCream.opacity(0.5),
            pendingDelivery: true
        ) {
            HStack(alignment: .top, spacing: 12) {
                Button {
                    inputFocused = false
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
                    Text(settings.t("飛花令", "飞花令"))
                        .font(AppTheme.Typography.screenTitle)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Text(settings.t("用學過的詩句接字", "用学过的诗句接字"))
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

    // MARK: Setup

    private var setup: some View {
        Group {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    MascotIllustration(size: 60)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(settings.t("今天飛哪個字？", "今天飞哪个字？"))
                            .font(.sectionTitle)
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                        Text(settings.t("選一個字，說出含有這個字的詩句。", "选一个字，说出含有这个字的诗句。"))
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 60), spacing: 10)], spacing: 10) {
                    ForEach(library.feiHuaLingCharacters, id: \.hans) { option in
                        CharacterDisc(text: settings.t(option), isSelected: option == character, size: 60) {
                            character = option
                        }
                    }
                }
            }
            .card(padding: AppTheme.Spacing.cardInset, radius: AppTheme.CornerRadius.container)

            VStack(alignment: .leading, spacing: 10) {
                PillPicker(selection: $mode, options: [
                    (FeiHuaLingMode.entry, settings.t("入門：選一選", "入门：选一选")),
                    (FeiHuaLingMode.challenge, settings.t("挑戰：寫一寫", "挑战：写一写")),
                ])
                Text(mode == .entry
                     ? settings.t("每題四句詩，選出含有「\(character.hant)」的那一句。", "每题四句诗，选出含有“\(character.hans)”的那一句。")
                     : settings.t("憑記憶輸入含有「\(character.hant)」的詩句，不限時，可以看首字提示。", "凭记忆输入含有“\(character.hans)”的诗句，不限时，可以看首字提示。"))
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    IconDisc(systemImage: "trophy.fill")
                    Text(settings.t("個人最佳", "个人最佳"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Spacer()
                    Text(settings.t("\(best(for: mode)) 分", "\(best(for: mode)) 分"))
                        .font(.headline)
                        .foregroundStyle(AppTheme.Colors.accentOrange)
                }
                .accessibilityElement(children: .combine)
                scopeLabel
            }
            .card()

            Button(action: start) {
                Label(settings.t("開始", "开始"), systemImage: "play.fill")
            }
            .buttonStyle(PrimaryButtonStyle(showsChevron: true))
        }
    }

    private var scopeLabel: some View {
        Label(settings.t("本輪範圍：已學詩庫（內置 \(library.poems.count) 首）", "本轮范围：已学诗库（内置 \(library.poems.count) 首）"),
              systemImage: "books.vertical")
            .font(.footnote.weight(.medium))
            .foregroundStyle(AppTheme.Colors.textSecondary)
    }

    // MARK: Entry mode

    private func entryRound(rounds: [FeiHuaLingEngine.Round], index: Int, picked: Int?, score: Int) -> some View {
        let round = rounds[index]
        return Group {
            VStack(alignment: .leading, spacing: 12) {
                gameHeader(progress: settings.t("第 \(index + 1) / \(rounds.count) 題", "第 \(index + 1) / \(rounds.count) 题"), score: score)
                Text(settings.t("選出含有「\(character.hant)」的詩句", "选出含有“\(character.hans)”的诗句"))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                VStack(spacing: AppTheme.Spacing.item) {
                    ForEach(round.options.indices, id: \.self) { option in
                        let state: OptionCard.State = {
                            guard let picked else { return .normal }
                            if option == round.answer { return .correct }
                            return option == picked ? .needsFix : .dimmed
                        }()
                        Button {
                            guard picked == nil else { return }
                            let gained = option == round.answer ? 1 : 0
                            phase = .entry(rounds: rounds, index: index, picked: option, score: score + gained)
                        } label: {
                            OptionCard(text: round.options[option].text(settings.script).withoutTrailingPunctuation, state: state)
                        }
                        .buttonStyle(.plain)
                        .disabled(picked != nil)
                    }
                }
            }
            .card(padding: AppTheme.Spacing.cardInset, radius: AppTheme.CornerRadius.container)

            if let picked {
                let correctLine = round.options[round.answer]
                VStack(alignment: .leading, spacing: 10) {
                    Label(picked == round.answer ? settings.t("答對了！", "答对了！") : settings.t("再看看：含有「\(character.hant)」的是這句", "再看看：含有“\(character.hans)”的是这句"),
                          systemImage: picked == round.answer ? "checkmark.circle.fill" : "arrow.uturn.backward.circle.fill")
                        .font(.headline)
                        .foregroundStyle(picked == round.answer ? Color.deepLeaf : Color.hintRed)
                    sourceRow(correctLine)
                }
                .card(fill: picked == round.answer ? .paleGreenFill : .paleRedFill)

                Button {
                    if index + 1 < rounds.count {
                        phase = .entry(rounds: rounds, index: index + 1, picked: nil, score: score)
                    } else {
                        finish(score: score)
                    }
                } label: {
                    Text(index + 1 < rounds.count ? settings.t("下一題", "下一题") : settings.t("看結果", "看结果"))
                }
                .buttonStyle(PrimaryButtonStyle(showsChevron: true))
            }
        }
    }

    // MARK: Challenge mode

    private var challenge: some View {
        Group {
            VStack(alignment: .leading, spacing: 12) {
                gameHeader(progress: settings.t("已答 \(engine.used.count) / \(engine.validLines.count) 句", "已答 \(engine.used.count) / \(engine.validLines.count) 句"),
                           score: engine.used.count)
                Text(settings.t("輸入含有「\(character.hant)」的詩句", "输入含有“\(character.hans)”的诗句"))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                HStack(spacing: 10) {
                    TextField(settings.t("例如：一整句詩", "例如：一整句诗"), text: $input)
                        .font(.title3)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 50)
                        .background(AppTheme.Colors.backgroundCream, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(inputFocused ? AppTheme.Colors.primaryGold : AppTheme.Colors.borderWarm, lineWidth: 1.5))
                        .focused($inputFocused)
                        .submitLabel(.done)
                        .onSubmit(submitChallenge)
                        .autocorrectionDisabled()
                    Button(action: submitChallenge) {
                        Text(settings.t("提交", "提交"))
                    }
                    .buttonStyle(PrimaryButtonStyle(compact: true))
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let hint {
                    Label(hint, systemImage: "lightbulb.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.Colors.highlightCream, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                HStack(spacing: AppTheme.Spacing.item) {
                    Button {
                        if let line = engine.hint(), let first = line.text(settings.script).first {
                            hint = settings.t("試試以「\(first)」開頭的詩句", "试试以“\(first)”开头的诗句")
                        }
                    } label: {
                        Label(settings.t("首字提示", "首字提示"), systemImage: "lightbulb")
                    }
                    .buttonStyle(SoftButtonStyle(compact: true))
                    .frame(maxWidth: .infinity)
                    Button {
                        finish(score: engine.used.count)
                    } label: {
                        Label(settings.t("結束本局", "结束本局"), systemImage: "flag.checkered")
                    }
                    .buttonStyle(SoftButtonStyle(compact: true))
                    .frame(maxWidth: .infinity)
                }
            }
            .card(padding: AppTheme.Spacing.cardInset, radius: AppTheme.CornerRadius.container)

            if let verdict {
                verdictCard(verdict)
            }

            if !engine.used.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: settings.t("已用過的詩句", "已用过的诗句"))
                    ForEach(engine.used.reversed()) { line in
                        sourceRow(line)
                        if line != engine.used.first {
                            Divider().overlay(AppTheme.Colors.borderWarm)
                        }
                    }
                }
                .card()
            }
            scopeLabel
        }
    }

    private func verdictCard(_ verdict: FeiHuaLingEngine.Verdict) -> some View {
        let content: (icon: String, color: Color, fill: Color, text: String, line: FeiHuaLingLine?) = {
            switch verdict {
            case .accepted(let line):
                return ("checkmark.circle.fill", .deepLeaf, .paleGreenFill, settings.t("接得好！", "接得好！"), line)
            case .alreadyUsed(let line):
                return ("arrow.triangle.2.circlepath", .chestnut, .warmWhite, settings.t("這句已經用過了，換一句吧。", "这句已经用过了，换一句吧。"), line)
            case .missingCharacter(let line):
                return ("magnifyingglass", .chestnut, .warmWhite,
                        settings.t("這句詩裏沒有「\(character.hant)」字，再想想。", "这句诗里没有“\(character.hans)”字，再想想。"), line)
            case .notCollected:
                return ("tray", .chestnut, .warmWhite,
                        settings.t("暫未收錄：這句不在本輪詩庫裏，不算錯，可以換一句已學過的。", "暂未收录：这句不在本轮诗库里，不算错，可以换一句已学过的。"), nil)
            case .empty:
                return ("pencil", .chestnut, .warmWhite, settings.t("先輸入一句詩。", "先输入一句诗。"), nil)
            }
        }()
        return VStack(alignment: .leading, spacing: 8) {
            Label(content.text, systemImage: content.icon)
                .font(.headline)
                .foregroundStyle(content.color)
                .fixedSize(horizontal: false, vertical: true)
            if let line = content.line {
                sourceRow(line)
            }
        }
        .card(fill: content.fill)
    }

    // MARK: Finished

    private func finished(score: Int, previousBest: Int) -> some View {
        let isRecord = score > previousBest
        return Group {
            VStack(spacing: 10) {
                MascotIllustration(size: 110)
                Text(settings.t("「\(character.hant)」字飛花令", "“\(character.hans)”字飞花令"))
                    .font(AppTheme.Typography.label)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                Text(settings.t("\(score) 分", "\(score) 分"))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                if isRecord {
                    Label(settings.t("刷新個人最佳！", "刷新个人最佳！"), systemImage: "trophy.fill")
                        .font(.headline)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(AppTheme.Colors.highlightCream, in: Capsule())
                } else {
                    Text(settings.t("個人最佳：\(previousBest) 分", "个人最佳：\(previousBest) 分"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .card(padding: AppTheme.Spacing.cardInset, radius: AppTheme.CornerRadius.container)
            .accessibilityElement(children: .combine)

            if mode == .challenge, !engine.used.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: settings.t("這局接上的詩句", "这局接上的诗句"))
                    ForEach(engine.used) { line in
                        sourceRow(line)
                        if line != engine.used.last {
                            Divider().overlay(AppTheme.Colors.borderWarm)
                        }
                    }
                }
                .card()
            }
            Button(action: start) {
                Label(settings.t("再來一局", "再来一局"), systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(PrimaryButtonStyle())
            HStack(spacing: AppTheme.Spacing.item) {
                Button {
                    phase = .setup
                } label: {
                    Text(settings.t("換一個字", "换一个字"))
                }
                .buttonStyle(SoftButtonStyle())
                Button {
                    router.pop()
                } label: {
                    Text(settings.t("回到今天", "回到今天"))
                }
                .buttonStyle(SoftButtonStyle())
            }
        }
    }

    // MARK: Pieces

    private func gameHeader(progress: String, score: Int) -> some View {
        HStack(spacing: 12) {
            CharacterDisc(text: settings.t(character), isSelected: true, size: 48, action: nil)
                .accessibilityLabel(settings.t("目標字：\(character.hant)", "目标字：\(character.hans)"))
            Text(progress)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.Colors.textSecondary)
            Spacer()
            Label(settings.t("\(score) 分", "\(score) 分"), systemImage: "star.fill")
                .font(.headline)
                .foregroundStyle(AppTheme.Colors.accentOrange)
        }
    }

    /// The line with its source and a link back to the poem's explanation.
    private func sourceRow(_ line: FeiHuaLingLine) -> some View {
        let poem = library.poem(line.poemID)
        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(line.text(settings.script).withoutTrailingPunctuation)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                if let poem {
                    Text("《\(settings.t(poem.title))》\(poem.byline(settings))")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
            }
            Spacer(minLength: 8)
            if let poem {
                Button {
                    inputFocused = false
                    router.push(.poem(poem.id))
                } label: {
                    Text(settings.t("看釋義", "看释义"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.Colors.accentOrange)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Actions

    private func best(for mode: FeiHuaLingMode) -> Int {
        records.filter { $0.mode == mode.rawValue }.map(\.score).max() ?? 0
    }

    private func start() {
        engine = FeiHuaLingEngine(character: character, poems: library.poems, normalizer: library.normalizer)
        input = ""
        verdict = nil
        hint = nil
        switch mode {
        case .entry:
            let rounds = engine.entryRounds()
            phase = rounds.isEmpty ? .setup : .entry(rounds: rounds, index: 0, picked: nil, score: 0)
        case .challenge:
            phase = .challenge
            inputFocused = true
        }
    }

    private func submitChallenge() {
        let result = engine.submit(input)
        verdict = result
        if case .accepted = result {
            input = ""
            hint = nil
            if engine.isExhausted {
                finish(score: engine.used.count)
            }
        }
    }

    private func finish(score: Int) {
        inputFocused = false
        let previousBest = ProgressStore(context: context)
            .recordGame(mode: mode.rawValue, character: character.hans, score: score)
        phase = .finished(score: score, previousBest: previousBest)
    }
}

// MARK: - Pieces shared with the workshop

/// One big character on a round sticker: gold when chosen, paper otherwise. Dark text on gold, never white.
struct CharacterDisc: View {
    let text: String
    let isSelected: Bool
    var size: CGFloat = 60
    var action: (() -> Void)?

    var body: some View {
        let disc = Text(text)
            .font(.system(size: size * 0.48, weight: .semibold, design: .serif))
            .foregroundStyle(AppTheme.Colors.textPrimary)
            .frame(width: size, height: size)
            .background(
                AnyShapeStyle(isSelected
                    ? AnyShapeStyle(LinearGradient(colors: [AppTheme.Colors.primaryGoldLight, AppTheme.Colors.primaryGold],
                                                   startPoint: .top, endPoint: .bottom))
                    : AnyShapeStyle(AppTheme.Colors.surfacePaper)),
                in: Circle()
            )
            .overlay(Circle().strokeBorder(isSelected ? Color(hex: 0xE9A512).opacity(0.6) : AppTheme.Colors.borderWarm, lineWidth: 1.5))
            .shadow(color: AppTheme.Colors.shadow.opacity(isSelected ? 0.16 : 0.06), radius: 6, y: 3)
        if let action {
            Button(action: action) { disc }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
        } else {
            disc
        }
    }
}

/// Small icon on a pale gold round base, as in the growth stats panel.
struct IconDisc: View {
    let systemImage: String
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(Color(hex: 0xB07A1A))
            .frame(width: size, height: size)
            .background(Color(hex: 0xFFF0C9), in: Circle())
            .accessibilityHidden(true)
    }
}

/// Two-to-four way choice drawn as a paper capsule with a gold sliding pill; replaces the blue system segmented control.
struct PillPicker<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(Value, String)]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.0) { value, title in
                let isSelected = value == selection
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { selection = value }
                } label: {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(isSelected ? AppTheme.Colors.primaryGold : Color.clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(AppTheme.Colors.backgroundCream, in: Capsule())
        .overlay(Capsule().strokeBorder(AppTheme.Colors.borderWarm, lineWidth: 1))
        .frame(minHeight: 44)
    }
}
