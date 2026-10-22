import SwiftData
import SwiftUI

/// 我的诗集: everything written in 小小诗人, newest first. Tap to edit; long-press to delete.
struct MyPoemsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var context
    @Query(sort: \PoemDraft.updatedAt, order: .reverse) private var drafts: [PoemDraft]
    @State private var pendingDelete: PoemDraft?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
                header
                if drafts.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: AppTheme.Spacing.item) {
                        ForEach(drafts) { draft in
                            DraftCard(draft: draft) {
                                router.push(.poetWorkshop(.edit(draft.id)))
                            } delete: {
                                pendingDelete = draft
                            }
                        }
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
        .navigationTitle(settings.t("我的詩集", "我的诗集"))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(settings.t("刪除這首作品？刪除後無法復原。", "删除这首作品？删除后无法恢复。"),
                            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button(settings.t("刪除", "删除"), role: .destructive) {
                if let pendingDelete {
                    ProgressStore(context: context).deleteDraft(pendingDelete)
                }
                pendingDelete = nil
            }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                PendingArtwork(name: ArtworkAsset.poemBookArt, compact: true)
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(drafts.isEmpty ? settings.t("還沒有作品", "还没有作品")
                                        : settings.t("收藏了 \(drafts.count) 首作品", "收藏了 \(drafts.count) 首作品"))
                        .font(.sectionTitle)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Text(settings.t("寫下的每一首，都只保存在這部裝置上。", "写下的每一首，都只保存在这台设备上。"))
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
    var delete: () -> Void

    @Environment(AppSettings.self) private var settings

    var body: some View {
        let theme = PoetWorkshopContent.theme(draft.themeID)
        Button(action: open) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(draft.title)
                        .font(.cardTitle)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .lineLimit(1)
                    Spacer()
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
            Button(role: .destructive, action: delete) { Label(settings.t("刪除", "删除"), systemImage: "trash") }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(settings.t("打開修改；長按可刪除", "打开修改；长按可删除"))
    }
}
