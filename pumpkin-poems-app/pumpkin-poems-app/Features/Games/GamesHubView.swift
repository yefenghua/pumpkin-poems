import SwiftUI
import SwiftData

struct GamesHubView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(Router.self) private var router
    @Query private var records: [GameRecord]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(settings.t("讓詩句，玩起來", "让诗句，玩起来"))
                            .font(.title2.bold())
                        Text(settings.t("回想一句、連出一句、推理一句。", "回想一句、连出一句、推理一句。"))
                            .font(.subheadline).foregroundStyle(Color.chestnut)
                    }
                    Spacer()
                    MascotIllustration(size: 70)
                }
                gameCard(title: settings.t("飛花令 · 飄字成詩", "飞花令 · 飘字成诗"),
                         caption: settings.t("接住字，補成詩", "接住字，补成诗"),
                         description: settings.t("選一個飛字，接住飄落的字補全詩句。六句一局。", "选一个飞字，接住飘落的字补全诗句。六句一局。"),
                         icon: "sparkles", tint: .pumpkinOrange, route: .feiHuaLing(nil),
                         result: best("flying").map { settings.t("最佳 \($0) 分", "最佳 \($0) 分") })
                gameCard(title: settings.t("劃字尋詩", "划字寻诗"),
                         caption: settings.t("發現 × 路徑", "发现 × 路径"),
                         description: settings.t("在字格裏拖曳連詩，可轉彎、跨格。", "在字格里拖拽连诗，可转弯、跨格。"),
                         icon: "square.grid.3x3", tint: .blue, route: .verseGrid,
                         result: records.contains { $0.mode == "verse-grid" } ? settings.t("已完成過尋詩", "已完成过寻诗") : nil)
                gameCard(title: settings.t("六輪猜詩", "六轮猜诗"),
                         caption: settings.t("推理 × 排除", "推理 × 排除"),
                         description: settings.t("跟著顏色線索，在六輪內猜中詩句。", "跟着颜色线索，在六轮内猜中诗句。"),
                         icon: "rectangle.grid.3x2", tint: .green, route: .poemWordle,
                         result: records.contains { $0.mode == "poem-wordle" && $0.score > 0 } ? settings.t("已猜中過詩句", "已猜中过诗句") : nil)
                Text(settings.t("選自己的詩庫，玩過再聽一遍。", "选自己的诗库，玩过再听一遍。"))
                    .font(.footnote).foregroundStyle(Color.chestnut)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .pageBackground()
        .navigationTitle(settings.t("詩詞遊樂園", "诗词游乐园"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { ScriptAndVoiceMenus() }
        }
    }

    private func best(_ mode: String) -> Int? { records.filter { $0.mode == mode }.map(\.score).max() }

    private func gameCard(title: String, caption: String, description: String, icon: String,
                          tint: Color, route: Route, result: String?) -> some View {
        Button { GameFeedback.shared.play(.tap); router.push(route) } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: icon).font(.title2).foregroundStyle(tint)
                        .frame(width: 46, height: 46)
                        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(.headline).foregroundStyle(Color.cocoa)
                        Text(caption).font(.caption.weight(.semibold)).foregroundStyle(tint)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").foregroundStyle(Color.chestnut)
                }
                Text(description).font(.subheadline).foregroundStyle(Color.chestnut)
                    .fixedSize(horizontal: false, vertical: true)
                if let result { Text(result).font(.caption.weight(.semibold)).foregroundStyle(tint) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}
