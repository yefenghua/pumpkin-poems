import SwiftData
import SwiftUI

/// 巩固小测: meaning, line matching, fill-in, next line and ordering, each with an explanation.
/// Answer state is never revealed before submitting. The first attempt is what gets scored;
/// "再试一次" is for learning and does not change the score.
struct QuizView: View {
    enum Mode: Hashable {
        /// Full five-question quiz for a poem.
        case poem(String)
        /// Retry specific questions from 错题回看.
        case retry([String])
    }

    private struct Item: Identifiable {
        let poem: Poem
        let question: Question
        var id: String { question.id }
    }

    let mode: Mode

    @Environment(AppSettings.self) private var settings
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var context

    @State private var index = 0
    @State private var selected: Int?
    @State private var order: [Int] = []
    @State private var submitted = false
    @State private var lastCorrect = false
    @State private var firstAnswers: [String: Bool] = [:]
    @State private var outcome: QuizOutcome?
    @State private var retryResolved: Int?

    private var store: ProgressStore { ProgressStore(context: context) }

    private var items: [Item] {
        let library = PoemLibrary.shared
        switch mode {
        case .poem(let id):
            guard let poem = library.poem(id) else { return [] }
            return poem.questions.map { Item(poem: poem, question: $0) }
        case .retry(let ids):
            return ids.compactMap { id in
                library.poems.lazy.compactMap { poem in poem.question(id).map { Item(poem: poem, question: $0) } }.first
            }
        }
    }

    var body: some View {
        Group {
            if let outcome, case .poem(let id) = mode, let poem = PoemLibrary.shared.poem(id) {
                QuizCompletionView(poem: poem, outcome: outcome) { restart() }
            } else if let retryResolved {
                retrySummary(resolved: retryResolved)
            } else if items.indices.contains(index) {
                questionPage(items[index])
            } else {
                ContentUnavailableView(settings.t("沒有需要練習的題目", "没有需要练习的题目"), systemImage: "checkmark.circle")
            }
        }
        .pageBackground()
        #if DEBUG
        .onAppear {
            // `-demoQuizDone YES`: jump straight to the completion page with a perfect round, for screenshots.
            guard outcome == nil, UserDefaults.standard.bool(forKey: "demoQuizDone"),
                  case .poem(let id) = mode, let poem = PoemLibrary.shared.poem(id) else { return }
            let answers = Dictionary(uniqueKeysWithValues: poem.questions.map { ($0.id, true) })
            outcome = store.recordQuiz(poem: poem, answers: answers)
        }
        #endif
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var navigationTitle: String {
        switch mode {
        case .poem: settings.t("小測", "小测")
        case .retry: settings.t("錯題重做", "错题重做")
        }
    }

    // MARK: Question page

    private func questionPage(_ item: Item) -> some View {
        let question = item.question
        return ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
                HStack {
                    Text(settings.t("第 \(index + 1) / \(items.count) 題", "第 \(index + 1) / \(items.count) 题"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.chestnut)
                    Spacer()
                    Chip(title: kindTitle(question.kind))
                }
                ProgressView(value: Double(index), total: Double(max(items.count, 1)))
                    .tint(.pumpkinGold)

                if case .retry = mode {
                    Text("《\(settings.t(item.poem.title))》")
                        .font(.subheadline)
                        .foregroundStyle(Color.chestnut)
                }

                Text(settings.t(question.prompt))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.cocoa)
                    .fixedSize(horizontal: false, vertical: true)

                if let context = question.context {
                    Text(settings.t(context))
                        .poemFont()
                        .foregroundStyle(Color.cocoa)
                        .frame(maxWidth: .infinity)
                        .card(fill: .paleGoldFill)
                }

                if question.kind == .order {
                    orderPicker(question)
                } else {
                    VStack(spacing: 12) {
                        ForEach(question.options.indices, id: \.self) { option in
                            optionButton(question, option: option)
                        }
                    }
                }

                if submitted {
                    feedback(question)
                } else {
                    Button {
                        submit(item)
                    } label: {
                        Text(settings.t("提交", "提交"))
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!canSubmit(question))
                }
            }
            .padding(.horizontal, Metrics.pagePadding)
            .padding(.top, 12).padding(.bottom, AppTheme.Spacing.pageBottom)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .id(question.id)
    }

