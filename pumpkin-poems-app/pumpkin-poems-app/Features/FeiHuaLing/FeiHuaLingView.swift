import SwiftData
import SwiftUI

/// Six completion rounds with stable, gently falling character tokens.
struct FeiHuaLingView: View {
    private enum Phase: String { case setup, playing, finished }

    @Environment(AppSettings.self) private var settings
    @Environment(Router.self) private var router
    @Environment(SpeechPlayer.self) private var speech
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Query private var records: [GameRecord]
    @State private var character: LocalizedText
    @State private var game: FlyingFlowerEngine?
    @State private var phase: Phase = .setup
    @State private var field: FlyingGlyphField?
    @State private var lastSelectionAt = ProcessInfo.processInfo.systemUptime
    @State private var lastShakeAt = -Double.infinity
    @State private var previousBest = 0
    @State private var showRules = false
    @State private var showHint = false

    private let catalog: FlyingFlowerCatalog
    private let recordMode = "flying"

    init(initialCharacter: String?) {
        let corpus = GameCorpus.shared
        let catalogue = FlyingFlowerCatalog(verses: corpus.verses, normalizer: corpus.normalizer)
        catalog = catalogue
        _character = State(initialValue: catalogue.characters.first {
            $0.hans == initialCharacter || $0.hant == initialCharacter
        } ?? catalogue.characters.first ?? LocalizedText(hant: "月", hans: "月"))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                switch phase {
                case .setup: setup
                case .playing: playing
                case .finished: finished
                }
            }
            .padding(16)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .pageBackground()
        .navigationTitle(settings.t("飛花令", "飞花令"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    GameSoundControls()
                    Button { showRules = true } label: { Image(systemName: "questionmark.circle") }
                        .accessibilityLabel(settings.t("玩法", "玩法"))
                }
            }
        }
        .sheet(isPresented: $showRules) {
            NavigationStack {
                ScrollView { rules.padding(20) }.pageBackground()
                    .navigationTitle(settings.t("怎樣飛花", "怎样飞花"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) {
                        Button(settings.t("知道了", "知道了")) { showRules = false }
                    } }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showHint, onDismiss: {
            lastSelectionAt = ProcessInfo.processInfo.systemUptime
        }) {
            hintWindow
        }
        .background(ShakeDetector(enabled: phase == .playing && game?.resolved == false
                                  && game?.full == false && !showRules && !showHint && scenePhase == .active,
                                  onShake: shake).frame(width: 0, height: 0))
        .task(id: "\(phase.rawValue)-\(game?.index ?? -1)-\(scenePhase == .active)") {
            guard phase == .playing, scenePhase == .active else { return }
            resetSky()
            while !Task.isCancelled && phase == .playing {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                if !showRules, !showHint, let game, !game.resolved {
                    field?.update(at: ProcessInfo.processInfo.systemUptime, game: game)
                }
            }
        }
        .onDisappear {
            speech.stop()
            GameFeedback.shared.endSession()
        }
        .onAppear {
            if phase == .playing { GameFeedback.shared.beginSession() }
        }
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                MascotIllustration(size: 74)
                VStack(alignment: .leading, spacing: 6) {
                    Text(settings.t("接住飄落的字，補完一句詩", "接住飘落的字，补完一句诗"))
                        .font(.title2.bold())
                    Text(settings.t("選一個飛字，每局六句。", "选一个飞字，每局六句。"))
                        .foregroundStyle(Color.chestnut)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 14) {
                ForEach(catalog.characters, id: \.hans) { option in
                    CharacterDisc(text: settings.t(option), isSelected: option == character, size: 58) {
                        character = option
                        GameFeedback.shared.play(.tap)
                    }
                }
            }
            HStack {
                Label(settings.t("個人最佳", "个人最佳"), systemImage: "trophy")
                Spacer()
                Text("\(records.filter { $0.mode == recordMode }.map(\.score).max() ?? 0) / 600")
            }
            .font(.subheadline.weight(.semibold))
            Button(action: start) {
                Label(settings.t("開始飛花", "开始飞花"), systemImage: "wind")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(catalog.characters.isEmpty)
        }
        .card()
    }

    private var rules: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(settings.t("點選飄字，從左到右補完詩句。每局六題。", "点选飘字，从左到右补完诗句。每局六题。"))
            Text(settings.t("搖一搖可增加飄字。", "摇一摇可增加飘字。"))
            Text(settings.t("每題100分，答錯減10分，最低20分。", "每题100分，答错减10分，最低20分。"))
        }
        .foregroundStyle(Color.cocoa)
    }

    @ViewBuilder
    private var playing: some View {
        if let game, let round = game.current {
            VStack(spacing: 12) {
                HStack {
                    CharacterDisc(text: settings.t(character), isSelected: true, size: 44, action: nil)
                    Text(settings.t("第 \(game.index + 1) / 6 題", "第 \(game.index + 1) / 6 题"))
                    Spacer()
                    Label("\(game.score)", systemImage: "star.fill").foregroundStyle(Color.pumpkinOrange)
                }
                .font(.headline)
                HStack(spacing: 5) {
                    ForEach(0..<round.length, id: \.self) { position in
                        let fixed = round.fixedPositions.contains(position)
                        let hinted = game.hintPosition == position
                        Text(game.slots(settings.script)[position] ?? "·")
                            .font(.title2.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .foregroundStyle(fixed ? Color.pumpkinOrange : (hinted ? Color.deepLeaf : Color.cocoa))
                            .background(fixed ? Color.paleGoldLine.opacity(0.55) : (hinted ? Color.deepLeaf.opacity(0.1) : Color.warmWhite),
                                        in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(
                                fixed ? Color.pumpkinOrange : (hinted ? Color.deepLeaf : Color.paleGoldLine),
                                lineWidth: fixed || hinted ? 2 : 1))
                            .accessibilityLabel(settings.t("第\(position + 1)字", "第\(position + 1)字"))
                            .accessibilityValue(game.slots(settings.script)[position] ?? settings.t("未填", "未填"))
                    }
                }
                if !game.resolved {
                    HStack {
                        Text(settings.t("接字填空", "接字填空"))
                            .font(.caption).foregroundStyle(Color.chestnut)
                        Spacer()
                        Button(action: openHint) {
                            Label(settings.t("提示", "提示"), systemImage: "lightbulb")
                        }
                        .padding(.trailing, 12)
                        Button(settings.t("撤回", "撤回")) { self.game?.undo(); GameFeedback.shared.play(.tap) }
                            .disabled(game.entered.isEmpty)
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
            .card(padding: 14)
            if game.resolved {
                answerFeedback(game)
            } else {
                sky
                if game.verdict == .incorrect || game.verdict == .duplicate {
                    Text(game.verdict == .duplicate
                         ? settings.t("這句已用過", "这句已用过")
                         : settings.t("詩句不符", "诗句不符"))
                        .font(.subheadline).foregroundStyle(Color.hintRed)
                }
                HStack(spacing: 12) {
                    Button(settings.t("跳過看答案", "跳过看答案")) {
                        self.game?.skip(); speech.stop(); GameFeedback.shared.play(.tap)
                    }
                    .buttonStyle(SoftButtonStyle())
                    Button(settings.t("提交詩句", "提交诗句")) { submit() }
                        .buttonStyle(PrimaryButtonStyle()).disabled(!game.full)
                }
            }
        }
    }

    private var hintWindow: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let game, let verse = game.hintVerse {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(settings.t("出處", "出处"), systemImage: "book.closed")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(Color.chestnut)
                            Text("《\(settings.t(verse.title))》")
                                .font(.title2.bold()).foregroundStyle(Color.cocoa)
                            Text(settings.t(verse.author))
                                .foregroundStyle(Color.chestnut)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card()
                        if let letter = game.hintLetter {
                            HStack {
                                Label(settings.t("補字", "补字"), systemImage: "lightbulb.fill")
                                    .foregroundStyle(Color.chestnut)
                                Spacer()
                                Text(settings.t(letter))
                                    .font(.title.bold()).foregroundStyle(Color.deepLeaf)
                                    .frame(width: 52, height: 52)
                                    .background(Color.deepLeaf.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                            }
                            .card()
                        } else {
                            Button(action: fillHint) {
                                Label(settings.t("補一個字", "补一个字"), systemImage: "lightbulb.fill")
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(game.full)
                        }
                    }
                }
                .padding(20)
            }
            .pageBackground()
            .navigationTitle(settings.t("提示", "提示"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button(settings.t("繼續接字", "继续接字")) { showHint = false }
            } }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var sky: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { _ in
            GeometryReader { geo in
                let now = ProcessInfo.processInfo.systemUptime
                ZStack(alignment: .topLeading) {
                    LinearGradient(colors: [Color(hex: 0xEAF4FF), Color(hex: 0xFFF9E9)], startPoint: .top, endPoint: .bottom)
                    Image(systemName: "cloud.fill").font(.system(size: 75)).foregroundStyle(.white.opacity(0.7)).offset(x: 14, y: 20)
                    Image(systemName: "cloud.fill").font(.system(size: 55)).foregroundStyle(.white.opacity(0.65)).offset(x: geo.size.width - 80, y: 160)
                    if let field {
                        ForEach(field.glyphs) { glyph in
                            let point = field.position(of: glyph, at: now)
                            Button { catchGlyph(glyph) } label: {
                                Text(settings.t(glyph.text))
                                    .font(.system(size: 25, weight: .semibold, design: .serif))
                                    .foregroundStyle(Color.cocoa)
                                    .frame(width: 44, height: 48)
                                    .background(.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 14))
                                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.paleGoldLine))
                                    .shadow(color: Color.cocoa.opacity(0.12), radius: 4, y: 3)
                            }
                            .buttonStyle(.plain)
                            .position(x: point.x, y: point.y)
                            .disabled(game?.full == true || point.y < 24 || point.y > geo.size.height - 24)
                            .accessibilityLabel(settings.t("接住\(settings.t(glyph.text))", "接住\(settings.t(glyph.text))"))
                        }
                    }
                }
                .clipped()
                .contentShape(Rectangle())
                .onAppear { configureSky(width: geo.size.width, height: geo.size.height) }
                .onChange(of: geo.size) { _, size in configureSky(width: size.width, height: size.height) }
                .onChange(of: reduceMotion) { _, _ in configureSky(width: geo.size.width, height: geo.size.height) }
                .overlay(alignment: .bottom) {
                    if now - lastSelectionAt >= 15, game?.full == false, field?.isBoosted(at: now) != true {
                        Label(settings.t("搖一搖，掉落更多字", "摇一摇，掉落更多字"), systemImage: "iphone.radiowaves.left.and.right")
                            .font(.caption.weight(.medium)).foregroundStyle(Color.chestnut)
                            .padding(8).background(.regularMaterial, in: Capsule()).padding(8)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }

    private func answerFeedback(_ game: FlyingFlowerEngine) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(game.verdict == .accepted ? settings.t("答對，＋\(game.gained)分", "答对，＋\(game.gained)分")
                  : settings.t("本題答案", "本题答案"),
                  systemImage: game.verdict == .accepted ? "checkmark.seal.fill" : "book")
                .font(.title3.bold()).foregroundStyle(Color.deepLeaf)
            if let verse = game.acceptedVerse {
                Text(settings.t(verse.text)).font(.title2.weight(.semibold))
                Text("《\(settings.t(verse.title))》 · \(settings.t(verse.author))")
                    .font(.subheadline).foregroundStyle(Color.chestnut)
                HStack {
                    Button {
                        speech.speak([(id: verse.id, text: settings.spoken(verse.text))], language: settings.voice)
                    } label: { Label(settings.t("聽這句", "听这句"), systemImage: "speaker.wave.2") }
                    .buttonStyle(AudioButtonStyle(compact: true))
                    if verse.hasLearningPage {
                        Button(settings.t("看釋義", "看释义")) { router.push(.poem(verse.poemID)) }
                            .buttonStyle(SoftButtonStyle(compact: true))
                    }
                }
            }
            Button {
                speech.stop()
                if game.isLast { finish() } else { self.game?.next() }
            } label: { Text(game.isLast ? settings.t("看成績", "看成绩") : settings.t("下一題", "下一题")) }
                .buttonStyle(PrimaryButtonStyle(showsChevron: true))
        }
        .card()
    }

    private var finished: some View {
        VStack(spacing: 18) {
            MascotIllustration(size: 100)
            Text(settings.t("本局完成", "本局完成")).font(.title2.bold())
            Text("\(game?.score ?? 0) / 600").font(.system(size: 42, weight: .bold, design: .rounded))
            Text(settings.t("接對 \(game?.solvedCount ?? 0) / 6 句", "接对 \(game?.solvedCount ?? 0) / 6 句"))
                .foregroundStyle(Color.chestnut)
            if (game?.score ?? 0) > previousBest {
                Label(settings.t("刷新個人最佳", "刷新个人最佳"), systemImage: "trophy.fill").foregroundStyle(Color.pumpkinOrange)
            }
            Button(settings.t("再飛一局", "再飞一局"), action: start).buttonStyle(PrimaryButtonStyle())
            Button(settings.t("換一個飛字", "换一个飞字")) { phase = .setup }.buttonStyle(SoftButtonStyle())
            Button(settings.t("回到遊樂園", "回到游乐园")) { router.pop() }.buttonStyle(.borderless)
        }
        .frame(maxWidth: .infinity).card()
    }

    private func start() {
        let nextGame = FlyingFlowerEngine(character: character, catalog: catalog)
        guard nextGame.rounds.count == 6 else { return }
        game = nextGame
        phase = .playing
        GameFeedback.shared.beginSession()
        GameFeedback.shared.play(.tap)
    }

    private func configureSky(width: Double, height: Double) {
        field = FlyingGlyphField(width: width, height: height, reduceMotion: reduceMotion)
        field?.reset(at: ProcessInfo.processInfo.systemUptime)
    }

    private func resetSky() {
        let now = ProcessInfo.processInfo.systemUptime
        field?.reset(at: now)
        lastSelectionAt = now
        lastShakeAt = -.infinity
    }

    private func catchGlyph(_ glyph: FlyingGlyphField.Glyph) {
        guard phase == .playing, !showHint, game?.resolved == false, game?.full == false,
              let text = field?.remove(id: glyph.id), game?.enter(text) == true else { return }
        lastSelectionAt = ProcessInfo.processInfo.systemUptime
        GameFeedback.shared.play(.tap)
    }

    private func shake() {
        let now = ProcessInfo.processInfo.systemUptime
        guard phase == .playing, game?.resolved == false, game?.full == false,
              !showRules, !showHint, scenePhase == .active, now - lastShakeAt >= 1 else { return }
        field?.shake(at: now)
        lastShakeAt = now
        lastSelectionAt = now
        GameFeedback.shared.play(.tap)
    }

    private func submit() {
        guard let result = game?.submit() else { return }
        lastSelectionAt = ProcessInfo.processInfo.systemUptime
        GameFeedback.shared.play(result == .accepted ? .success : .error)
    }

    private func openHint() {
        guard phase == .playing, game?.revealSourceHint() != nil else { return }
        GameFeedback.shared.play(.tap)
        showHint = true
    }

    private func fillHint() {
        guard game?.fillHintLetter() == true else { return }
        lastSelectionAt = ProcessInfo.processInfo.systemUptime
        GameFeedback.shared.play(.success)
        showHint = false
    }

    private func finish() {
        guard phase == .playing, let game, game.isLast, game.resolved else { return }
        previousBest = ProgressStore(context: context).recordGame(mode: recordMode, character: character.hans, score: game.score)
        phase = .finished
        field?.reset(at: ProcessInfo.processInfo.systemUptime)
        GameFeedback.shared.endSession()
        GameFeedback.shared.play(.complete)
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
