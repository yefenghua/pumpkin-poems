import SwiftData
import SwiftUI

/// 学习完成页 (P1 成长反馈): a celebration scene, the poem card just earned (or what is still
/// missing), the concrete rewards, a small growth-book progress strip, and the 飞花令 entry so the
/// learner can use the lines straight away. Every number comes from real records.
struct QuizCompletionView: View {
    let poem: Poem
    let outcome: QuizOutcome
    var onRetry: () -> Void

    @Environment(AppSettings.self) private var settings
    @Environment(Router.self) private var router
    @Query private var progressRecords: [PoemProgress]

    private let library = PoemLibrary.shared
    private let cardOverlap: CGFloat = 44

    var body: some View {
        let snapshot = LearningSnapshot(progress: progressRecords)
        GeometryReader { geo in
            let width = geo.size.width
            let safeTop = geo.safeAreaInsets.top
            ScrollView {
                VStack(spacing: 0) {
                    scene(width: width, safeTop: safeTop)
                    VStack(spacing: AppTheme.Spacing.section) {
                        resultCard(snapshot)
                        progressCard(snapshot)
                        actions
                    }
                    .padding(.horizontal, width < 380 ? AppTheme.Spacing.pageCompact : AppTheme.Spacing.page)
                    .padding(.top, -cardOverlap)
                    .padding(.bottom, AppTheme.Spacing.pageBottom)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                }
            }
            .ignoresSafeArea(edges: .top)
        }
        .pageBackground()
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
    }

    // MARK: Scene