    private func optionButton(_ question: Question, option: Int) -> some View {
        let state: OptionCard.State
        if submitted {
            if option == question.answer { state = .correct }
            else if option == selected { state = .needsFix }
            else { state = .dimmed }
        } else {
            state = selected == option ? .selected : .normal
        }
        return Button {
            selected = option
        } label: {
            OptionCard(text: settings.t(question.options[option]), state: state,
                       large: question.kind == .fill)
        }
        .buttonStyle(.plain)
        .disabled(submitted)
    }

    /// Tap-to-place ordering: works without dragging and with VoiceOver.
    private func orderPicker(_ question: Question) -> some View {
        let answerOrder = question.answerOrder ?? []
        return VStack(alignment: .leading, spacing: 12) {
            Text(settings.t("你的順序（點一下可以移回）", "你的顺序（点一下可以移回）"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.chestnut)
            VStack(spacing: 10) {
                ForEach(0..<question.options.count, id: \.self) { slot in
                    if slot < order.count {
                        let option = order[slot]
                        let state: OptionCard.State = submitted
                            ? (answerOrder.indices.contains(slot) && answerOrder[slot] == option ? .correct : .needsFix)
                            : .selected
                        Button {
                            order.remove(at: slot)
                        } label: {
                            OptionCard(text: settings.t(question.options[option]), state: state, number: slot + 1)
                        }
                        .buttonStyle(.plain)
                        .disabled(submitted)
                        .accessibilityHint(settings.t("移回待選", "移回待选"))
                    } else {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.chestnut.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                            .frame(height: 56)
                            .overlay(Text("\(slot + 1)").font(.headline).foregroundStyle(Color.chestnut.opacity(0.6)))
                            .accessibilityLabel(settings.t("第 \(slot + 1) 句，未選", "第 \(slot + 1) 句，未选"))
                    }
                }
            }
            let remaining = question.options.indices.filter { !order.contains($0) }
            if !remaining.isEmpty && !submitted {
                Text(settings.t("待選詩句", "待选诗句"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.chestnut)
                    .padding(.top, 4)
                VStack(spacing: 10) {
                    ForEach(remaining, id: \.self) { option in
                        Button {
                            order.append(option)
                        } label: {
                            OptionCard(text: settings.t(question.options[option]), state: .normal)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(settings.t("放到下一個位置", "放到下一个位置"))
                    }
                }
            }
        }
    }

    private func feedback(_ question: Question) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                MascotIllustration(size: 56)
                VStack(alignment: .leading, spacing: 6) {
                    Label(lastCorrect ? settings.t("答對了！", "答对了！") : settings.t("再看看這裏", "再看看这里"),
                          systemImage: lastCorrect ? "checkmark.circle.fill" : "arrow.uturn.backward.circle.fill")
                        .font(.headline)
                        .foregroundStyle(lastCorrect ? Color.deepLeaf : Color.hintRed)
                    if !lastCorrect, let answer = question.answer {
                        Text(settings.t("正確答案：", "正确答案：") + settings.t(question.options[answer]))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.cocoa)
                    }
                    Text(settings.t(question.explanation))
                        .font(.body)
                        .lineSpacing(4)
                        .foregroundStyle(Color.cocoa)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .card(fill: lastCorrect ? .paleGreenFill : .paleRedFill)

            if !lastCorrect {
                Button {
                    selected = nil
                    order = []
                    submitted = false
                } label: {
                    Label(settings.t("再試一次", "再试一次"), systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(SoftButtonStyle())
            }
            Button {
                next()
            } label: {
                Text(index + 1 < items.count ? settings.t("下一題", "下一题") : settings.t("看結果", "看结果"))
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .transition(.opacity)
    }

    private func retrySummary(resolved: Int) -> some View {
        VStack(spacing: AppTheme.Spacing.section) {
            MascotIllustration(size: 140)
            Text(resolved > 0
                 ? settings.t("你修正了 \(resolved) 道錯題，有進步！", "你修正了 \(resolved) 道错题，有进步！")
                 : settings.t("這些題目還可以再看看解釋，下次再試。", "这些题目还可以再看看解释，下次再试。"))
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.cocoa)
                .multilineTextAlignment(.center)
            Button {
                router.pop()
            } label: {
                Text(settings.t("完成", "完成"))
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(Metrics.pagePadding)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Actions

    private func canSubmit(_ question: Question) -> Bool {
        question.kind == .order ? order.count == question.options.count : selected != nil
    }

    private func submit(_ item: Item) {
        let question = item.question
        let correct = question.kind == .order ? order == question.answerOrder : selected == question.answer
        if firstAnswers[question.id] == nil {
            firstAnswers[question.id] = correct
        }
        withAnimation(.easeOut(duration: 0.2)) {
            lastCorrect = correct
            submitted = true
        }
    }

    private func next() {
        if index + 1 < items.count {
            index += 1
            selected = nil
            order = []
            submitted = false
            return
        }
        switch mode {
        case .poem(let id):
            guard let poem = PoemLibrary.shared.poem(id) else { return }
            outcome = store.recordQuiz(poem: poem, answers: firstAnswers)
        case .retry:
            var resolved = 0
            for item in items {
                if store.recordRetry(questionID: item.question.id, poemID: item.poem.id,
                                     correct: firstAnswers[item.question.id] ?? false) {
                    resolved += 1
                }
            }
            retryResolved = resolved
        }
    }

    private func restart() {
        index = 0
        selected = nil
        order = []
        submitted = false
        firstAnswers = [:]
        outcome = nil
    }

    private func kindTitle(_ kind: Question.Kind) -> String {
        switch kind {
        case .meaning: settings.t("詩意理解", "诗意理解")
        case .match: settings.t("詩意配對", "诗意配对")
        case .fill: settings.t("關鍵字填空", "关键字填空")
        case .next: settings.t("上下句", "上下句")
        case .order: settings.t("詩句排序", "诗句排序")
        }
    }
}

/// Answer option. Selected: deep blue border, light blue fill, check icon.
/// After submitting: green for correct, gentle red for the choice that needs fixing.
struct OptionCard: View {
    enum State { case normal, selected, correct, needsFix, dimmed }

    let text: String
    let state: State
    var number: Int?
    var large = false

    var body: some View {
        HStack(spacing: 12) {
            if let number {
                Text("\(number)")
                    .font(.headline)
                    .foregroundStyle(Color.lakeBlue)
                    .frame(width: 28, height: 28)
                    .background(Color.paleBlueFill, in: Circle())
            }
            Text(text)
                .font(large ? .title2.weight(.semibold) : .title3)
                .foregroundStyle(Color.cocoa)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let icon {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(border)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(minHeight: 56)
        .background(fill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(border, lineWidth: state == .normal ? 1.5 : 2.5))
        .opacity(state == .dimmed ? 0.6 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(state == .selected ? [.isButton, .isSelected] : .isButton)
    }

    private var fill: Color {
        switch state {
        case .normal, .dimmed: .warmWhite
        case .selected: .paleBlueFill
        case .correct: .paleGreenFill
        case .needsFix: .paleRedFill
        }
    }

    private var border: Color {
        switch state {
        case .normal, .dimmed: Color.chestnut.opacity(0.3)
        case .selected: .lakeBlue
        case .correct: .deepLeaf
        case .needsFix: .hintRed
        }
    }

    private var icon: String? {
        switch state {
        case .normal, .dimmed: nil
        case .selected: "checkmark.circle.fill"
        case .correct: "checkmark.seal.fill"
        case .needsFix: "arrow.uturn.backward.circle"
        }
    }
}
