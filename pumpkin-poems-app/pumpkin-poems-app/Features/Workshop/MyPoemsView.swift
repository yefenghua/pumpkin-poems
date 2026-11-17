import SwiftData
import SwiftUI

/// 我的诗集: finished pieces and autosaved drafts, newest first. Tap to edit; long-press to copy or delete.
/// A deletion can be undone for a few seconds. Pieces are private to this learner; nothing is published.
struct MyPoemsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<PoemDraft> { !$0.pendingDeletion }, sort: \PoemDraft.updatedAt, order: .reverse)
    private var drafts: [PoemDraft]
    @State private var pendingDelete: PoemDraft?
    @State private var undoable: PoemDraft?
    @State private var undoTask: Task<Void, Never>?

    private var finished: [PoemDraft] { drafts.filter { $0.draftStatus == .finished } }
    private var unfinished: [PoemDraft] { drafts.filter { $0.draftStatus == .draft } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
                header
                if drafts.isEmpty {
                    emptyState
                } else {
                    if !unfinished.isEmpty {
                        section(settings.t("草稿", "草稿"), unfinished)
                    }
                    if !finished.isEmpty {
                        section(settings.t("完成的作品", "完成的作品"), finished)
                    }
                }
            }
            .padding(.horizontal, Metrics.pagePadding)
            .padding(.top, 12)
            .padding(.bottom, AppTheme.Spacing.pageBottom)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .pageBackground()
        .overlay(alignment: .bottom) {
            if let undoable {
                undoBar(undoable)
                    .padding(.horizontal, Metrics.pagePadding)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: undoable?.id)
        .navigationTitle(settings.t("我的詩集", "我的诗集"))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(settings.t("刪除這首作品？", "删除这首作品？"),
                            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button(settings.t("刪除", "删除"), role: .destructive) {
                if let pendingDelete { delete(pendingDelete) }
                pendingDelete = nil
            }
        } message: {
            Text(settings.t("刪除後幾秒內可以撤銷。", "删除后几秒内可以撤销。"))
        }
        .onDisappear { finalizeDelete() }
    }

    private func section(_ title: String, _ items: [PoemDraft]) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.item) {
            SectionHeader(title: title)
            ForEach(items) { draft in
                DraftCard(draft: draft) {
                    router.push(.poetWorkshop(.edit(draft.id)))
                } copy: {
                    ProgressStore(context: context).copyDraft(draft, suffix: settings.t("（副本）", "（副本）"))
                } delete: {
                    pendingDelete = draft
                }
            }
        }
    }

    private func undoBar(_ draft: PoemDraft) -> some View {
        HStack {
            Text(settings.t("已刪除《\(draft.title.isEmpty ? "無題" : draft.title)》", "已删除《\(draft.title.isEmpty ? "无题" : draft.title)》"))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .lineLimit(1)
            Spacer()
            Button(settings.t("撤銷", "撤销")) {
                undoTask?.cancel()
                ProgressStore(context: context).undoDelete(draft)
                undoable = nil
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(AppTheme.Colors.accentOrange)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 50)
        .background(AppTheme.Colors.surfacePaper, in: Capsule())
        .overlay(Capsule().strokeBorder(AppTheme.Colors.borderWarm, lineWidth: 1))
        .shadow(color: AppTheme.Colors.shadow.opacity(0.15), radius: 10, y: 4)
    }

    private func delete(_ draft: PoemDraft) {
        finalizeDelete()
        ProgressStore(context: context).deleteDraft(draft)
        undoable = draft
        undoTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            finalizeDelete()
        }
    }

    private func finalizeDelete() {
        undoTask?.cancel()
        guard undoable != nil else { return }
        undoable = nil
        ProgressStore(context: context).purgeDeletedDrafts()
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                PendingArtwork(name: ArtworkAsset.poemBookArt, compact: true)
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(drafts.isEmpty ? settings.t("還沒有作品", "还没有作品")
                                        : settings.t("收藏了 \(finished.count) 首作品", "收藏了 \(finished.count) 首作品"))
                        .font(.sectionTitle)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Text(settings.t("作品只有你自己看得到，不會公開。", "作品只有你自己看得到，不会公开。"))
                        .font(.footnote)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            if !drafts.isEmpty {
                Button {
                    router.push(.poetWorkshop(.new(themeID: nil)))
                } label: {
                    Label(settings.t("寫新作品", "写新作品"), systemImage: "pencil.line")
                }
                .buttonStyle(PrimaryButtonStyle(showsChevron: true))
            }
        }
        .card(padding: 14, radius: AppTheme.CornerRadius.container)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            MascotIllustration(size: 110)
            Text(settings.t("用學過的意象，寫兩句自己的詩。", "用学过的意象，写两句自己的诗。"))
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .multilineTextAlignment(.center)
            Text(settings.t("不用管平仄，先把看見的、想到的寫出來。", "不用管平仄，先把看见的、想到的写出来。"))
                .font(.subheadline)
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
            Button {
                router.push(.poetWorkshop(.new(themeID: nil)))
            } label: {
                Label(settings.t("寫第一首", "写第一首"), systemImage: "pencil.line")
            }
            .buttonStyle(PrimaryButtonStyle(showsChevron: true))
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .card(padding: AppTheme.Spacing.cardInset, radius: AppTheme.CornerRadius.container)
    }
}

/// One saved piece: title, theme and imagery chips, the lines centred like a printed poem, and the date.
struct DraftCard: View {
    let draft: PoemDraft
    var open: () -> Void
    var copy: () -> Void
    var delete: () -> Void

    @Environment(AppSettings.self) private var settings

    var body: some View {
        let theme = PoetWorkshopContent.theme(draft.themeID)
        Button(action: open) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(draft.title.isEmpty ? settings.t("（未命名）", "（未命名）") : draft.title)
                        .font(.cardTitle)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    if draft.conflictOf != nil {
                        Chip(title: settings.t("衝突副本", "冲突副本"))
                    }
                    Chip(title: draft.writingMode == .imitate ? settings.t("仿寫", "仿写") : settings.t("自由寫", "自由写"))
                    if let theme {
                        Chip(title: settings.t(theme.name))
                    }
                }
                VStack(spacing: 4) {
                    ForEach(Array(draft.lines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.title3.weight(.medium))
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(AppTheme.Colors.backgroundCream, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                HStack {
                    if let theme {
                        let used = draft.wordIDs.compactMap { id in theme.words.first { $0.id == id } }
                        if !used.isEmpty {
                            Text(settings.t("意象：", "意象：") + used.map { settings.t($0.text) }.joined(separator: "、"))
                                .font(.caption)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                        }
                    }
                    Spacer()
                    Text(draft.updatedAt.formatted(.dateTime.month().day()))
                        .font(.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
            }
            .card()
            .contentShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(action: open) { Label(settings.t("修改", "修改"), systemImage: "pencil") }
            Button(action: copy) { Label(settings.t("複製一份", "复制一份"), systemImage: "doc.on.doc") }
            Button(role: .destructive, action: delete) { Label(settings.t("刪除", "删除"), systemImage: "trash") }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(settings.t("打開修改；長按可複製或刪除", "打开修改；长按可复制或删除"))
    }
}
