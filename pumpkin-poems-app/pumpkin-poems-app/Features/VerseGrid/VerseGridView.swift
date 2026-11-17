import SwiftData
import SwiftUI

/// Find complete verses in one continuous drag; lifting the finger submits the path.
struct VerseGridView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SpeechPlayer.self) private var speech
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var size = 6
    @State private var selectedPoemIDs: Set<String> = []
    @State private var preparedPuzzle: VerseGridPuzzle?
    @State private var preparedFor = ""
    @State private var preparing = false
    @State private var preparationRound = 0
    @State private var engine: VerseGridEngine?
    @State private var isDragging = false
    @State private var speechEnabled = false
    @State private var hintIndex: Int?
    @State private var message = ""
    @State private var lastMatchedID: String?
    @State private var savedResult = false
    @State private var confirmNewGame = false
    @State private var showRules = false

    private var corpus: GameCorpus { GameCorpus.shared }
    private var preparationID: String {
        "\(size):\(preparationRound):" + selectedPoemIDs.sorted().joined(separator: ",")
    }
    private var canStart: Bool { preparedPuzzle != nil && preparedFor == preparationID && !preparing }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let engine {
                    gameHeader(engine)
                    board(engine)
                    selectionControls(engine)
                    clues(engine)
                    if engine.isComplete { completion(engine) }
                } else {
                    setup
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
        .scrollDisabled(isDragging)
        .pageBackground()
        .navigationTitle(settings.t("劃字尋詩", "划字寻诗"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                GameSoundControls()
                Button { showRules = true } label: { Image(systemName: "questionmark.circle") }
                    .accessibilityLabel(settings.t("遊戲規則", "游戏规则"))
            }
        }
        .sheet(isPresented: $showRules) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(settings.t("從首字開始拖曳，放手提交。可轉彎、跨格；一句內每格只用一次。", "从首字开始拖拽，松手提交。可转弯、跨格；一句内每格只用一次。"))
                        Text(settings.t("同字需用不同格。拖回上一格可退字，沿空隙移動可避開其他字。", "同字需用不同格。拖回上一格可退字，沿空隙移动可避开其他字。"))
                        Text(settings.t("依篇名線索找齊所有詩句。", "依篇名线索找齐所有诗句。"))
                    }.padding()
                }
                .navigationTitle(settings.t("怎樣玩", "怎么玩"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) {
                    Button(settings.t("明白了", "明白了")) { showRules = false }
                } }
            }
            .presentationDetents([.medium, .large])
        }
        .confirmationDialog(settings.t("重新開局？本局尋詩進度會重來。", "重新开局？本局寻诗进度会重来。"),
                            isPresented: $confirmNewGame, titleVisibility: .visible) {
            Button(settings.t("重新開局", "重新开局"), action: returnToSetup)
        }
        .onChange(of: settings.script) { _, _ in cancelSelection() }
        .onChange(of: speechEnabled) { _, enabled in
            if enabled && !speech.hasVoice(for: settings.voice) {
                speechEnabled = false
                message = settings.t("所選語音未就緒，請先到設定下載並試聽。", "所选语音未就绪，请先到设置下载并试听。")
            }
            speech.stop()
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { cancelSelection() } }
        .task(id: preparationID) { await preparePuzzle() }
        .onDisappear { cancelSelection(); GameFeedback.shared.endSession() }
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(settings.t("把散落的字，連回一首詩", "把散落的字，连回一首诗"), systemImage: "hand.draw.fill")
                .font(.title2.bold()).foregroundStyle(Color.cocoa)
            Text(settings.t("從首字拖到末字，找齊所有詩句。", "从首字拖到末字，找齐所有诗句。"))
                .foregroundStyle(Color.chestnut)
            Picker(settings.t("棋盤", "棋盘"), selection: $size) {
                Text(settings.t("輕鬆 6×6", "轻松 6×6")).tag(6)
                Text(settings.t("挑戰 7×7", "挑战 7×7")).tag(7)
            }.pickerStyle(.segmented)
            Text(size == 6 ? settings.t("找出 3 句五言詩", "找出 3 句五言诗")
                 : settings.t("找出 4 句五言／七言詩", "找出 4 句五言／七言诗"))
                .font(.subheadline).foregroundStyle(Color.chestnut)
            GameLibraryPicker(selection: $selectedPoemIDs)
            if preparing {
                ProgressView(settings.t("正在準備…", "正在准备…"))
            } else if !canStart && !selectedPoemIDs.isEmpty {
                Text(settings.t("請多選一些詩", "请多选一些诗"))
                    .foregroundStyle(Color.chestnut).font(.callout)
            }
            settingsControls
            Button(action: startGame) {
                Label(settings.t("開始尋詩", "开始寻诗"), systemImage: "play.fill")
            }.buttonStyle(PrimaryButtonStyle()).disabled(!canStart)
                .accessibilityIdentifier("verse-grid.start")
            ScriptAndVoiceMenus()
            if !message.isEmpty { Text(message).foregroundStyle(Color.hintRed) }
        }.card()
    }

    private var settingsControls: some View {
        VStack(spacing: 8) {
            Toggle(settings.t("逐字朗讀", "逐字朗读"), isOn: $speechEnabled)
            Text(settings.voice == .cantonese ? settings.t("朗讀語言：粵語", "朗读语言：粤语")
                 : settings.t("朗讀語言：普通話", "朗读语言：普通话"))
                .font(.caption).foregroundStyle(Color.chestnut).frame(maxWidth: .infinity, alignment: .leading)
        }.tint(Color.pumpkinOrange)
    }

    private func gameHeader(_ engine: VerseGridEngine) -> some View {
        VStack(spacing: 8) {
            HStack {
                Label(settings.t("已找到 \(engine.foundIDs.count)／\(engine.puzzle.targets.count) 句", "已找到 \(engine.foundIDs.count)／\(engine.puzzle.targets.count) 句"), systemImage: "sparkles")
                    .font(.headline)
                Spacer()
                Button(settings.t("新一局", "新一局")) {
                    if engine.isComplete { returnToSetup() }
                    else { confirmNewGame = true }
                }.font(.subheadline)
            }
            Text(settings.t("可轉彎、跨格，放手提交", "可转弯、跨格，松手提交"))
                .font(.caption).foregroundStyle(Color.chestnut)
        }
    }

    private func board(_ engine: VerseGridEngine) -> some View {
        GeometryReader { geometry in
            let boardWidth = geometry.size.width
            let gap: CGFloat = 4
            let cellWidth = (boardWidth - gap * CGFloat(engine.puzzle.size - 1)) / CGFloat(engine.puzzle.size)
            ZStack(alignment: .topLeading) {
                ForEach(engine.puzzle.targets) { target in
                    if let path = engine.foundPaths[target.id] {
                        trace(path, size: engine.puzzle.size, cellWidth: cellWidth, gap: gap)
                            .stroke(Color.deepLeaf.opacity(0.3), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                    }
                }
                trace(engine.selection, size: engine.puzzle.size, cellWidth: cellWidth, gap: gap)
                    .stroke(Color.lakeBlue.opacity(0.65), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                VStack(spacing: gap) {
                    ForEach(0..<engine.puzzle.size, id: \.self) { row in
                        HStack(spacing: gap) {
                            ForEach(0..<engine.puzzle.size, id: \.self) { column in
                                let index = row * engine.puzzle.size + column
                                cell(index, engine: engine, width: cellWidth)
                            }
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            .highPriorityGesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard !engine.isComplete else { return }
                    if !isDragging { self.engine?.clearSelection(); isDragging = true; message = "" }
                    if let index = hitTest(value.location, size: engine.puzzle.size, cellWidth: cellWidth, gap: gap) {
                        select(index)
                    }
                }
                .onEnded { _ in
                    guard isDragging else { return }
                    isDragging = false
                    submit()
                }, including: .all)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityIdentifier("verse-grid.board")
    }

    private func cell(_ index: Int, engine: VerseGridEngine, width: CGFloat) -> some View {
        let selected = engine.selection.firstIndex(of: index)
        let found = engine.foundPaths.values.contains { $0.contains(index) }
        return Text(settings.t(engine.puzzle.cells[index].text))
            .font(.system(size: min(26, width * 0.53), weight: .semibold, design: .serif))
            .foregroundStyle(selected != nil ? Color.white : Color.cocoa)
            .frame(width: width, height: width)
            .background(selected != nil ? Color.lakeBlue : found ? Color.paleGreenFill : Color.warmWhite,
                        in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(
                hintIndex == index ? Color.pumpkinOrange : found ? Color.deepLeaf : Color.paleGoldLine,
                lineWidth: hintIndex == index ? 3 : 1))
            .overlay(alignment: .topLeading) {
                if let selected {
                    Text("\(selected + 1)").font(.system(size: 9, weight: .bold)).foregroundStyle(.white).padding(3)
                } else if hintIndex == index {
                    Image(systemName: "sparkle").font(.system(size: 9)).foregroundStyle(Color.pumpkinOrange).padding(3)
                }
            }
            .contentShape(Rectangle())
            .accessibilityLabel(settings.t(engine.puzzle.cells[index].text)
                + settings.t("，第 \(index / engine.puzzle.size + 1) 行，第 \(index % engine.puzzle.size + 1) 列", "，第 \(index / engine.puzzle.size + 1) 行，第 \(index % engine.puzzle.size + 1) 列"))
            .accessibilityValue(selected.map { settings.t("第 \($0 + 1) 字", "第 \($0 + 1) 字") } ?? "")
    }

    private func trace(_ path: [Int], size: Int, cellWidth: CGFloat, gap: CGFloat) -> Path {
        Path { drawing in
            for (offset, index) in path.enumerated() {
                let point = CGPoint(x: CGFloat(index % size) * (cellWidth + gap) + cellWidth / 2,
                                    y: CGFloat(index / size) * (cellWidth + gap) + cellWidth / 2)
                if offset == 0 { drawing.move(to: point) } else { drawing.addLine(to: point) }
            }
        }
    }

    private func hitTest(_ point: CGPoint, size: Int, cellWidth: CGFloat, gap: CGFloat) -> Int? {
        guard point.x >= 0, point.y >= 0 else { return nil }
        let column = Int(point.x / (cellWidth + gap)), row = Int(point.y / (cellWidth + gap))
        guard row < size, column < size,
              point.x - CGFloat(column) * (cellWidth + gap) <= cellWidth,
              point.y - CGFloat(row) * (cellWidth + gap) <= cellWidth else { return nil }
        return row * size + column
    }

    private func selectionControls(_ engine: VerseGridEngine) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(engine.selection.isEmpty ? settings.t("從第一個字開始…", "从第一个字开始…") : engine.selectedText(settings.script))
                    .font(.title3.weight(.semibold)).foregroundStyle(Color.cocoa)
                    .minimumScaleFactor(0.7).lineLimit(1)
                Spacer(minLength: 4)
                Text("\(engine.selection.count) / \(engine.longestTarget)").font(.caption.monospacedDigit()).foregroundStyle(Color.chestnut)
            }
            if !message.isEmpty {
                Text(message).font(.subheadline).foregroundStyle(lastMatchedID == nil ? Color.chestnut : Color.deepLeaf)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("verse-grid.feedback")
            }
            if !engine.isComplete {
                HStack {
                    Button {
                        hintIndex = self.engine?.revealStart()
                        GameFeedback.shared.play(.tap)
                        message = settings.t("從橙框的字開始。", "从橙框的字开始。")
                        lastMatchedID = nil
                    } label: { Label(settings.t("提示首字", "提示首字"), systemImage: "lightbulb") }
                    Spacer()
                    Text(settings.t("提示 \(engine.hintsUsed) 次", "提示 \(engine.hintsUsed) 次"))
                        .font(.caption).foregroundStyle(Color.chestnut)
                }.font(.subheadline)
            }
            if !engine.isComplete { settingsControls }
        }.card(padding: 12)
    }

    private func clues(_ engine: VerseGridEngine) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(settings.t("尋詩線索", "寻诗线索")).font(.headline)
            ForEach(engine.puzzle.targets) { target in
                let found = engine.foundIDs.contains(target.id)
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: found ? "checkmark.circle.fill" : "magnifyingglass")
                        .foregroundStyle(found ? Color.deepLeaf : Color.chestnut)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(found ? settings.t(target.verse.text)
                             : settings.t("\(target.path.count) 個字 · 《\(settings.t(target.verse.title))》", "\(target.path.count) 个字 ·《\(settings.t(target.verse.title))》"))
                            .font(.subheadline.weight(.semibold))
                        Text(settings.t(target.verse.author) + (found ? " ·《\(settings.t(target.verse.title))》" : ""))
                            .font(.caption).foregroundStyle(Color.chestnut)
                    }
                    Spacer(minLength: 0)
                    if found {
                        Button {
                            speech.speak([(target.id, settings.spoken(target.verse.text))], language: settings.voice)
                        } label: { Image(systemName: "speaker.wave.2") }
                            .frame(minWidth: 44, minHeight: 44)
                            .accessibilityLabel(settings.t("朗讀找到的詩句", "朗读找到的诗句"))
                    }
                }
            }
        }.card(padding: 14)
    }

    private func completion(_ engine: VerseGridEngine) -> some View {
        VStack(spacing: 10) {
            Label(settings.t("全部找到了！", "全部找到了！"), systemImage: "star.circle.fill")
                .font(.title2.bold()).foregroundStyle(Color.deepLeaf)
            Text(settings.t("找到 \(engine.foundIDs.count) 句 · 使用 \(engine.hintsUsed) 次提示", "找到 \(engine.foundIDs.count) 句 · 使用 \(engine.hintsUsed) 次提示"))
                .font(.subheadline).foregroundStyle(Color.chestnut)
            Button(settings.t("再尋一局", "再寻一局"), action: returnToSetup).buttonStyle(PrimaryButtonStyle())
        }.card()
    }

    private func preparePuzzle() async {
        let identifier = preparationID
        preparedPuzzle = nil
        preparedFor = ""
        guard !selectedPoemIDs.isEmpty else { preparing = false; return }
        preparing = true
        let selectedSize = size
        let verses = corpus.verses.filter {
            selectedPoemIDs.contains($0.poemID) && (selectedSize != 6 || $0.text.hans.count == 5)
        }
        let normalizer = corpus.normalizer
        let job = Task.detached(priority: .userInitiated) {
            VerseGridPuzzle.make(verses: verses, size: selectedSize, targetCount: selectedSize == 6 ? 3 : 4,
                                 normalizer: normalizer)
        }
        let puzzle = await withTaskCancellationHandler(operation: { await job.value }, onCancel: { job.cancel() })
        guard !Task.isCancelled, preparationID == identifier else { return }
        preparedPuzzle = puzzle
        preparedFor = identifier
        preparing = false
    }

    private func startGame() {
        guard canStart, let puzzle = preparedPuzzle else { return }
        speech.stop()
        engine = VerseGridEngine(puzzle: puzzle, normalizer: corpus.normalizer)
        hintIndex = nil
        message = ""
        lastMatchedID = nil
        savedResult = false
        isDragging = false
        GameFeedback.shared.beginSession()
        GameFeedback.shared.play(.tap)
    }

    private func returnToSetup() {
        cancelSelection()
        GameFeedback.shared.endSession()
        engine = nil
        message = ""
        preparationRound += 1
    }

    private func select(_ index: Int) {
        guard let change = engine?.select(index) else { return }
        if change == .added {
            message = ""
            lastMatchedID = nil
            GameFeedback.shared.play(.tap)
            if speechEnabled, let text = engine?.puzzle.cells[index].text, speech.hasVoice(for: settings.voice) {
                speech.speak([("grid-cell-\(index)", settings.spoken(text))], language: settings.voice)
            }
        } else if change == .backtracked { speech.stop(); GameFeedback.shared.play(.tap) }
    }

    private func cancelSelection() {
        isDragging = false
        engine?.clearSelection()
        speech.stop()
    }

    private func submit() {
        guard let result = engine?.submit() else { return }
        speech.stop()
        lastMatchedID = nil
        switch result {
        case .found(let id):
            GameFeedback.shared.play(engine?.isComplete == true ? .complete : .success)
            lastMatchedID = id
            hintIndex = nil
            let verse = engine?.puzzle.targets.first { $0.id == id }?.verse
            message = settings.t("找到了：", "找到了：") + (verse.map { settings.t($0.text) } ?? "")
        case .alreadyFound:
            GameFeedback.shared.play(.error)
            message = settings.t("這句已找到，換一句試試。", "这句已找到，换一句试试。")
        case .notTarget:
            GameFeedback.shared.play(.error)
            message = settings.t("看看篇名線索，再試一次。", "看看篇名线索，再试一次。")
        case .empty: return
        }
        if let engine, engine.isComplete, !savedResult {
            savedResult = true
            _ = ProgressStore(context: context).recordGame(mode: "verse-grid", character: "\(size)", score: engine.foundIDs.count)
        }
    }
}
