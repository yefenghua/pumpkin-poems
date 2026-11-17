import SwiftUI

/// A horizontal row of items that can be wider than the screen. While something is hidden beyond an
/// edge, a round ← / → button sits on that edge; tapping it scrolls the next hidden item into view.
/// Nothing is shown when everything fits, so a short row looks like a plain `HStack`.
struct ArrowedShelf<Data: RandomAccessCollection, Content: View>: View where Data.Element: Identifiable {
    let items: Data
    var spacing: CGFloat = 16
    /// Room around the row inside the scroll view (shadows and tilted covers need some).
    var contentInsets = EdgeInsets(top: 12, leading: 4, bottom: 12, trailing: 4)
    @ViewBuilder let content: (Data.Element) -> Content

    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Each item's frame in the scroll view's own space: negative minX means hidden on the left.
    @State private var frames: [Data.Element.ID: CGRect] = [:]
    @State private var viewportWidth: CGFloat = 0

    private var hiddenLeft: Bool { frames.values.contains { $0.minX < -1 } }
    private var hiddenRight: Bool { viewportWidth > 0 && frames.values.contains { $0.maxX > viewportWidth + 1 } }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: spacing) {
                    ForEach(items) { item in
                        content(item)
                            .id(item.id)
                            .background(GeometryReader { geo in
                                Color.clear.preference(key: ShelfFramesKey<Data.Element.ID>.self,
                                                       value: [item.id: geo.frame(in: .named("shelf"))])
                            })
                    }
                }
                .padding(contentInsets)
            }
            .coordinateSpace(name: "shelf")
            .onPreferenceChange(ShelfFramesKey<Data.Element.ID>.self) { frames = $0 }
            .background(GeometryReader { geo in
                Color.clear.onAppear { viewportWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, width in viewportWidth = width }
            })
            .overlay(alignment: .leading) {
                if hiddenLeft {
                    arrow("chevron.left", label: settings.t("往左看", "往左看")) {
                        // The last item cut off on the left comes in at the leading edge.
                        guard let target = orderedIDs.last(where: { (frames[$0]?.minX ?? 0) < -1 }) else { return }
                        scroll(proxy, to: target, anchor: .leading)
                    }
                    .padding(.leading, 6)
                }
            }
            .overlay(alignment: .trailing) {
                if hiddenRight {
                    arrow("chevron.right", label: settings.t("往右看", "往右看")) {
                        // The first item cut off on the right comes in at the leading edge, so the ones after it show too.
                        guard let target = orderedIDs.first(where: { (frames[$0]?.maxX ?? 0) > viewportWidth + 1 }) else { return }
                        scroll(proxy, to: target, anchor: .leading)
                    }
                    .padding(.trailing, 6)
                }
            }
        }
    }

    private var orderedIDs: [Data.Element.ID] { items.map(\.id) }

    private func scroll(_ proxy: ScrollViewProxy, to id: Data.Element.ID, anchor: UnitPoint) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) {
            proxy.scrollTo(id, anchor: anchor)
        }
    }

    private func arrow(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .frame(width: 34, height: 34)
                .background(Color.white, in: Circle())
                .overlay(Circle().strokeBorder(AppTheme.Colors.borderWarm, lineWidth: 1))
                .shadow(color: AppTheme.Colors.shadow.opacity(0.18), radius: 6, y: 2)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .transition(.opacity)
    }
}

private struct ShelfFramesKey<ID: Hashable>: PreferenceKey {
    static var defaultValue: [ID: CGRect] { [:] }
    static func reduce(value: inout [ID: CGRect], nextValue: () -> [ID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}
