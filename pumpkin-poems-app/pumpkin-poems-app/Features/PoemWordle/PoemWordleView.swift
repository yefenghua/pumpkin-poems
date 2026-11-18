import SwiftData
import SwiftUI

/// A six-round deduction game. Source verses stay hidden until the round has ended.
struct PoemWordleView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SpeechPlayer.self) private var speech
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var context
    @State private var length = 5
    @State private var engine: PoemWordleEngine?
    @State private var selectedPoemIDs: Set<String> = []
    @State private var preparedPuzzle: PoemWordlePuzzle?
    @State private var preparedFor = ""
    @State private var preparing = false
    @State private var preparationRound = 0
    @State private var showRules = false
    @State private var confirmRestart = false
    @State private var savedResult = false
    @State private var feedback = ""

    private var preparationID: String {
        "\(length):\(preparationRound):" + selectedPoemIDs.sorted().joined(separator: ",")
    }
    private var canStart: Bool { preparedPuzzle != nil && preparedFor == preparationID && !preparing }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let game = engine {
                    gameHeader(game)
                    board(game)
                    legend
                    if game.finished {
                        result(game)
                    } else {
                        keyboard(game)
                        actions(game)
                    }
                } else {
                    setup
                }
            }
            .padding(16)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .pageBackground()
        .navigationTitle(settings.t("六輪猜詩", "六轮猜诗"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                GameSoundControls()
                Button(settings.t("玩法", "玩法"), systemImage: "questionmark.circle") { showRules = true }
            }
        }
        .sheet(isPresented: $showRules) {
            NavigationStack {
                ScrollView { rules.padding(20) }
                    .pageBackground()
                    .navigationTitle(settings.t("怎樣猜詩", "怎样猜诗"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(settings.t("知道了", "知道了")) { showRules = false }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
        .confirmationDialog(settings.t("放棄本局，重新選擇？", "放弃本局，重新选择？"),
                            isPresented: $confirmRestart, titleVisibility: .visible) {
            Button(settings.t("重新選擇", "重新选择"), role: .destructive) {
                returnToSetup()
            }
        }
        .task(id: preparationID) { await preparePuzzle() }
        .onDisappear { speech.stop(); GameFeedback.shared.endSession() }
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "square.grid.3x3.fill")
                    .font(.system(size: 38)).foregroundStyle(Color.pumpkinOrange)
                VStack(alignment: .leading, spacing: 5) {
                    Text(settings.t("六次機會，猜出一句詩", "六次机会，猜出一句诗"))
                        .font(.title2.bold())
                }
            }
            Picker(settings.t("詩句長度", "诗句长度"), selection: $length) {
                Text(settings.t("五言 · 5 字", "五言 · 5 字")).tag(5)
                Text(settings.t("七言 · 7 字", "七言 · 7 字")).tag(7)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("wordle.length")
            Text(settings.t("從候選字中輸入所選詩庫的詩句。", "从候选字中输入所选诗库的诗句。"))
                .font(.subheadline).foregroundStyle(Color.chestnut)
            GameLibraryPicker(selection: $selectedPoemIDs)
            if preparing {
                ProgressView(settings.t("正在準備…", "正在准备…"))
            } else if !canStart && !selectedPoemIDs.isEmpty {
                Text(settings.t("請多選一些詩", "请多选一些诗"))
                    .foregroundStyle(Color.chestnut).font(.callout)
            }
            Button(action: start) {
                Label(settings.t("開始猜詩", "开始猜诗"), systemImage: "play.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!canStart)
            .accessibilityIdentifier("wordle.start")
        }
        .card()
    }

    private var rules: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(settings.t("用候選字輸入所選詩庫中的完整詩句，六輪內猜中謎底。", "用候选字输入所选诗库中的完整诗句，六轮内猜中谜底。"))
            legend
            Text(settings.t("同一字可以重複輸入。", "同一字可以重复输入。"))
                .font(.footnote).foregroundStyle(Color.chestnut)
        }
        .foregroundStyle(Color.cocoa)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func gameHeader(_ game: PoemWordleEngine) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(game.puzzle.length == 5 ? settings.t("五言謎局", "五言谜局") : settings.t("七言謎局", "七言谜局"))
                    .font(.headline)
                Text(settings.t("\(game.puzzle.keyboard.count) 個候選字", "\(game.puzzle.keyboard.count) 个候选字"))
                    .font(.caption).foregroundStyle(Color.chestnut)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text(game.finished ? settings.t("本局結束", "本局结束")
                     : settings.t("第 \(game.guesses.count + 1) / 6 輪", "第 \(game.guesses.count + 1) / 6 轮"))
                    .font(.headline).monospacedDigit()
                if !game.finished {
                    Button(settings.t("換一局", "换一局")) { confirmRestart = true }
                        .font(.caption)
                }
            }
        }
    }

    private func board(_ game: PoemWordleEngine) -> some View {
        VStack(spacing: 5) {
            ForEach(0..<PoemWordleEngine.maximumGuesses, id: \.self) { row in
                let guess = game.guesses.indices.contains(row) ? game.guesses[row] : nil
                let current = row == game.guesses.count && !game.finished
                HStack(spacing: 5) {
                    ForEach(0..<game.puzzle.length, id: \.self) { column in
                        let key = guess.map { $0.keys[column] }
                            ?? (current && game.input.indices.contains(column) ? game.input[column] : "")
                        let mark = guess.map { $0.marks[column] }
                        tile(key: key, mark: mark, active: current, game: game)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(rowLabel(row: row, guess: guess, current: current, game: game))
            }
        }
        .accessibilityIdentifier("wordle.board")
    }

    private func tile(key: String, mark: PoemWordleEngine.Mark?, active: Bool, game: PoemWordleEngine) -> some View {
        VStack(spacing: 0) {
            Text(display(key, in: game))
                .font(.system(size: game.puzzle.length == 7 ? 21 : 25, weight: .semibold, design: .serif))
                .lineLimit(1).minimumScaleFactor(0.7)
            if let mark { Image(systemName: icon(mark)).font(.system(size: 7, weight: .bold)) }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .foregroundStyle(foreground(mark))
        .background(fill(mark), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(active ? Color.pumpkinOrange : Color.paleGoldLine,
                                                              lineWidth: active ? 1.6 : 0.7))
    }

    private var legend: some View {
        HStack(spacing: 8) {
            legendItem(.correct, settings.t("字位皆對", "字位皆对"))
            legendItem(.misplaced, settings.t("位置不對", "位置不对"))
            legendItem(.absent, settings.t("無字／多猜", "无字／多猜"))
        }
        .frame(maxWidth: .infinity)
    }

    private func legendItem(_ mark: PoemWordleEngine.Mark, _ text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon(mark)).font(.system(size: 10, weight: .bold))
                .frame(width: 17, height: 17)
                .background(fill(mark), in: RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(foreground(mark))
            Text(text).font(.caption2)
        }
        .foregroundStyle(Color.chestnut)
    }

    private func keyboard(_ game: PoemWordleEngine) -> some View {
        let marks = game.keyboardMarks
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 7), spacing: 6) {
            ForEach(game.puzzle.keyboard) { key in
                let mark = marks[key.id]
                Button {
                    engine?.append(key.id)
                    feedback = ""
                    GameFeedback.shared.play(.tap)
                } label: {
                    VStack(spacing: 0) {
                        Text(settings.t(key.text)).font(.title3.weight(.semibold))
                        if let mark { Image(systemName: icon(mark)).font(.system(size: 7, weight: .bold)) }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(fill(mark), in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(foreground(mark))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.paleGoldLine, lineWidth: 0.7))
                }
                .buttonStyle(.plain)
                .disabled(game.input.count >= game.puzzle.length)
                .accessibilityLabel(settings.t(key.text) + (mark.map { "，" + markLabel($0) } ?? ""))
                .accessibilityIdentifier("wordle.key.\(key.id)")
            }
        }
    }

    private func actions(_ game: PoemWordleEngine) -> some View {
        VStack(spacing: 8) {
            if !feedback.isEmpty { Text(feedback).font(.caption).foregroundStyle(Color.hintRed) }
            HStack(spacing: 10) {
                Button { engine?.backspace(); feedback = ""; GameFeedback.shared.play(.tap) } label: {
                    Image(systemName: "delete.left").frame(minWidth: 28)
                }
                .buttonStyle(SoftButtonStyle(compact: true))
                .disabled(game.input.isEmpty)
                .accessibilityLabel(settings.t("刪除最後一字", "删除最后一字"))
                Button(settings.t("清空", "清空")) { engine?.clear(); feedback = ""; GameFeedback.shared.play(.tap) }
                    .buttonStyle(SoftButtonStyle(compact: true))
                    .disabled(game.input.isEmpty)
                Button(action: submit) { Text(settings.t("提交", "提交")) }
                    .buttonStyle(PrimaryButtonStyle(compact: true))
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("wordle.submit")
            }
        }
    }

    private func result(_ game: PoemWordleEngine) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(game.won ? settings.t("\(game.guesses.count) 輪猜中", "\(game.guesses.count) 轮猜中")
                  : settings.t("六輪已用完", "六轮已用完"),
                  systemImage: game.won ? "checkmark.seal.fill" : "book.fill")
                .font(.title3.bold()).foregroundStyle(game.won ? Color.deepLeaf : Color.cocoa)
            Text(settings.t(game.puzzle.answer.text)).font(.title2.weight(.semibold))
            Text("《\(settings.t(game.puzzle.answer.title))》· \(settings.t(game.puzzle.answer.author))")
                .font(.subheadline).foregroundStyle(Color.chestnut)
            HStack {
                Button {
                    speech.speak([(game.puzzle.answer.id, settings.spoken(game.puzzle.answer.text))], language: settings.voice)
                } label: { Label(settings.t("聽答案", "听答案"), systemImage: "speaker.wave.2") }
                    .buttonStyle(AudioButtonStyle(compact: true))
                if game.puzzle.answer.hasLearningPage {
                    Button(settings.t("讀這首詩", "读这首诗")) { router.push(.poem(game.puzzle.answer.poemID)) }
                        .buttonStyle(SoftButtonStyle(compact: true))
                }
            }
            DisclosureGroup(settings.t("本局詩句與出處", "本局诗句与出处")) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(game.puzzle.allSources) { verse in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(settings.t(verse.text)).font(.body)
                            Text("《\(settings.t(verse.title))》· \(settings.t(verse.author))")
                                .font(.caption).foregroundStyle(Color.chestnut)
                        }
                    }
                }.padding(.top, 8)
            }
            Button(settings.t("再猜一局", "再猜一局"), action: returnToSetup)
                .buttonStyle(PrimaryButtonStyle())
        }
        .card()
        .accessibilityIdentifier("wordle.result")
    }

    private func preparePuzzle() async {
        let identifier = preparationID
        preparedPuzzle = nil
        preparedFor = ""
        guard !selectedPoemIDs.isEmpty else { preparing = false; return }
        preparing = true
        let corpus = GameCorpus.shared
        let verses = corpus.verses.filter { selectedPoemIDs.contains($0.poemID) }
        let normalizer = corpus.normalizer
        let selectedLength = length
        let job = Task.detached(priority: .userInitiated) {
            PoemWordlePuzzle.make(length: selectedLength, verses: verses, normalizer: normalizer)
        }
        let puzzle = await withTaskCancellationHandler(operation: { await job.value }, onCancel: { job.cancel() })
        guard !Task.isCancelled, preparationID == identifier else { return }
        preparedPuzzle = puzzle
        preparedFor = identifier
        preparing = false
    }

    private func start() {
        guard canStart, let puzzle = preparedPuzzle else { return }
        speech.stop()
        savedResult = false
        feedback = ""
        engine = PoemWordleEngine(puzzle: puzzle)
        GameFeedback.shared.beginSession()
        GameFeedback.shared.play(.tap)
    }

    private func returnToSetup() {
        speech.stop()
        GameFeedback.shared.endSession()
        engine = nil
        feedback = ""
        preparationRound += 1
    }

    private func submit() {
        guard let submission = engine?.submit() else { return }
        switch submission {
        case .incomplete:
            feedback = settings.t("請填滿 \(length) 個字。", "请填满 \(length) 个字。")
            GameFeedback.shared.play(.error)
            return
        case .notInLibrary:
            feedback = settings.t("請換一句所選詩庫中的詩句。", "请换一句所选诗库中的诗句。")
            GameFeedback.shared.play(.error)
            return
        case .finished: return
        case .accepted: feedback = ""
        }
        guard let game = engine else { return }
        GameFeedback.shared.play(game.finished ? (game.won ? .complete : .error) : .success)
        guard game.finished, !savedResult else { return }
        savedResult = true
        _ = ProgressStore(context: context).recordGame(mode: "poem-wordle", character: "\(length)",
                                                       score: game.won ? 7 - game.guesses.count : 0)
    }

    private func display(_ key: String, in game: PoemWordleEngine) -> String {
        game.puzzle.keyboard.first { $0.id == key }.map { settings.t($0.text) } ?? ""
    }
    private func fill(_ mark: PoemWordleEngine.Mark?) -> Color {
        switch mark {
        case .correct: Color.deepLeaf
        case .misplaced: Color.pumpkinGold
        case .absent: Color(hex: 0x73777E)
        case nil: Color.warmWhite
        }
    }
    private func foreground(_ mark: PoemWordleEngine.Mark?) -> Color {
        mark == .correct || mark == .absent ? .white : .cocoa
    }
    private func icon(_ mark: PoemWordleEngine.Mark) -> String {
        switch mark { case .correct: "checkmark"; case .misplaced: "arrow.left.arrow.right"; case .absent: "minus" }
    }
    private func markLabel(_ mark: PoemWordleEngine.Mark) -> String {
        switch mark {
        case .correct: settings.t("字和位置正確", "字和位置正确")
        case .misplaced: settings.t("有這個字，位置不對", "有这个字，位置不对")
        case .absent: settings.t("沒有這個字，或數量已用完", "没有这个字，或数量已用完")
        }
    }
    private func rowLabel(row: Int, guess: PoemWordleEngine.Guess?, current: Bool, game: PoemWordleEngine) -> String {
        let prefix = settings.t("第 \(row + 1) 輪，", "第 \(row + 1) 轮，")
        if let guess {
            return prefix + zip(guess.keys, guess.marks).map { pair in display(pair.0, in: game) + "：" + markLabel(pair.1) }.joined(separator: "，")
        }
        return prefix + (current ? game.input.map { display($0, in: game) }.joined() : settings.t("未開始", "未开始"))
    }
}
