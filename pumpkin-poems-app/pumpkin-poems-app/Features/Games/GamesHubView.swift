import SwiftUI

struct GamesHubView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(Router.self) private var router

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                gameCard(
                    title: settings.t("飛花令", "飞花令"),
                    description: settings.t("字雨紛飛，接住散落的詩句。", "字雨纷飞，接住散落的诗句。"),
                    screenshot: "game_flying_preview", cropTop: 0.40, route: .feiHuaLing(nil)
                )
                gameCard(
                    title: settings.t("劃字尋詩", "划字寻诗"),
                    description: settings.t("指尖轉個彎，字格裏藏著一首詩。", "指尖转个弯，字格里藏着一首诗。"),
                    screenshot: "game_grid_preview", cropTop: 0.45, route: .verseGrid
                )
                gameCard(
                    title: settings.t("六輪猜詩", "六轮猜诗"),
                    description: settings.t("六次猜想，讓顏色揭開詩句的謎底。", "六次猜想，让颜色揭开诗句的谜底。"),
                    screenshot: "game_wordle_preview", cropTop: 0.40, route: .poemWordle
                )
                comingSoonCard
            }
            .padding(16)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .pageBackground()
        .navigationTitle(settings.t("詩詞遊樂園", "诗词游乐园"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func gameCard(title: String, description: String, screenshot: String, cropTop: CGFloat, route: Route) -> some View {
        Button {
            GameFeedback.shared.play(.tap)
            router.push(route)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                GeometryReader { geometry in
                    Image(screenshot)
                        .resizable()
                        .scaledToFit()
                        // Keep the full iPhone capture at its original aspect ratio,
                        // then show the gameplay area within the card's viewport.
                        .frame(width: geometry.size.width, height: geometry.size.width * 2622 / 1206)
                        .offset(y: -geometry.size.width * cropTop)
                }
                .aspectRatio(1.05, contentMode: .fit)
                .clipped()
                .accessibilityHidden(true)

                cardText(title: title, description: description)
            }
            .card(padding: 0)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private var comingSoonCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Color.pumpkinOrange.opacity(0.07)
                Image(systemName: "sparkles")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(Color.pumpkinOrange.opacity(0.55))
            }
            .aspectRatio(1.05, contentMode: .fit)
            .accessibilityHidden(true)

            cardText(title: settings.t("敬請期待", "敬请期待"), description: nil)
        }
        .card(padding: 0)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func cardText(title: String, description: String?) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.cocoa)
            if let description {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(Color.chestnut)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 85, alignment: .topLeading)
        .padding(14)
    }
}
