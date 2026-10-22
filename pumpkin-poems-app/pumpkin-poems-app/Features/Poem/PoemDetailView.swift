import SwiftData
import SwiftUI

/// 诗歌学习页 (ui-instruction §6): themed scene on top, a sheet of warm paper carrying the poem,
/// the tapped line's meaning with the pumpkin helper, and a fixed listen / recite bar at the bottom.
struct PoemDetailView: View {
    let poemID: String

    @Environment(AppSettings.self) private var settings
    @Environment(Router.self) private var router
    @Environment(SpeechPlayer.self) private var speech
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var progressRecords: [PoemProgress]

    @State private var selectedLineID: String?
    @State private var viewedLineIDs: Set<String> = []
    @State private var showThink = false
    @State private var activeTerm: Annotation?
    @State private var playingFullPoem = false

    /// How far the paper rides up over the scene.
    private let paperOverlap: CGFloat = 28

    init(poemID: String) {
        self.poemID = poemID
        _progressRecords = Query(filter: #Predicate<PoemProgress> { $0.poemID == poemID })
    }

    private var poem: Poem? { PoemLibrary.shared.poem(poemID) }
    private var progress: PoemProgress? { progressRecords.first }
    private var store: ProgressStore { ProgressStore(context: context) }

    var body: some View {
        if let poem {
            content(poem)
        } else {
            ContentUnavailableView(settings.t("找不到這首詩", "找不到这首诗"), systemImage: "book.closed")
        }
    }

    private func content(_ poem: Poem) -> some View {
        let theme = PoemVisualTheme(themeID: poem.theme)
        return GeometryReader { geo in
            let width = geo.size.width
            let safeTop = geo.safeAreaInsets.top
            ScrollView {
                VStack(spacing: 0) {
                    scene(poem, theme: theme, width: width, safeTop: safeTop)
                    PaperSurface {
                        VStack(spacing: AppTheme.Spacing.section) {
                            poemLines(poem)
                            lineExplanation(poem)
                            understanding(poem)
                            Button {
                                speech.stop()
                                store.markRead(poem.id)
                                router.push(.quiz(poem.id))
                            } label: {
                                Label(settings.t("直接做小測", "直接做小测"), systemImage: "checklist")
                            }
                            .buttonStyle(SoftButtonStyle())
                        }
                        .padding(.horizontal, width < 380 ? AppTheme.Spacing.pageCompact : AppTheme.Spacing.page)
                        .padding(.top, 16)
                        .padding(.bottom, AppTheme.Spacing.pageBottom)
                        .frame(maxWidth: 760)
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.top, -paperOverlap)
                }
            }
            .ignoresSafeArea(edges: .top)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                LearningActionBar(poem: poem, width: width, playing: speech.isSpeaking && playingFullPoem) {
                    toggleFullPoem(poem)
                } recite: {
                    speech.stop()
                    store.markRead(poem.id)
                    router.push(.recite(poem.id))
                }
            }
        }
        .background(AppTheme.Colors.surfacePaper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .sheet(item: $activeTerm) { term in
            TermSheet(annotation: term)
                .presentationDetents([.fraction(0.3), .medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.warmWhite)
        }
        .onAppear {
            store.advance(poem.id, to: .reading)
            if selectedLineID == nil { selectedLineID = poem.lines.first?.id }
        }
        .onDisappear { speech.stop() }
        .onChange(of: speech.isSpeaking) { _, isSpeaking in
            if !isSpeaking && playingFullPoem {
                playingFullPoem = false
                store.markRead(poem.id)
            }
        }
        .onChange(of: speech.speakingLineID) { _, lineID in
            if let lineID { selectedLineID = lineID }
        }
        .onChange(of: viewedLineIDs) { _, viewed in
            if viewed.count == poem.lines.count { store.markRead(poem.id) }
        }
    }

    // MARK: Scene and navigation

    private func scene(_ poem: Poem, theme: PoemVisualTheme?, width: CGFloat, safeTop: CGFloat) -> some View {
        // Scene about 300pt on a phone: the picture keeps its top (moon, lantern) and loses a little water.
        let height = min(width * 0.76, 400)
        let light = theme?.prefersLightForeground ?? false
        let fg = theme?.foreground ?? AppTheme.Colors.textPrimary
        let fg2 = theme?.secondaryForeground ?? AppTheme.Colors.textSecondary
        return IllustratedSceneHeader(
            asset: theme?.readingAsset,
            height: height,
            fade: 0.1,
            textScrim: light ? Color(hex: 0x10204A).opacity(0.42) : AppTheme.Colors.backgroundCream.opacity(0.5)
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Button {
                        speech.stop()
                        router.pop()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.bold))
                            .frame(width: 40, height: 40)
                            .background(AppTheme.Colors.surfacePaper.opacity(0.92), in: Circle())
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                    }
                    .accessibilityLabel(settings.t("返回", "返回"))

                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 12) {
                            titleBlock(poem, foreground: fg, secondary: fg2)
                            Spacer(minLength: 8)
                            ScriptAndVoiceMenus()
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            titleBlock(poem, foreground: fg, secondary: fg2)
                            ScriptAndVoiceMenus()
                        }
                    }

