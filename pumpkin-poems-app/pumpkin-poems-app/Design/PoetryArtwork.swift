import SwiftUI
import UIKit

// MARK: - Theme → artwork mapping (ui-instruction.md "主题资源映射")

/// One of the three delivered visual themes. Chosen from the poem's explicit theme ID,
/// never randomly and never from the system colour scheme.
enum PoemVisualTheme: String, CaseIterable, Identifiable {
    case moonlight, landscape, seasons

    var id: String { rawValue }

    /// Maps the content theme IDs (`moon` / `landscape` / `seasons`) to artwork.
    init?(themeID: String) {
        switch themeID {
        case "moon", "moonlight": self = .moonlight
        case "landscape": self = .landscape
        case "seasons": self = .seasons
        default: return nil
        }
    }

    init?(poem: Poem?) {
        guard let poem else { return nil }
        self.init(themeID: poem.theme)
    }

    /// The home scene rotates through the three themes, one per calendar day (honours the debug day offset).
    static func daily(_ date: Date, calendar: Calendar = .current) -> PoemVisualTheme {
        let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        return allCases[day % allCases.count]
    }

    /// Square home scene with 贝贝 already painted in.
    var homeAsset: String {
        switch self {
        case .moonlight: "home_moonlight"
        case .landscape: "home_landscape"
        case .seasons: "home_seasons"
        }
    }

    /// Transparent vignette for the right side of the continue-learning card.
    var continueAsset: String {
        switch self {
        case .moonlight: "art_continue_moonlight"
        case .landscape: "art_continue_landscape"
        case .seasons: "art_continue_seasons"
        }
    }

    /// Reading page background, no character.
    var readingAsset: String {
        switch self {
        case .moonlight: "scene_poem_moonlight"
        case .landscape: "scene_poem_landscape"
        case .seasons: "scene_poem_seasons"
        }
    }

    /// Portrait album cover, no title baked in.
    var coverAsset: String {
        switch self {
        case .moonlight: "cover_moon"
        case .landscape: "cover_landscape"
        case .seasons: "cover_seasons"
        }
    }

    /// Text colour that reads on this theme's scenes: the moon night needs warm white, the others dark.
    var prefersLightForeground: Bool { self == .moonlight }

    var foreground: Color { prefersLightForeground ? Color(hex: 0xFFF6E3) : AppTheme.Colors.textPrimary }
    var secondaryForeground: Color { prefersLightForeground ? Color(hex: 0xFFF6E3).opacity(0.86) : AppTheme.Colors.textSecondary }
}

enum ArtworkAsset {
    static let mascotPeeking = "mascot_peeking"
    static let growthScene = "scene_growth_with_mascot"
    static let reviewScroll = "art_review_scroll"
    static let flowerGame = "art_flower_game"

    // Not delivered yet (see docs/design/pending-artwork-prompts.md). Until the PNG is dropped into
    // `PoetryArtwork.xcassets` under exactly this name, the screen shows a neutral grey area instead.
    /// 飞花令 page header: 贝贝 in a spring garden catching falling petals. Wide, opaque.
    static let gameScene = "scene_feihualing"
    /// 小小诗人 page header: 贝贝 at a low desk with brush, ink and paper. Wide, opaque.
    static let workshopScene = "scene_poet_workshop"
    /// 学习完成页 header: 贝贝 jumping with the newly earned poem card. Wide, opaque.
    static let celebrationScene = "scene_celebration"
    /// 我的诗集: a small hand-bound notebook with brush and petals. Transparent PNG.
    static let poemBookArt = "art_poem_book"

    /// Answers already given by `isAvailable`. UIKit caches a hit but not a miss: every lookup of an
    /// undelivered asset searches the catalogs and the bundle again, which view bodies cannot afford.
    @MainActor private static var availability: [String: Bool] = [:]

