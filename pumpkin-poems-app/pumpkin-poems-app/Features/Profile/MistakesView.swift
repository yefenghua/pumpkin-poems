import SwiftData
import SwiftUI

/// 错题回看: open mistakes grouped by poem, each with its explanation and a retry entry.
struct MistakesView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(Router.self) private var router
    @Query(sort: \Mistake.lastWrongAt, order: .reverse) private var mistakes: [Mistake]

    private let library = PoemLibrary.shared

    var body: some View {
        let open = mistakes.filter { !$0.isResolved }
        let resolved = mistakes.count - open.count
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
                if open.isEmpty {
                    VStack(spacing: 12) {
                        MascotIllustration(size: 120)
                        Text(settings.t("錯題本是空的。", "错题本是空的。"))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color.cocoa)
                        if resolved > 0 {
                            Text(settings.t("你已經修正了 \(resolved) 道錯題。", "你已经修正了 \(resolved) 道错题。"))
                                .foregroundStyle(Color.chestnut)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                } else {
                    Button {
                        router.push(.retry(open.map(\.questionID)))
                    } label: {
                        Label(settings.t("全部重做（\(open.count) 道）", "全部重做（\(open.count) 道）"), systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    ForEach(groupedByPoem(open), id: \.poem.id) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            Button {
                                router.push(.poem(group.poem.id))
                            } label: {
                                HStack {
                                    Text("《\(settings.t(group.poem.title))》")
                                        .font(.headline)
                                        .foregroundStyle(Color.cocoa)
                                    Spacer()
                                    Text(settings.t("看釋義", "看释义"))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Color.lakeBlue)
                                }
                                .frame(minHeight: 44)
                            }
                            .buttonStyle(.plain)
                            ForEach(group.items, id: \.mistake.questionID) { item in
                                mistakeRow(item.mistake, question: item.question)
                            }
                        }
                        .card()
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

    private func mistakeRow(_ mistake: Mistake, question: Question) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(settings.t(question.prompt))
                .font(.body.weight(.medium))
                .foregroundStyle(Color.cocoa)
                .fixedSize(horizontal: false, vertical: true)
            Text(settings.t(question.explanation))
                .font(.subheadline)
                .foregroundStyle(Color.chestnut)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text(settings.t("答錯 \(mistake.wrongCount) 次", "答错 \(mistake.wrongCount) 次"))
                    .font(.caption)
                    .foregroundStyle(Color.hintRed)
                Spacer()
                Button {
                    router.push(.retry([mistake.questionID]))
                } label: {
                    Label(settings.t("再做一次", "再做一次"), systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(SoftButtonStyle(compact: true))
            }
        }
        .padding(12)
        .background(Color.cream, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private struct MistakeItem {
        let mistake: Mistake
        let question: Question
    }

    private struct PoemGroup {
        let poem: Poem
        let items: [MistakeItem]
    }

    private func groupedByPoem(_ mistakes: [Mistake]) -> [PoemGroup] {
        library.poems.compactMap { poem -> PoemGroup? in
            let items = mistakes
                .filter { $0.poemID == poem.id }
                .compactMap { mistake -> MistakeItem? in
                    poem.question(mistake.questionID).map { MistakeItem(mistake: mistake, question: $0) }
                }
            return items.isEmpty ? nil : PoemGroup(poem: poem, items: items)
        }
    }
}