                    Button {
                        store.toggleFavorite(poem.id)
                    } label: {
                        Image(systemName: progress?.isFavorite == true ? "heart.fill" : "heart")
                            .font(.body.weight(.semibold))
                            .frame(width: 40, height: 40)
                            .background(AppTheme.Colors.surfacePaper.opacity(0.92), in: Circle())
                            .foregroundStyle(Color.peachPink)
                    }
                    .accessibilityLabel(progress?.isFavorite == true ? settings.t("取消收藏", "取消收藏") : settings.t("收藏", "收藏"))
                }
            }
            .padding(.top, safeTop + 8)
            .padding(.horizontal, width < 380 ? AppTheme.Spacing.pageCompact : AppTheme.Spacing.page)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func titleBlock(_ poem: Poem, foreground: Color, secondary: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(settings.t(poem.title))
                .font(AppTheme.Typography.detailTitle)
                .foregroundStyle(foreground)
                .lineLimit(2)
            Text(poem.byline(settings))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(secondary)
        }
        .shadow(color: foreground == AppTheme.Colors.textPrimary ? Color.white.opacity(0.5) : Color.black.opacity(0.3),
                radius: 2, y: 1)
        .padding(.top, 6)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: Poem lines

    private func poemLines(_ poem: Poem) -> some View {
        VStack(spacing: 4) {
            ForEach(poem.lines) { line in
                let isSelected = selectedLineID == line.id
                let isSpoken = speech.speakingLineID == line.id
                AnnotatedLineText(line: line, annotations: poem.annotations) { term in
                    select(line)
                    activeTerm = term
                }
                .multilineTextAlignment(.center)
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 60)
                .background(isSelected ? AppTheme.Colors.highlightCream : Color.clear,
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(alignment: .leading) {
                    if isSpoken {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.caption)
                            .foregroundStyle(AppTheme.Colors.audioBlue)
                            .padding(.leading, 8)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
                .onTapGesture { select(line) }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                .accessibilityHint(settings.t("點一下看這句的意思", "点一下看这句的意思"))
                .accessibilityAction { select(line) }
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: selectedLineID)
    }

    // MARK: 读懂这句

    /// Size of the pumpkin leaning on the box's top-right corner; about 45% of him sits inside the box.
    private var helperSize: CGFloat { dynamicTypeSize.isAccessibilitySize ? 80 : 92 }

    private func lineExplanation(_ poem: Poem) -> some View {
        let line = poem.line(selectedLineID ?? "")
        let inset: CGFloat = 18
        let helperInside = helperSize * 0.42
        return VStack(alignment: .leading, spacing: 12) {
            Label(settings.t("讀懂這句", "读懂这句"), systemImage: "lightbulb.fill")
                .font(.headline)
                .foregroundStyle(AppTheme.Colors.accentOrange)
                .padding(.trailing, helperSize + 8)
                // Keep the body text below the pumpkin's chin.
                .frame(minHeight: max(22, helperInside - inset + 10), alignment: .topLeading)
            if let line {
                Text(settings.t(line.explain))
                    .font(AppTheme.Typography.explanation)
                    .lineSpacing(6)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button {
                        select(line)
                        playingFullPoem = false
                        speech.speak([(line.id, line.text(settings.script))], language: settings.voice)
                    } label: {
                        Label(settings.t("聽這句", "听这句"), systemImage: "speaker.wave.2")
                    }
                    .buttonStyle(AudioButtonStyle(compact: true))
                    if line.think != nil {
                        Button {
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { showThink.toggle() }
                        } label: {
                            Label(settings.t("再想一想", "再想一想"), systemImage: showThink ? "chevron.up" : "sparkles")
                        }
                        .buttonStyle(SoftButtonStyle(compact: true))
                    }
                }
                if showThink, let think = line.think {
                    Text(settings.t(think))
                        .font(.body)
                        .lineSpacing(6)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            } else {
                Text(settings.t("點一句詩，貝貝陪你讀懂它在說甚麼。", "点一句诗，贝贝陪你读懂它在说什么。"))
                    .font(AppTheme.Typography.explanation)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
            }
        }
        .padding(inset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.Colors.backgroundCream,
                    in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.card, style: .continuous)
            .strokeBorder(AppTheme.Colors.borderWarm, lineWidth: 1))
        .overlay(alignment: .topTrailing) {
            // 贝贝 leans on the corner: body in front of the box, hands and scarf resting on its edge.
            MascotIllustration(size: helperSize, mirrored: true)
                .overlay(alignment: .topLeading) {
                    IdeaSparkles()
                        .frame(width: helperSize * 0.26, height: helperSize * 0.26)
                        .offset(x: -helperSize * 0.02, y: helperSize * 0.08)
                }
                .offset(x: 6, y: -(helperSize - helperInside))
        }
        .padding(.top, helperSize - helperInside - 6)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: selectedLineID)
    }

    // MARK: 全诗理解

    private func understanding(_ poem: Poem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: settings.t("全詩理解", "全诗理解"))
            understandingRow(icon: "photo", title: settings.t("詩中場景", "诗中场景"), text: poem.understanding.scene)
            understandingRow(icon: "heart.text.square", title: settings.t("主要情感", "主要情感"), text: poem.understanding.feeling)
            understandingRow(icon: "clock", title: settings.t("寫作背景", "写作背景"), text: poem.understanding.background)
            Divider().overlay(AppTheme.Colors.borderWarm)
            VStack(alignment: .leading, spacing: 4) {
                Text(settings.t("關於作者", "关于作者"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                Text(settings.t(poem.author.bio))
                    .font(.callout)
                    .lineSpacing(4)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
            }
            HStack(spacing: 8) {
                if let theme = PoemLibrary.shared.theme(poem.theme) {
                    Chip(title: settings.t(theme.name))
                }
                Chip(title: settings.t(poem.genre))
                StatusBadge(status: PoemStatus(progress))
            }
        }
        .card(fill: AppTheme.Colors.backgroundCream)
    }

    private func understandingRow(icon: String, title: String, text: LocalizedText) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.Colors.textSecondary)
            Text(settings.t(text))
                .font(.body)
                .lineSpacing(5)
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Actions

    private func toggleFullPoem(_ poem: Poem) {
        if speech.isSpeaking {
            speech.stop()
            playingFullPoem = false
        } else {
            playingFullPoem = true
            speech.speak(poem.lines.map { ($0.id, $0.text(settings.script)) }, language: settings.voice)
        }
    }

    private func select(_ line: PoemLine) {
        if selectedLineID != line.id {
            showThink = false
        }
        selectedLineID = line.id
        viewedLineIDs.insert(line.id)
    }
}

