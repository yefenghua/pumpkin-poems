import SwiftData
import SwiftUI

extension MistakeCategory {
    func title(_ settings: AppSettings) -> String {
        switch self {
        case .word: settings.t("字詞不理解", "字词不理解")
        case .meaning: settings.t("詩意判斷", "诗意判断")
        case .order: settings.t("順序記憶", "顺序记忆")
        case .completion: settings.t("詩句補全", "诗句补全")
        }
    }

    var systemImage: String {
        switch self {
        case .word: "character.book.closed"
        case .meaning: "lightbulb"
        case .order: "list.number"
        case .completion: "text.badge.plus"
        }
    }
}

/// How a mistake stands today, from the record and the current content.
enum MistakeState {
    /// 待巩固
    case open
    /// Corrected on the same day; leaves 待巩固 after a correct answer on a later day.
    case corrected
    /// 已巩固 — kept as history.
    case resolved
    /// The question changed since: the old version is shown and it can be practised in its new form.
    case revised
    /// The question was withdrawn (or its pack removed): kept as history, no longer counts.
    case withdrawn

    init(_ mistake: Mistake, library: PoemLibrary) {
        let current = library.question(mistake.questionID)?.question
        if library.withdrawnQuestions.contains(mistake.questionID) || current == nil {
            self = .withdrawn
        } else if mistake.isResolved {
            self = .resolved
        } else if let current, !mistake.questionRev.isEmpty, current.rev != mistake.questionRev {
            self = .revised
        } else {
            self = mistake.isCorrected ? .corrected : .open
        }
    }

    /// Still counts in 待巩固 and in review priority.
    var isOpen: Bool { self == .open || self == .corrected || self == .revised }

    func title(_ settings: AppSettings) -> String {
        switch self {
        case .open: settings.t("待鞏固", "待巩固")
        case .corrected: settings.t("已訂正 · 明天再鞏固", "已订正 · 明天再巩固")
        case .resolved: settings.t("已鞏固", "已巩固")
        case .revised: settings.t("題目已修訂", "题目已修订")
        case .withdrawn: settings.t("題目已撤回", "题目已撤回")
        }
    }

    var tint: Color {
        switch self {
        case .open: .hintRed
        case .corrected, .revised: AppTheme.Colors.accentOrange
        case .resolved: AppTheme.Colors.successGreen
        case .withdrawn: AppTheme.Colors.textSecondary
        }
    }
}