    /// True when the image exists in an asset catalog of the app bundle.
    @MainActor static func isAvailable(_ name: String) -> Bool {
        if let known = availability[name] { return known }
        let found = UIImage(named: name) != nil
        availability[name] = found
        return found
    }
}

// MARK: - Safe image loading

/// Decorative artwork that never crashes or shows a broken image: when the asset is missing it renders
/// a clearly marked neutral placeholder so missing deliveries are visible, not silent.
struct ArtworkImage: View {
    let name: String
    var contentMode: ContentMode = .fill

    var body: some View {
        if ArtworkAsset.isAvailable(name) {
            Image(name)
                .resizable()
                .aspectRatio(contentMode: contentMode)
                .accessibilityHidden(true)
        } else {
            ArtworkPlaceholder(name: name)
        }
    }
}

/// Neutral paper area used when an asset is absent or a poem has no mapped theme.
struct ArtworkPlaceholder: View {
    var name: String?

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0xFFF3DA), AppTheme.Colors.backgroundCream],
                           startPoint: .top, endPoint: .bottom)
            if let name {
                Text("缺少素材：\(name)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .padding(6)
                    .background(AppTheme.Colors.surfacePaper.opacity(0.8), in: Capsule())
            }
        }
        .accessibilityHidden(true)
    }
}

/// Grey stand-in for artwork that has not been generated yet. Deliberately plain so nobody mistakes
/// it for final visuals; swaps to the real picture automatically once the asset exists.
struct PendingArtwork: View {
    let name: String
    /// Small areas show only the icon; the asset name would wrap.
    var compact = false

    var body: some View {
        if ArtworkAsset.isAvailable(name) {
            ArtworkImage(name: name, contentMode: .fill)
        } else {
            // Label sits top-right below the status bar: titles live top-left and the cream fade covers the bottom.
            ZStack(alignment: compact ? .center : .topTrailing) {
                Color(hex: 0xD9D5CE)
                HStack(spacing: 4) {
                    Image(systemName: "photo")
                        .font(compact ? .title3 : .caption)
                    if !compact {
                        Text(name)
                            .font(.caption2.monospaced())
                    }
                }
                .foregroundStyle(Color(hex: 0x7A746B))
                .padding(.trailing, compact ? 0 : 12)
                .padding(.top, compact ? 0 : 64)
            }
            .accessibilityHidden(true)
        }
    }
}

// MARK: - Shared illustrated components

/// The small pumpkin helper that peeks over the explanation box. Only `mascot_peeking` is delivered,
/// so every helper moment uses it; it never intercepts touches.
struct MascotIllustration: View {
    var size: CGFloat = 72
    /// Flip left-to-right, e.g. when the helper leans on a box from the right.
    var mirrored = false