    private func scene(width: CGFloat, safeTop: CGFloat) -> some View {
        IllustratedSceneHeader(
            asset: ArtworkAsset.celebrationScene,
            height: min(width * 0.6, 290),
            fade: 0.3,
            imageAlignment: .top,
            textScrim: AppTheme.Colors.backgroundCream.opacity(0.5),
            pendingDelivery: true
        ) {
            HStack(alignment: .top, spacing: 12) {
                Button {
                    router.pop()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.bold))
                        .frame(width: 40, height: 40)
                        .background(AppTheme.Colors.surfacePaper.opacity(0.92), in: Circle())
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                }
                .accessibilityLabel(settings.t("返回詩頁", "返回诗页"))
                VStack(alignment: .leading, spacing: 4) {
                    Text(outcome.passed ? settings.t("練習完成", "练习完成") : settings.t("再試一次", "再试一次"))
                        .font(AppTheme.Typography.screenTitle)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Text("《\(title)》" + poem.byline(settings))
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

    // MARK: Result

    private func resultCard(_ snapshot: LearningSnapshot) -> some View {
        let progress = snapshot.progress(poem.id)
        return VStack(alignment: .leading, spacing: 12) {
            Text(headline)
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 14) {
                poemCard(progress)
                VStack(alignment: .leading, spacing: 8) {
                    Label(settings.t("答對 \(outcome.score) / \(outcome.total) 題", "答对 \(outcome.score) / \(outcome.total) 题"),
                          systemImage: outcome.passed ? "checkmark.seal.fill" : "arrow.counterclockwise.circle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(outcome.passed ? AppTheme.Colors.successGreen : AppTheme.Colors.textSecondary)
                    ForEach(rewards, id: \.text) { reward in
                        HStack(alignment: .top, spacing: 8) {
                            IconDisc(systemImage: reward.icon, size: 28)
                            Text(reward.text)
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .card(padding: AppTheme.Spacing.cardInset, radius: AppTheme.CornerRadius.container)
    }

    /// The 诗词卡 for this poem: full colour once earned, locked and desaturated otherwise.
    private func poemCard(_ progress: PoemProgress?) -> some View {
        let earned = progress?.hasPassed ?? false
        let level = progress?.cardLevel ?? 0
        return VStack(spacing: 0) {
            ZStack {
                Group {
                    if let theme = PoemVisualTheme(themeID: poem.theme) {
                        ArtworkImage(name: theme.coverAsset, contentMode: .fill)
                    } else {
                        ArtworkPlaceholder()
                    }
                }
                .frame(width: 96, height: 118)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .saturation(earned ? 1 : 0.1)
                .opacity(earned ? 1 : 0.55)
                if !earned {
                    Image(systemName: "lock.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .padding(10)
                        .background(AppTheme.Colors.surfacePaper.opacity(0.92), in: Circle())
                }
            }
            .padding(5)
            VStack(spacing: 3) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                HStack(spacing: 2) {
                    ForEach(0..<ReviewScheduler.maxCardLevel, id: \.self) { index in
                        Image(systemName: index < level ? "star.fill" : "star")
                            .font(.system(size: 9))
                            .foregroundStyle(Color(hex: 0x9A5B12))
                    }
                }
            }
            .padding(.vertical, 6)
        }
        .frame(width: 106)
        .background(AppTheme.Colors.surfacePaper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(earned ? AppTheme.Colors.primaryGold : AppTheme.Colors.borderWarm, lineWidth: earned ? 1.5 : 1))
        .shadow(color: AppTheme.Colors.shadow.opacity(0.12), radius: 8, y: 4)
        .rotationEffect(.degrees(-3))
        .padding(.horizontal, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(earned ? settings.t("詩詞卡《\(title)》，熟練度 \(level) 級", "诗词卡《\(title)》，熟练度 \(level) 级")
                                   : settings.t("詩詞卡《\(title)》尚未獲得", "诗词卡《\(title)》尚未获得"))
    }

    // MARK: Progress

    /// 简单进度展示: the growth book's passed count and this theme's cards, as a gold progress strip.
    private func progressCard(_ snapshot: LearningSnapshot) -> some View {
        let passed = snapshot.count(.passed)
        let total = library.poems.count
        let theme = library.theme(poem.theme)
        let themePoems = library.poems(inTheme: poem.theme).count
        let themePassed = snapshot.passedPoems(inTheme: poem.theme)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(settings.t("成長冊", "成长册"), systemImage: "book.closed")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                Spacer()
                Text(settings.t("練習通過 \(passed) / \(total) 首", "练习通过 \(passed) / \(total) 首"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
            }
            ProgressStrip(fraction: total == 0 ? 0 : Double(passed) / Double(total))
            if let theme {
                HStack {
                    Text(settings.t(theme.name))
                        .font(.footnote)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                    Spacer()
                    Text(settings.t("\(themePassed) / \(themePoems) 張詩詞卡", "\(themePassed) / \(themePoems) 张诗词卡"))
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                ProgressStrip(fraction: themePoems == 0 ? 0 : Double(themePassed) / Double(themePoems))
            }
        }
        .card()
        .accessibilityElement(children: .combine)
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: AppTheme.Spacing.item) {
            if !outcome.passed {
                Button(action: onRetry) {
                    Label(settings.t("再練一次", "再练一次"), systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            if let character = feiHuaLingCharacter {
                Button {
                    router.push(.feiHuaLing(character.hans))
                } label: {
                    Label(settings.t("用剛學的詩句玩「\(character.hant)」字飛花令",
                                     "用刚学的诗句玩“\(character.hans)”字飞花令"),
                          systemImage: "sparkles")
                }
                .buttonStyle(outcome.passed ? AnyButtonStyle(PrimaryButtonStyle(showsChevron: true)) : AnyButtonStyle(SoftButtonStyle()))
            }
            HStack(spacing: AppTheme.Spacing.item) {
                if let workshopTheme = workshopTheme {
                    Button {
                        router.push(.poetWorkshop(.new(themeID: workshopTheme.id)))
                    } label: {
                        Label(settings.t("寫兩句", "写两句"), systemImage: "pencil.line")
                    }
                    .buttonStyle(SoftButtonStyle())
                }
                Button {
                    router.pop()
                } label: {
                    Text(settings.t("返回詩頁", "返回诗页"))
                }
                .buttonStyle(SoftButtonStyle())
            }
        }
    }

    // MARK: Text

    private var title: String { settings.t(poem.title) }

    private var headline: String {
        switch outcome.event {
        case .firstPass:
            settings.t("這次你把《\(title)》的練習都完成了！", "这次你把《\(title)》的练习都完成了！")
        case .reviewPassed:
            settings.t("隔了一天，你還記得這首詩。", "隔了一天，你还记得这首诗。")
        case .repeatedSameDay:
            settings.t("再練一次，記得更牢了。", "再练一次，记得更牢了。")
        case .failed:
            settings.t("還差一點點，看看解釋再試一次。", "还差一点点，看看解释再试一次。")
        }
    }

    private var rewards: [(icon: String, text: String)] {
        var items: [(String, String)] = []
        switch outcome.event {
        case .firstPass:
            items.append(("rectangle.stack.badge.plus", settings.t("獲得詩詞卡《\(title)》", "获得诗词卡《\(title)》")))
        case .reviewPassed:
            items.append(("arrow.up.circle", settings.t("詩詞卡熟練度提升到 \(outcome.cardLevel) 級", "诗词卡熟练度提升到 \(outcome.cardLevel) 级")))
        case .repeatedSameDay, .failed:
            break
        }
        if let theme = outcome.completedTheme {
            items.append(("rosette", settings.t("解鎖主題徽章「\(settings.t(theme.badge))」", "解锁主题徽章“\(settings.t(theme.badge))”")))
        }
        if outcome.resolvedMistakes > 0 {
            items.append(("wand.and.stars", settings.t("你修正了 \(outcome.resolvedMistakes) 道之前的錯題", "你修正了 \(outcome.resolvedMistakes) 道之前的错题")))
        }
        if outcome.score < outcome.total {
            items.append(("tray.full", settings.t("答錯的題目已放進錯題本", "答错的题目已放进错题本")))
        }
        if let next = outcome.nextReviewAt {
            items.append(("calendar", settings.t("下次複習：", "下次复习：") + Self.describe(next, settings: settings)))
        }
        return items
    }

    /// A 飞花令 character that appears in this poem.
    private var feiHuaLingCharacter: LocalizedText? {
        library.feiHuaLingCharacters.first { character in
            poem.lines.contains { library.normalizer.normalize($0.text.hans).contains(character.hans) }
        }
    }

    /// The writing theme that borrows this poem's imagery, for the 小小诗人 shortcut.
    private var workshopTheme: PoetWorkshopTheme? {
        PoetWorkshopContent.themes.first { $0.libraryThemeID == poem.theme }
    }

    static func describe(_ date: Date, settings: AppSettings) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: AppClock.now),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        switch days {
        case ...0: return settings.t("今天", "今天")
        case 1: return settings.t("明天", "明天")
        case 2: return settings.t("後天", "后天")
        default:
            let components = calendar.dateComponents([.month, .day], from: date)
            return settings.t("\(components.month ?? 0)月\(components.day ?? 0)日", "\(components.month ?? 0)月\(components.day ?? 0)日")
        }
    }
}

/// Thin gold progress bar on a cream track.
struct ProgressStrip: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(AppTheme.Colors.backgroundCream)
                    .overlay(Capsule().strokeBorder(AppTheme.Colors.borderWarm, lineWidth: 1))
                Capsule()
                    .fill(LinearGradient(colors: [AppTheme.Colors.primaryGoldLight, AppTheme.Colors.primaryGold],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, min(1, fraction)) * proxy.size.width)
            }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}

/// Type-erased button style so a button can switch between styles.
struct AnyButtonStyle: ButtonStyle {
    private let make: (Configuration) -> AnyView

    init<S: ButtonStyle>(_ style: S) {
        make = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: Configuration) -> some View {
        make(configuration)
    }
}
