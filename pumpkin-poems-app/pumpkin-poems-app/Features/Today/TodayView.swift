import SwiftData
import SwiftUI

/// 今天: immersive scene → continue-learning card → 今日计划 strip → 今日复习 / 飞花令 shortcuts (ui-instruction §5).
/// The top scene rotates daily through the three themes; the card vignette and the reading page
/// follow the current poem's explicit theme.
struct TodayView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(Router.self) private var router
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query private var progressRecords: [PoemProgress]
    @Query private var mistakes: [Mistake]
    @Query private var attempts: [QuizAttempt]
    /// Re-reads the goal when it changes.
    @Query(filter: #Predicate<LearningEvent> { $0.kind == "goal" }) private var goalEvents: [LearningEvent]
    @Environment(\.modelContext) private var context
    @Environment(NetworkMonitor.self) private var network
    @State private var showsGoal = false
    #if DEBUG
    /// Re-renders when the demo date shift changes.
    @AppStorage(AppClock.dayOffsetKey) private var dayOffset = 0
    #endif

    /// How far the continue card rides up over the scene's fade.
    private let cardOverlap: CGFloat = 56

    private var snapshot: LearningSnapshot { LearningSnapshot(progress: progressRecords) }

    var body: some View {
        #if DEBUG
        let _ = dayOffset
        #endif
        let snapshot = snapshot
        let now = AppClock.now
        let _ = goalEvents.count
        let plan = snapshot.dailyPlan(goal: ProgressStore(context: context).currentGoal(), mistakes: mistakes,
                                      attempts: attempts, now: now)
        let current = snapshot.inProgress
        let mainPoem = current?.poem ?? snapshot.nextUnstarted
        let heroTheme = PoemVisualTheme.daily(now)
        let cardTheme = PoemVisualTheme(poem: mainPoem)

        StorybookPage(overlap: cardOverlap, sceneHeight: { width in
            // Square scene shown whole (no stretching, 贝贝 never cropped); only the grass under the card is covered.
            min(width * 0.96, 500)
        }, scene: { metrics in
            heroScene(theme: heroTheme, metrics: metrics)
        }, content: { metrics in
            VStack(spacing: AppTheme.Spacing.section) {
                ContinueLearningCard(current: current, poem: mainPoem, theme: cardTheme,
                                     isFirstEver: !snapshot.hasAnyRecord)
                DailyPlanStrip(plan: plan, isOffline: !network.isOnline) { showsGoal = true }
                shortcuts(plan: plan)
            }
            .storybookColumn(metrics)
        })
        .pageBackground()
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showsGoal) {
            DailyGoalSheet(goal: ProgressStore(context: context).currentGoal())
                .presentationDetents([.medium])
        }
        .onAppear {
            Telemetry.shared.logDayOpened(dueCount: snapshot.dueReviews(mistakes: mistakes, now: AppClock.now).count)
        }
    }

    // MARK: Scene

    /// The square picture is anchored to its bottom so only sky is trimmed and 贝贝 stays whole; the card
    /// then rides up over the fade at the bottom. As a side panel the picture is about square anyway.
    private func heroScene(theme: PoemVisualTheme, metrics: StorybookMetrics) -> some View {
        let light = theme.prefersLightForeground
        return IllustratedSceneHeader(
            asset: theme.homeAsset,
            height: metrics.sceneHeight,
            fade: 0.24,
            imageAlignment: .bottom,
            textScrim: light ? Color(hex: 0x14204A).opacity(0.38) : AppTheme.Colors.backgroundCream.opacity(0.55),
            fadeEdge: metrics.fadeEdge
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Text(settings.t("今天", "今天"))
                    .font(AppTheme.Typography.screenTitle)
                Text(settings.t("和貝貝一起，\n讀懂一首詩", "和贝贝一起，\n读懂一首诗"))
                    .font(AppTheme.Typography.heroLead)
                    .lineSpacing(3)
            }
            .foregroundStyle(theme.foreground)
            .shadow(color: light ? Color.black.opacity(0.25) : Color.white.opacity(0.6), radius: 2, y: 1)
            .padding(metrics.sceneTextInsets)
            .frame(maxWidth: 560, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: Shortcuts

    @ViewBuilder
    private func shortcuts(plan: DailyPlan) -> some View {
        let today = plan.reviewsToday.count
        let review = LearningShortcutCard(
            title: settings.t("今日複習", "今日复习"),
            subtitle: plan.isPaused ? settings.t("今天休息", "今天休息")
                : today == 0 ? settings.t("今天沒有要複習的詩", "今天没有要复习的诗")
                : settings.t("\(today) 首等你複習", "\(today) 首等你复习"),
            asset: ArtworkAsset.reviewScroll,
            artAlignment: .bottomLeading,
            artScale: 0.74
        ) { router.push(.review) }

        let game = LearningShortcutCard(
            title: settings.t("飛花令", "飞花令"),
            subtitle: settings.t("用學過的詩句接字", "用学过的诗句接字"),
            asset: ArtworkAsset.flowerGame,
            artAlignment: .bottomLeading,
            artScale: 0.72
        ) { router.push(.feiHuaLing(nil)) }

        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: AppTheme.Spacing.shortcutGap) {
                review
                game
            }
        } else {
            HStack(alignment: .top, spacing: AppTheme.Spacing.shortcutGap) {
                review
                game
            }
        }
    }
}