/// 错题回看: open mistakes grouped by why they were missed. Each opens the original line, the reason and a practice.
/// A mistake leaves 待巩固 only when answered correctly, without hints, on a later day; history is kept.
struct MistakesView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(Router.self) private var router
    @Query(sort: \Mistake.lastWrongAt, order: .reverse) private var mistakes: [Mistake]
    @State private var showsHistory = false

    private var library: PoemLibrary { PoemLibrary.shared }

    var body: some View {
        let library = library
        let states = Dictionary(mistakes.map { ($0.questionID, MistakeState($0, library: library)) }, uniquingKeysWith: { a, _ in a })
        let open = mistakes.filter { states[$0.questionID]?.isOpen ?? false }
        let history = mistakes.filter { !(states[$0.questionID]?.isOpen ?? false) }
        let shown = showsHistory ? history : open
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
                PillPicker(selection: $showsHistory, options: [
                    (false, settings.t("待鞏固 \(open.count)", "待巩固 \(open.count)")),
                    (true, settings.t("已鞏固／歷史 \(history.count)", "已巩固／历史 \(history.count)")),
                ])
                if shown.isEmpty {
                    VStack(spacing: 12) {
                        MascotIllustration(size: 120)
                        Text(showsHistory ? settings.t("還沒有鞏固好的錯題。", "还没有巩固好的错题。")
                                          : settings.t("沒有待鞏固的錯題。", "没有待巩固的错题。"))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color.cocoa)
                        if !showsHistory && !history.isEmpty {
                            Text(settings.t("你已經鞏固了 \(history.count) 道錯題。", "你已经巩固了 \(history.count) 道错题。"))
                                .foregroundStyle(Color.chestnut)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 30)
                } else {
                    if !showsHistory {
                        let retryable = open.filter { states[$0.questionID] != .withdrawn }.map(\.questionID)
                        Button {
                            router.push(.retry(retryable))
                        } label: {
                            Label(settings.t("全部再練一次（\(retryable.count) 道）", "全部再练一次（\(retryable.count) 道）"),
                                  systemImage: "arrow.counterclockwise")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        Text(settings.t("隔天不用提示答對，才會移出「待鞏固」。", "隔天不用提示答对，才会移出“待巩固”。"))
                            .font(.footnote)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                    ForEach(MistakeCategory.allCases, id: \.self) { category in
                        let items = shown.filter { categoryOf($0) == category }
                        if !items.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Label(category.title(settings), systemImage: category.systemImage)
                                    .font(.headline)
                                    .foregroundStyle(AppTheme.Colors.textPrimary)
                                ForEach(items, id: \.questionID) { mistake in
                                    row(mistake, state: states[mistake.questionID] ?? .open)
                                }
                            }
                            .card()
                        }
                    }
                }
            }
            .padding(.horizontal, Metrics.pagePadding)
            .padding(.top, 12).padding(.bottom, AppTheme.Spacing.pageBottom)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .pageBackground()
        .navigationTitle(settings.t("錯題回看", "错题回看"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func categoryOf(_ mistake: Mistake) -> MistakeCategory {
        MistakeCategory(rawValue: mistake.category) ?? library.question(mistake.questionID)?.question.mistakeCategory ?? .meaning
    }

    private func row(_ mistake: Mistake, state: MistakeState) -> some View {
        let found = library.question(mistake.questionID)
        let prompt = found.map { settings.t($0.question.prompt) } ?? mistake.questionSnapshot.map { settings.t($0.prompt) } ?? ""
        return Button {
            router.push(.mistakeDetail(mistake.questionID))
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                if let poem = found?.poem ?? library.poem(mistake.poemID) {
                    Text("《\(settings.t(poem.title))》")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                Text(prompt)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.cocoa)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text(state.title(settings))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(state.tint)
                    Text(settings.t("答錯 \(mistake.wrongCount) 次", "答错 \(mistake.wrongCount) 次"))
                        .font(.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.Colors.accentOrange)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.cream, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// One mistake: first the original line(s), then why the answer was wrong, then a practice of the same point.
struct MistakeDetailView: View {
    let questionID: String

    @Environment(AppSettings.self) private var settings
    @Environment(Router.self) private var router
    @Query private var mistakes: [Mistake]

    init(questionID: String) {
        self.questionID = questionID
        _mistakes = Query(filter: #Predicate<Mistake> { $0.questionID == questionID })
    }

    var body: some View {
        let library = PoemLibrary.shared
        let found = library.question(questionID)
        let mistake = mistakes.first
        let state = mistake.map { MistakeState($0, library: library) } ?? .open
        let snapshot = mistake?.questionSnapshot
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
                if let found {
                    originalLines(found.poem, found.question)
                }
                reason(found?.question, snapshot: snapshot, state: state, mistake: mistake)
                practice(state: state, isAvailable: found != nil)
            }
            .padding(.horizontal, Metrics.pagePadding)
            .padding(.top, 12).padding(.bottom, AppTheme.Spacing.pageBottom)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .pageBackground()
        .navigationTitle(settings.t("錯題", "错题"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func originalLines(_ poem: Poem, _ question: Question) -> some View {
        let lines = question.lineIDs.compactMap(poem.line)
        return VStack(alignment: .leading, spacing: 10) {
            Label(settings.t("先看原句", "先看原句"), systemImage: "1.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.Colors.textSecondary)
            VStack(spacing: 6) {
                ForEach(lines) { line in
                    Text(settings.t(line.text))
                        .poemFont()
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                }
                Text("《\(settings.t(poem.title))》" + poem.byline(settings))
                    .font(.footnote)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(AppTheme.Colors.highlightCream, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            if lines.count == 1, let line = lines.first {
                Text(settings.t("這句的意思：", "这句的意思：") + settings.t(line.explain))
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                router.push(.poem(poem.id))
            } label: {
                Text(settings.t("打開整首詩", "打开整首诗"))
            }
            .buttonStyle(SoftButtonStyle(compact: true))
        }
        .card()
    }

    @ViewBuilder
    private func reason(_ question: Question?, snapshot: LearningEventPayload.QuestionSnapshot?, state: MistakeState,
                        mistake: Mistake?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(settings.t("錯在哪裏", "错在哪里"), systemImage: "2.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                Spacer()
                Text(state.title(settings))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(state.tint)
            }
            if let category = (mistake.flatMap { MistakeCategory(rawValue: $0.category) } ?? question?.mistakeCategory) {
                Label(category.title(settings), systemImage: category.systemImage)
                    .font(.headline)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
            }
            // A revised or withdrawn question is shown as it was when it was missed.
            if (state == .revised || state == .withdrawn), let snapshot {
                Text(settings.t("當時的題目：", "当时的题目：") + settings.t(snapshot.prompt))
                    .font(.body)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let answer = snapshot.answer {
                    Text(settings.t("當時的答案：", "当时的答案：") + settings.t(answer))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                }
                Text(settings.t(snapshot.explanation))
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(state == .revised
                     ? settings.t("這道題後來修訂了，下面練習的是新版本。", "这道题后来修订了，下面练习的是新版本。")
                     : settings.t("這道題已撤回，只保留記錄，不再影響學習判斷。", "这道题已撤回，只保留记录，不再影响学习判断。"))
                    .font(.footnote)
                    .foregroundStyle(AppTheme.Colors.accentOrange)
            } else if let question {
                Text(settings.t(question.prompt))
                    .font(.body)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let answer = question.answer, question.options.indices.contains(answer) {
                    Text(settings.t("正確答案：", "正确答案：") + settings.t(question.options[answer]))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                }
                Text(settings.t(question.explanation))
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let mistake {
                Text(settings.t("答錯 \(mistake.wrongCount) 次，最近一次 ", "答错 \(mistake.wrongCount) 次，最近一次 ")
                     + mistake.lastWrongAt.formatted(.dateTime.month().day()))
                    .font(.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
        }
        .card()
    }

    private func practice(state: MistakeState, isAvailable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(settings.t("再練一次", "再练一次"), systemImage: "3.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.Colors.textSecondary)
            if isAvailable && state != .withdrawn {
                Text(settings.t("這個知識點目前只有這一道題，所以是同一題再次練習。", "这个知识点目前只有这一道题，所以是同一题再次练习。"))
                    .font(.footnote)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    router.push(.retry([questionID]))
                } label: {
                    Label(settings.t("再次練習（同一題）", "再次练习（同一题）"), systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(PrimaryButtonStyle())
            } else {
                Text(settings.t("這道題已經不能練習了。", "这道题已经不能练习了。"))
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
        }
        .card()
    }
}
