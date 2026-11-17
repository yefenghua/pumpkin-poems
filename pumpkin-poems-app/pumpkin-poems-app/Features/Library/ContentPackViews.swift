import SwiftData
import SwiftUI

/// 诗库 → 主题包: the downloadable theme packs from the published manifest, with their state.
/// Hidden when there is no manifest yet and nothing is installed, so an offline first launch stays clean.
struct ContentPacksSection: View {
    @Environment(AppSettings.self) private var settings
    @Environment(Router.self) private var router
    @Environment(ContentStore.self) private var content

    var body: some View {
        if !content.packs.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: settings.t("主題包", "主题包"),
                              subtitle: settings.t("下載後可離線學習", "下载后可离线学习"))
                ForEach(content.packs) { pack in
                    Button {
                        router.push(.contentPack(pack.id))
                    } label: {
                        ContentPackRow(pack: pack, state: content.state(of: pack))
                    }
                    .buttonStyle(.plain)
                }
            }
        } else if content.manifestError != nil, !content.installedPackIDs.isEmpty {
            Label(settings.t("暫時連不上內容服務，已下載的主題包照常可用。", "暂时连不上内容服务，已下载的主题包照常可用。"),
                  systemImage: "icloud.slash")
                .font(.footnote)
                .foregroundStyle(AppTheme.Colors.textSecondary)
        }
    }
}

struct ContentPackRow: View {
    let pack: ContentPackInfo
    let state: ContentStore.PackState

    @Environment(AppSettings.self) private var settings