// MARK: - Continue learning card

/// Paper card over the scene: small title, poem name, tagline and the gold action, with the theme's
/// vignette fading in from the right. Native text only; the artwork never sits behind text.
struct ContinueLearningCard: View {
    let current: (poem: Poem, step: LearningStep)?
    let poem: Poem?
    let theme: PoemVisualTheme?
    let isFirstEver: Bool

    @Environment(AppSettings.self) private var settings
    @Environment(Router.self) private var router

    var body: some View {
        Group {
            if let poem {
                poemContent(poem)
            } else {
                allDone
            }
        }
        .padding(AppTheme.Spacing.cardInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .topTrailing) {
            if let theme {
                GeometryReader { proxy in
                    // The vignette fills exactly the area above the gold button, so its soft bottom edge
                    // is never cut flat by the button row; only the left side fades into the paper.
                    let buttonTop = proxy.size.height - AppTheme.Spacing.cardInset - AppTheme.Sizes.buttonHeight
                    let artHeight = max(96, buttonTop - 4)
                    ArtworkImage(name: theme.continueAsset, contentMode: .fit)
                        .frame(height: artHeight)
                        .mask(
                            LinearGradient(stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .black, location: 0.32),
                            ], startPoint: .leading, endPoint: .trailing)
                        )
                        .frame(maxWidth: .infinity, alignment: .topTrailing)
                        .offset(x: 8, y: -2)
                }
                .allowsHitTesting(false)
            }
        }
        .background(AppTheme.Colors.surfacePaper,
                    in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.container, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.container, style: .continuous)
            .strokeBorder(AppTheme.Colors.borderWarm, lineWidth: 1))
        .overlay(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.container - 5, style: .continuous)
            .strokeBorder(AppTheme.Colors.borderWarm.opacity(0.45), lineWidth: 1)
            .padding(5))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.container, style: .continuous))
        .shadow(color: AppTheme.Colors.shadow.opacity(0.12), radius: 14, y: 6)
    }

    private func poemContent(_ poem: Poem) -> some View {
        let step = current?.step ?? .notStarted
        return VStack(alignment: .leading, spacing: 6) {
            Text(isFirstEver ? settings.t("開啟第一首詩", "开启第一首诗")
                 : current == nil ? settings.t("學下一首", "学下一首") : settings.t("繼續學習", "继续学习"))
                .font(AppTheme.Typography.label)
                .foregroundStyle(AppTheme.Colors.textSecondary)
            Text(settings.t(poem.title))
                .font(AppTheme.Typography.cardPoemTitle)
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .padding(.trailing, 110)
            Text(settings.t(poem.tagline))
                .font(.body)
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.trailing, 90)
            Button {
                open(poem, at: step)
            } label: {
                Text(actionTitle(step))
            }
            .buttonStyle(PrimaryButtonStyle(showsChevron: true))
            .padding(.top, 16)
            .accessibilityHint(stepTitle(step))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var allDone: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(settings.t("全部練習通過", "全部练习通过"))
                .font(AppTheme.Typography.label)
                .foregroundStyle(AppTheme.Colors.textSecondary)
            Text(settings.t("\(PoemLibrary.shared.poems.count) 首詩都練習通過了！", "\(PoemLibrary.shared.poems.count) 首诗都练习通过了！"))
                .font(AppTheme.Typography.cardPoemTitle)
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .minimumScaleFactor(0.7)
            Text(settings.t("按時複習，讓記憶更穩。", "按时复习，让记忆更稳。"))
                .foregroundStyle(AppTheme.Colors.textSecondary)
            Button {
                router.selectedTab = .me
            } label: {
                Text(settings.t("看看成長冊", "看看成长册"))
            }
            .buttonStyle(PrimaryButtonStyle(showsChevron: true))
            .padding(.top, 8)
        }
    }

    private func open(_ poem: Poem, at step: LearningStep) {
        switch step {
        case .reciting: router.push(.recite(poem.id))
        case .quizzing: router.push(.quiz(poem.id))
        default: router.push(.poem(poem.id))
        }
    }

    private func actionTitle(_ step: LearningStep) -> String {
        switch step {
        case .notStarted: settings.t("開始學習", "开始学习")
        case .reading: settings.t("繼續學習", "继续学习")
        case .reciting: settings.t("繼續背誦", "继续背诵")
        case .quizzing, .completed: settings.t("去小測", "去小测")
        }
    }

    private func stepTitle(_ step: LearningStep) -> String {
        switch step {
        case .notStarted, .reading: settings.t("學到：理解詩意", "学到：理解诗意")
        case .reciting: settings.t("學到：分層背誦", "学到：分层背诵")
        case .quizzing, .completed: settings.t("學到：鞏固小測", "学到：巩固小测")
        }
    }
}

