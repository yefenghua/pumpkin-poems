import SwiftUI

/// Compact setup control shared by the two puzzle games. Selection is explicit and
/// transactional: dismissing the sheet without "Use" leaves the current library alone.
struct GameLibraryPicker: View {
    @Binding var selection: Set<String>
    @Environment(AppSettings.self) private var settings
    @State private var presented = false

    private var selected: [GamePoem] { GameCorpus.shared.poems.filter { selection.contains($0.id) } }

    var body: some View {
        Button {
            GameFeedback.shared.play(.tap)
            presented = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "books.vertical.fill").font(.title2).foregroundStyle(Color.pumpkinOrange)
                VStack(alignment: .leading, spacing: 4) {
                    Text(selected.isEmpty ? settings.t("選擇詩庫", "选择诗库")
                         : settings.t("本局詩庫 · \(selected.count) 首", "本局诗库 · \(selected.count) 首"))
                        .font(.headline).foregroundStyle(Color.cocoa)
                    Text(selected.isEmpty ? settings.t("年級 · 作者 · 詩體 · 我的詩庫", "年级 · 作者 · 诗体 · 我的诗库")
                         : selected.prefix(3).map { settings.t($0.title) }.joined(separator: "、") + (selected.count > 3 ? "…" : ""))
                        .font(.caption).foregroundStyle(Color.chestnut).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").foregroundStyle(Color.chestnut)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
            .background(Color.warmWhite, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.paleGoldLine))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("game-library.open")
        .sheet(isPresented: $presented) { GameLibrarySheet(selection: $selection) }
    }
}

private struct GameLibrarySheet: View {
    enum Browser: String, CaseIterable, Identifiable {
        case stage, author, genre, meter, poems, saved
        var id: String { rawValue }
        var category: GameLibraryCatalog.Category? { GameLibraryCatalog.Category(rawValue: rawValue) }
        func title(_ settings: AppSettings) -> String {
            if let category { return settings.t(category.title) }
            return self == .poems ? settings.t("逐首自選", "逐首自选") : settings.t("我的詩庫", "我的诗库")
        }
    }
    @Binding var selection: Set<String>
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Set<String>
    @State private var browser: Browser = .stage
    @State private var query = ""
    @State private var saved: [SavedGameLibrary] = []
    @State private var newName = ""
    @State private var notice = ""
    @State private var pendingDelete: SavedGameLibrary?
    @State private var pendingUpdate: SavedGameLibrary?

    init(selection: Binding<Set<String>>) {
        _selection = selection
        _draft = State(initialValue: selection.wrappedValue)
    }