    var body: some View {
        ArtworkImage(name: ArtworkAsset.mascotPeeking, contentMode: .fit)
            .scaleEffect(x: mirrored ? -1 : 1, y: 1)
            .frame(width: size, height: size)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// A full-bleed scene that extends into the top safe area and fades into the cream page at its bottom edge.
struct IllustratedSceneHeader<Overlay: View>: View {
    let asset: String?
    var height: CGFloat
    /// Fraction of the scene height covered by the bottom fade into the cream page.
    var fade: CGFloat = 0.22
    /// Which part of the picture survives when the frame is shorter than the picture (.bottom keeps 贝贝's feet).
    var imageAlignment: Alignment = .center
    /// Extra darkening/lightening behind top-left text, when the scene needs it.
    var textScrim: Color? = nil
    /// The asset is on the pending list: show the grey stand-in rather than the "缺少素材" paper when absent.
    var pendingDelivery = false
    @ViewBuilder var overlay: Overlay

    var body: some View {
        let height = height
        ZStack(alignment: .topLeading) {
            // The frame is sized by the container, never by the bitmap: the image fills it and is clipped.
            // Pulling the page down past the top scales the picture up about its bottom edge by the same
            // distance, so it zooms and stays pinned to the top; the scroll view's rubber band limits how far.
            // The stretch is a visual effect applied after layout, so scrolling never re-runs this body.
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .overlay(alignment: imageAlignment) {
                    if let asset, pendingDelivery {
                        PendingArtwork(name: asset)
                    } else if let asset {
                        ArtworkImage(name: asset, contentMode: .fill)
                    } else {
                        ArtworkPlaceholder()
                    }
                }
                .clipped()
                .overlay(alignment: .top) {
                    if let textScrim {
                        LinearGradient(colors: [textScrim, textScrim.opacity(0)], startPoint: .top, endPoint: .bottom)
                            .frame(height: height * 0.45)
                    }
                }
                .visualEffect { content, proxy in
                    let pull = max(0, proxy.frame(in: .scrollView).minY)
                    return content.scaleEffect(1 + pull / height, anchor: .bottom)
                }
                .overlay(alignment: .bottom) {
                    LinearGradient(stops: [
                        .init(color: AppTheme.Colors.backgroundCream.opacity(0), location: 0),
                        .init(color: AppTheme.Colors.backgroundCream.opacity(0.55), location: 0.55),
                        .init(color: AppTheme.Colors.backgroundCream, location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                    .frame(height: height * fade)
                }
            overlay
        }
        .frame(height: height)
    }
}

/// Portrait collectible cover with a thick cream border and a native label underneath the picture.
struct CollectionCover: View {
    let theme: PoemVisualTheme
    let title: String
    var caption: String?
    var isUnlocked: Bool
    var width: CGFloat = 108

    /// Picture height for the 0.6 cover ratio; the label below grows with Dynamic Type.
    private var pictureHeight: CGFloat { width / 0.6 - 44 }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                ArtworkImage(name: theme.coverAsset, contentMode: .fill)
                    .frame(width: width - 10, height: pictureHeight)
                    .saturation(isUnlocked ? 1 : 0.1)
                    .opacity(isUnlocked ? 1 : 0.55)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                if !isUnlocked {
                    Image(systemName: "lock.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .padding(10)
                        .background(AppTheme.Colors.surfacePaper.opacity(0.92), in: Circle())
                }
            }
            .padding(.top, 5)
            VStack(spacing: 1) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let caption {
                    Text(caption)
                        .font(.caption2)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .frame(minHeight: 39)
        }
        .frame(width: width)
        .background(AppTheme.Colors.surfacePaper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(AppTheme.Colors.borderWarm, lineWidth: 1))
        .shadow(color: AppTheme.Colors.shadow.opacity(0.12), radius: 10, y: 5)
    }
}

/// Small theme thumbnail for lists (诗库 rows), derived from the album cover so it matches the collection.
struct ThemeThumbnail: View {
    let theme: PoemVisualTheme?
    var size: CGFloat = 64

    var body: some View {
        Group {
            if let theme {
                ArtworkImage(name: theme.coverAsset, contentMode: .fill)
            } else {
                ArtworkPlaceholder()
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(AppTheme.Colors.borderWarm, lineWidth: 1))
    }
}

/// Circular white arrow used in the bottom-right of tappable shortcut cards.
struct ArrowBadge: View {
    var body: some View {
        Image(systemName: "arrow.right")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(AppTheme.Colors.textPrimary)
            .frame(width: 34, height: 34)
            .background(Color.white, in: Circle())
            .shadow(color: AppTheme.Colors.shadow.opacity(0.14), radius: 6, y: 2)
            .accessibilityHidden(true)
    }
}

#Preview("Covers") {
    HStack(spacing: 14) {
        CollectionCover(theme: .moonlight, title: "月与思乡", caption: "2 / 4", isUnlocked: true).rotationEffect(.degrees(-3))
        CollectionCover(theme: .landscape, title: "山水田园", caption: "0 / 4", isUnlocked: false)
        CollectionCover(theme: .seasons, title: "四季景物", caption: "4 / 4", isUnlocked: true).rotationEffect(.degrees(3))
    }
    .padding()
    .pageBackground()
}