// MARK: - Shortcut card

/// 今日复习 / 飞花令: title top-left, artwork on the right, white round arrow bottom-right.
/// The whole card is the button; the artwork never intercepts touches.
struct LearningShortcutCard: View {
    let title: String
    let subtitle: String
    let asset: String
    var artAlignment: Alignment = .bottomTrailing
    var artScale: CGFloat = 1
    var action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 40)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 134, alignment: .topLeading)
            .background(alignment: artAlignment) {
                GeometryReader { proxy in
                    ArtworkImage(name: asset, contentMode: .fit)
                        .frame(width: proxy.size.width * artScale)
                        // Fade the top of the artwork so the subtitle above it stays clean.
                        .mask(LinearGradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.38),
                        ], startPoint: .top, endPoint: .bottom))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: artAlignment)
                        .offset(x: -6, y: 10)
                }
                .allowsHitTesting(false)
            }
            .overlay(alignment: .bottomTrailing) {
                ArrowBadge().padding(12)
            }
            .background(AppTheme.Colors.surfacePaper,
                        in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.card, style: .continuous)
                .strokeBorder(AppTheme.Colors.borderWarm, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.card, style: .continuous))
            .shadow(color: AppTheme.Colors.shadow.opacity(0.08), radius: 12, y: 4)
            .contentShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.card, style: .continuous))
        }
        .buttonStyle(ShortcutPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)，\(subtitle)")
        .accessibilityAddTraits(.isButton)
    }
}

private struct ShortcutPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Daily plan

/// One quiet row under the continue card: the goal, what is done today, and the gear to change it.
/// Backlog and offline notes appear only when they apply, so the page still fits one screen.
struct DailyPlanStrip: View {
    let plan: DailyPlan
    let isOffline: Bool
    var edit: () -> Void

    @Environment(AppSettings.self) private var settings