// MARK: - Bottom bar

/// Fixed bar in the bottom safe area: 听一听 (pale blue) and 开始背诵 (gold), about 1 : 1.6.
struct LearningActionBar: View {
    let poem: Poem
    let width: CGFloat
    let playing: Bool
    var listen: () -> Void
    var recite: () -> Void

    @Environment(AppSettings.self) private var settings
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var voiceAvailable: Bool { SpeechPlayer.hasVoice(for: settings.voice) }

    var body: some View {
        VStack(spacing: 8) {
            if !voiceAvailable {
                Text(settings.t("此裝置沒有對應的朗讀語音，將使用系統預設語音。", "此设备没有对应的朗读语音，将使用系统默认语音。"))
                    .font(.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 10) {
                    listenButton
                    reciteButton
                }
            } else {
                HStack(spacing: 12) {
                    listenButton.frame(maxWidth: .infinity)
                    reciteButton.frame(width: (min(width, 800) - AppTheme.Spacing.page * 2 - 12) * 1.6 / 2.6)
                }
            }
        }
        .padding(.horizontal, AppTheme.Spacing.page)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: 800)
        .frame(maxWidth: .infinity)
        .background(
            AppTheme.Colors.surfacePaper
                .shadow(color: AppTheme.Colors.shadow.opacity(0.08), radius: 12, y: -4)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var listenButton: some View {
        Button(action: listen) {
            Label(playing ? settings.t("暫停", "暂停") : settings.t("聽一聽", "听一听"),
                  systemImage: playing ? "pause.fill" : "speaker.wave.2.fill")
        }
        .buttonStyle(AudioButtonStyle())
        .accessibilityHint(playing ? settings.t("停止朗讀全詩", "停止朗读全诗") : settings.t("朗讀全詩", "朗读全诗"))
    }

    private var reciteButton: some View {
        Button(action: recite) {
            Text(settings.t("開始背誦", "开始背诵"))
        }
        .buttonStyle(PrimaryButtonStyle())
    }
}

/// Three short gold strokes beside the helper's head: "I've got an idea".
private struct IdeaSparkles: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            Path { path in
                path.move(to: CGPoint(x: w * 0.15, y: h * 0.55)); path.addLine(to: CGPoint(x: w * 0.45, y: h * 0.4))
                path.move(to: CGPoint(x: w * 0.4, y: h * 0.1)); path.addLine(to: CGPoint(x: w * 0.6, y: h * 0.38))
                path.move(to: CGPoint(x: w * 0.75, y: h * 0.0)); path.addLine(to: CGPoint(x: w * 0.8, y: h * 0.35))
            }
            .stroke(AppTheme.Colors.primaryGold, style: StrokeStyle(lineWidth: max(2.5, w * 0.1), lineCap: .round))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Word meaning in the context of this poem.
private struct TermSheet: View {
    let annotation: Annotation
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(settings.t("字詞解釋", "字词解释"), systemImage: "character.magnify")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.chestnut)
            Text(settings.t(annotation.term))
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(Color.cocoa)
            Text(settings.t(annotation.definition))
                .font(.title3)
                .foregroundStyle(Color.cocoa)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