    var body: some View {
        HStack(spacing: 12) {
            ThemeThumbnail(theme: PoemVisualTheme(themeID: pack.id), size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(settings.t(pack.title))
                    .font(.headline)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Text(settings.t("\(pack.poemCount) 首 · ", "\(pack.poemCount) 首 · ") + ByteCountFormatter.string(fromByteCount: Int64(pack.size), countStyle: .file))
                    .font(.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            Spacer(minLength: 6)
            PackStateBadge(state: state)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.Colors.accentOrange)
        }
        .card(padding: 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct PackStateBadge: View {
    let state: ContentStore.PackState

    @Environment(AppSettings.self) private var settings

    var body: some View {
        switch state {
        case .notDownloaded:
            Chip(title: settings.t("未下載", "未下载"), systemImage: "arrow.down.circle")
        case .downloading(let progress):
            Chip(title: "\(Int(progress * 100))%", systemImage: "arrow.down.circle.dotted")
        case .installed:
            Chip(title: settings.t("可用", "可用"), systemImage: "checkmark.circle.fill", isSelected: true,
                 tint: AppTheme.Colors.successGreen)
        case .updateAvailable:
            Chip(title: settings.t("有更新", "有更新"), systemImage: "arrow.triangle.2.circlepath", isSelected: true)
        case .failed:
            Chip(title: settings.t("更新失敗", "更新失败"), systemImage: "exclamationmark.triangle", isSelected: true,
                 tint: Color.hintRed)
        }
    }
}

/// 主题包详情: poems, size and space, and download / update / retry / remove. Removing frees the files only;
/// learning records, favourites and writing stay and come back with the pack.
struct ContentPackView: View {
    let packID: String

    @Environment(AppSettings.self) private var settings
    @Environment(Router.self) private var router
    @Environment(ContentStore.self) private var content
    @Environment(NetworkMonitor.self) private var network
    @Query private var progressRecords: [PoemProgress]
    @State private var confirmRemove = false

    var body: some View {
        let pack = content.packs.first { $0.id == packID }
        let poems = PoemLibrary.shared.poems.filter { $0.pack == packID }
        let snapshot = LearningSnapshot(progress: progressRecords)
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
                if let pack {
                    summary(pack)
                    actions(pack)
                } else {
                    Text(settings.t("這個主題包暫時不在發布清單中。", "这个主题包暂时不在发布清单中。"))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                if !poems.isEmpty {
                    SectionHeader(title: settings.t("包含的詩", "包含的诗"))
                    ForEach(poems) { poem in
                        Button {
                            router.push(.poem(poem.id))
                        } label: {
                            PoemCard(poem: poem, progress: snapshot.progress(poem.id))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, Metrics.pagePadding)
            .padding(.top, 12)
            .padding(.bottom, AppTheme.Spacing.pageBottom)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .pageBackground()
        .navigationTitle(pack.map { settings.t($0.title) } ?? settings.t("主題包", "主题包"))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(settings.t("刪除下載的內容？", "删除下载的内容？"), isPresented: $confirmRemove, titleVisibility: .visible) {
            Button(settings.t("刪除下載包", "删除下载包"), role: .destructive) {
                content.remove(packID: packID)
            }
        } message: {
            Text(settings.t("只釋放空間。學習記錄、收藏和作品都會保留，重新下載後就能繼續。",
                            "只释放空间。学习记录、收藏和作品都会保留，重新下载后就能继续。"))
        }
    }

    private func summary(_ pack: ContentPackInfo) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ThemeThumbnail(theme: PoemVisualTheme(themeID: pack.id), size: 84)
            VStack(alignment: .leading, spacing: 6) {
                Text(settings.t(pack.title))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Text(settings.t(pack.summary))
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(settings.t("\(pack.poemCount) 首 · 約 ", "\(pack.poemCount) 首 · 约 ")
                     + ByteCountFormatter.string(fromByteCount: Int64(pack.size), countStyle: .file)
                     + settings.t(" · 版本 ", " · 版本 ") + pack.version)
                    .font(.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
        }
        .card()
    }

    @ViewBuilder
    private func actions(_ pack: ContentPackInfo) -> some View {
        let state = content.state(of: pack)
        VStack(alignment: .leading, spacing: 10) {
            switch state {
            case .downloading(let progress):
                ProgressView(value: progress)
                    .tint(AppTheme.Colors.primaryGold)
                Text(settings.t("下載中，完成並校驗後才會切換。", "下载中，完成并校验后才会切换。"))
                    .font(.footnote)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            case .installed(let version):
                Label(settings.t("已下載（\(version)），可離線使用", "已下载（\(version)），可离线使用"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(AppTheme.Colors.successGreen)
                removeButton
            case .updateAvailable(let installed):
                Text(settings.t("有新版本。更新完成前，仍使用目前的 \(installed)。", "有新版本。更新完成前，仍使用目前的 \(installed)。"))
                    .font(.footnote)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                downloadButton(pack, title: settings.t("更新", "更新"))
                removeButton
            case .failed(let reason):
                Label(settings.t("沒有下載成功（\(reason)）。已有的內容和記錄不受影響。", "没有下载成功（\(reason)）。已有的内容和记录不受影响。"),
                      systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(Color.hintRed)
                    .fixedSize(horizontal: false, vertical: true)
                downloadButton(pack, title: settings.t("重試", "重试"))
            case .notDownloaded:
                if let free = content.availableCapacity {
                    Text(settings.t("需要約 ", "需要约 ") + ByteCountFormatter.string(fromByteCount: Int64(pack.size), countStyle: .file)
                         + settings.t("，這部裝置還有 ", "，这台设备还有 ") + ByteCountFormatter.string(fromByteCount: free, countStyle: .file)
                         + settings.t(" 可用。", " 可用。"))
                        .font(.footnote)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                downloadButton(pack, title: settings.t("下載", "下载"))
            }
            if !network.isOnline, state != .downloading(0) {
                Label(settings.t("現在離線，連上網絡後再下載。", "现在离线，连上网络后再下载。"), systemImage: "icloud.slash")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
        }
        .card()
    }

    private func downloadButton(_ pack: ContentPackInfo, title: String) -> some View {
        Button {
            Task { await content.download(pack) }
        } label: {
            Label(title, systemImage: "arrow.down.circle")
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(!network.isOnline)
    }

    private var removeButton: some View {
        Button(role: .destructive) {
            confirmRemove = true
        } label: {
            Label(settings.t("刪除下載包", "删除下载包"), systemImage: "trash")
        }
        .buttonStyle(SoftButtonStyle())
    }
}