    var body: some View {
        Button(action: edit) {
            HStack(spacing: 10) {
                Image(systemName: plan.isComplete ? "checkmark.seal.fill" : plan.isPaused ? "moon.zzz" : "target")
                    .font(.title3)
                    .foregroundStyle(plan.isComplete ? AppTheme.Colors.successGreen : AppTheme.Colors.accentOrange)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                if isOffline {
                    Label(settings.t("離線", "离线"), systemImage: "icloud.slash")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .labelStyle(.titleAndIcon)
                }
                Image(systemName: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.Colors.surfacePaper, in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.card, style: .continuous)
                .strokeBorder(AppTheme.Colors.borderWarm, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(settings.t("調整每日目標", "调整每日目标"))
    }

    private var headline: String {
        if plan.isPaused { return settings.t("今天休息一天", "今天休息一天") }
        if plan.isComplete { return settings.t("今日計劃完成了！", "今日计划完成了！") }
        return settings.t("今日計劃 · 約 \(plan.minutes) 分鐘", "今日计划 · 约 \(plan.minutes) 分钟")
    }

    private var detail: String {
        if plan.isPaused { return settings.t("到期的複習會留到明天，不會清零。", "到期的复习会留到明天，不会清零。") }
        if plan.hasNothingToDo { return settings.t("沒有到期的複習，也沒有新詩了。", "没有到期的复习，也没有新诗了。") }
        var parts: [String] = []
        if plan.reviewTarget > 0 {
            parts.append(settings.t("複習 \(plan.reviewsDone)/\(plan.reviewTarget)", "复习 \(plan.reviewsDone)/\(plan.reviewTarget)"))
        }
        if plan.newTarget > 0 {
            parts.append(settings.t("新詩 \(plan.newDone)/\(plan.newTarget)", "新诗 \(plan.newDone)/\(plan.newTarget)"))
        }
        var text = parts.joined(separator: " · ")
        if plan.backlog > 0 {
            text += settings.t("　另有 \(plan.backlog) 首可以明天再做", "　另有 \(plan.backlog) 首可以明天再做")
        }
        return text
    }
}

/// 每日目标: about 5, 10 or 15 minutes as a task-size suggestion (never a timer), and a rest day.
struct DailyGoalSheet: View {
    let goal: LearningEventPayload.Goal

    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var minutes = DailyPlan.defaultMinutes
    @State private var paused = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(settings.t("每天大約", "每天大约"), selection: $minutes) {
                        ForEach(DailyPlan.goalOptions, id: \.self) { value in
                            Text(settings.t("\(value) 分鐘", "\(value) 分钟")).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(quotaText)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                } header: {
                    Text(settings.t("每日目標", "每日目标"))
                } footer: {
                    Text(settings.t("只是任務量建議，不會計時。到期的複習優先，再學一首新詩；積下來的複習會分幾天完成。",
                                    "只是任务量建议，不会计时。到期的复习优先，再学一首新诗；积下来的复习会分几天完成。"))
                }
                Section {
                    Toggle(settings.t("今天休息", "今天休息"), isOn: $paused)
                } footer: {
                    Text(settings.t("休息不會清除任何記錄，明天照常。", "休息不会清除任何记录，明天照常。"))
                }
            }
            .navigationTitle(settings.t("今日計劃", "今日计划"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(settings.t("完成", "完成")) {
                        ProgressStore(context: context).setGoal(minutes: minutes, pausedToday: paused)
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            minutes = goal.minutes
            paused = goal.pausedOn.map { Calendar.current.isDate($0, inSameDayAs: AppClock.now) } ?? false
        }
    }

    private var quotaText: String {
        let quota = DailyPlan.quota(minutes: minutes, hasDueReviews: true)
        return settings.t("約複習 \(quota.reviews) 首，再學 \(max(quota.newPoems, minutes < 10 ? 0 : 1)) 首新詩。",
                          "约复习 \(quota.reviews) 首，再学 \(max(quota.newPoems, minutes < 10 ? 0 : 1)) 首新诗。")
            + (minutes < 10 ? settings.t("沒有複習的日子學一首新詩。", "没有复习的日子学一首新诗。") : "")
    }
}