    private var corpus: GameCorpus { GameCorpus.shared }
    private var catalog: GameLibraryCatalog { GameLibraryCatalog(poems: corpus.poems, normalizer: corpus.normalizer) }
    private var store: GameLibraryStore { GameLibraryStore(validIDs: catalog.validIDs) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Label(settings.t("已選 \(draft.count)／\(catalog.poems.count) 首", "已选 \(draft.count)／\(catalog.poems.count) 首"), systemImage: "checkmark.circle")
                            .font(.headline)
                        Spacer()
                        Button(settings.t("清空", "清空")) { changeSelection([]) }
                            .disabled(draft.isEmpty).buttonStyle(.bordered)
                    }
                    HStack {
                        Button(settings.t("全選", "全选")) { changeSelection(catalog.validIDs) }
                        Spacer()
                        Button(settings.t("選入精講詩庫", "选入精讲诗库")) {
                            add(Set(catalog.poems.filter(\.hasLearningPage).map(\.id)))
                        }
                    }.buttonStyle(.bordered)
                    Picker(settings.t("瀏覽方式", "浏览方式"), selection: $browser) {
                        ForEach(Browser.allCases) { Text($0.title(settings)).tag($0) }
                    }
                }

                if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Section(settings.t("搜尋結果", "搜索结果")) {
                        let results = catalog.matching(query)
                        if results.isEmpty { Text(settings.t("沒有找到相關詩詞", "没有找到相关诗词")) }
                        ForEach(results) { poemRow($0) }
                    }
                } else if let category = browser.category {
                    categorySection(category)
                } else if browser == .poems {
                    Section(settings.t("逐首自選", "逐首自选")) {
                        ForEach(catalog.poems) { poemRow($0) }
                    }
                } else {
                    savedSection
                }

                Section {
                    TextField(settings.t("我的李白詩庫", "我的李白诗库"), text: $newName)
                        .onChange(of: newName) { _, value in if value.count > 30 { newName = String(value.prefix(30)) } }
                        .accessibilityIdentifier("game-library.name")
                    Button {
                        do {
                            _ = try store.save(name: newName, selection: draft)
                            saved = store.load()
                            notice = settings.t("詩庫已儲存。", "诗库已保存。")
                            newName = ""
                            GameFeedback.shared.play(.success)
                        } catch GameLibraryStore.SaveProblem.duplicateName {
                            notice = settings.t("名稱已使用，請換個名字。", "名称已使用，请换个名字。")
                        } catch {
                            notice = settings.t("請填寫名稱，並至少選一首詩。", "请填写名称，并至少选一首诗。")
                        }
                    } label: { Label(settings.t("儲存為我的詩庫", "保存为我的诗库"), systemImage: "folder.badge.plus") }
                        .disabled(draft.isEmpty || newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("game-library.save")
                    if !notice.isEmpty { Text(notice).font(.footnote).foregroundStyle(Color.chestnut) }
                } header: {
                    Text(settings.t("收藏這個分類", "收藏这个分类"))
                }
            }
            .scrollContentBackground(.hidden)
            .pageBackground()
            .navigationTitle(settings.t("選擇本局詩庫", "选择本局诗库"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: settings.t("搜尋詩名、作者或類型", "搜索诗名、作者或类型"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(settings.t("取消", "取消")) { GameFeedback.shared.play(.tap); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(settings.t("使用 \(draft.count) 首", "使用 \(draft.count) 首")) {
                        selection = catalog.validated(draft)
                        GameFeedback.shared.play(.success)
                        dismiss()
                    }.disabled(draft.isEmpty)
                        .accessibilityIdentifier("game-library.apply")
                }
            }
            .onAppear { draft = catalog.validated(draft); saved = store.load() }
            .confirmationDialog(settings.t("刪除此詩庫分類？", "删除此诗库分类？"),
                                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
                Button(settings.t("刪除分類", "删除分类"), role: .destructive) {
                    if let value = pendingDelete { store.delete(value.id); saved = store.load() }
                    pendingDelete = nil
                }
            }
            .confirmationDialog(settings.t("用目前選中的 \(draft.count) 首，更新「\(pendingUpdate?.name ?? "")」？", "用当前选中的 \(draft.count) 首，更新“\(pendingUpdate?.name ?? "")”？"),
                                isPresented: Binding(get: { pendingUpdate != nil }, set: { if !$0 { pendingUpdate = nil } }), titleVisibility: .visible) {
                Button(settings.t("更新詩庫", "更新诗库")) {
                    if let value = pendingUpdate {
                        do { _ = try store.save(name: value.name, selection: draft, replacing: value.id); saved = store.load() }
                        catch { notice = settings.t("詩庫未更新，請至少選一首詩。", "诗库未更新，请至少选一首诗。") }
                    }
                    pendingUpdate = nil
                }
            }
        }
    }

    private func categorySection(_ category: GameLibraryCatalog.Category) -> some View {
        Section {
            ForEach(catalog.groups(category)) { group in
                DisclosureGroup {
                    HStack {
                        Button(settings.t("選入全部 \(group.poemIDs.count) 首", "选入全部 \(group.poemIDs.count) 首")) { add(group.poemIDs) }
                        Spacer()
                        Button(settings.t("移除", "移除")) { changeSelection(catalog.removing(group.poemIDs, from: draft)) }
                            .disabled(draft.isDisjoint(with: group.poemIDs))
                    }.buttonStyle(.bordered).font(.subheadline)
                    ForEach(catalog.poems.filter { group.poemIDs.contains($0.id) }) { poemRow($0) }
                } label: {
                    HStack {
                        Text(settings.t(group.title)).foregroundStyle(Color.cocoa)
                        Spacer()
                        Text("\(draft.intersection(group.poemIDs).count)/\(group.poemIDs.count)")
                            .font(.caption.monospacedDigit()).foregroundStyle(Color.chestnut)
                    }
                }
            }
        } header: {
            Text(settings.t(category.title))
        }
    }

    private func poemRow(_ poem: GamePoem) -> some View {
        Button {
            var next = draft
            if next.contains(poem.id) { next.remove(poem.id) } else { next.insert(poem.id) }
            changeSelection(next)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: draft.contains(poem.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(draft.contains(poem.id) ? Color.pumpkinOrange : Color.chestnut)
                VStack(alignment: .leading, spacing: 3) {
                    Text(settings.t(poem.title)).foregroundStyle(Color.cocoa)
                    Text(settings.t(poem.author) + " · " + settings.t(poem.genre))
                        .font(.caption).foregroundStyle(Color.chestnut)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(draft.contains(poem.id) ? .isSelected : [])
        .accessibilityIdentifier("game-library.poem.\(poem.id)")
    }

    private var savedSection: some View {
        Section {
            if saved.isEmpty {
                Text(settings.t("暫無自選詩庫", "暂无自选诗库"))
                    .foregroundStyle(Color.chestnut)
            }
            ForEach(saved) { library in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(library.name).font(.headline)
                        Spacer()
                        Text(settings.t("\(library.poemIDs.count) 首", "\(library.poemIDs.count) 首")).font(.caption).foregroundStyle(Color.chestnut)
                    }
                    HStack {
                        Button(settings.t("使用", "使用")) { changeSelection(Set(library.poemIDs)) }
                        Button(settings.t("加入目前選集", "加入当前选集")) { add(Set(library.poemIDs)) }
                        Spacer()
                        Menu {
                            Button(settings.t("用目前選集更新", "用当前选集更新")) { pendingUpdate = library }
                                .disabled(draft.isEmpty)
                            Button(settings.t("刪除分類", "删除分类"), role: .destructive) { pendingDelete = library }
                        } label: { Image(systemName: "ellipsis").frame(minWidth: 36, minHeight: 36) }
                    }.buttonStyle(.bordered).font(.subheadline)
                }.padding(.vertical, 4)
            }
        } header: { Text(settings.t("我的詩庫", "我的诗库")) }
    }

    private func add(_ ids: Set<String>) { changeSelection(catalog.adding(ids, to: draft)) }
    private func changeSelection(_ next: Set<String>) {
        draft = catalog.validated(next)
        notice = ""
        GameFeedback.shared.play(.tap)
    }
}
