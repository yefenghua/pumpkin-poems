import Foundation

func runGameLibraryTests(content: GameContent) {
    let normalizer = TextNormalizer(hantToHans: content.hantToHans)
    let corpus = GameCorpus(verses: content.verses, normalizer: normalizer, poems: content.poems ?? [])
    let catalog = GameLibraryCatalog(poems: corpus.poems, normalizer: normalizer)
    let versePoemIDs = Set(content.verses.map(\.poemID))
    check(catalog.validIDs == versePoemIDs, "library offers exactly poems with game verse material")
    check(corpus.poems.count == versePoemIDs.count, "game poem metadata is unique")
    check(corpus.poems.allSatisfy { !$0.lineLengths.isEmpty && $0.lineLengths.allSatisfy { [5, 7].contains($0) } }, "library word-length metadata stays within supported verse lengths")
    check(catalog.validated([]).isEmpty, "empty selected library never silently becomes all poems")
    check(catalog.validated(["not-a-poem"]).isEmpty, "stale selected IDs are discarded")
    check(Set(catalog.matching("靜夜思").map(\.id)) == Set(catalog.matching("静夜思").map(\.id)), "library title search accepts both scripts")
    check(!catalog.matching("靜夜思").isEmpty, "known poem search is discoverable")
    check(!catalog.matching("李白").isEmpty, "library author search finds poems")
    check(catalog.matching("not-collected-title").isEmpty, "non-Han unknown query does not reveal the entire corpus")
    check(catalog.matching("  ").count == corpus.poems.count, "blank query lists all game poems")

    let stageGroups = catalog.groups(.stage)
    check(stageGroups.contains { $0.id == "stage-1" && $0.poemIDs.contains("hk-ks1-10") }, "primary stage one metadata includes 静夜思")
    check(stageGroups.contains { $0.id == "stage-2" && $0.poemIDs.contains("hk-ks2-12") }, "primary stage two metadata includes 枫桥夜泊")
    let extensionIDs = Set(corpus.poems.filter { $0.keyStages.isEmpty }.map(\.id))
    check(stageGroups.first { $0.id == "stage-extension" }?.poemIDs == extensionIDs, "unassigned extension poems remain a separate source group")
    check(stageGroups.first { $0.id == "stage-1" }?.title.hans == "小一至小三", "stage one label is accurate year band")
    check(stageGroups.first { $0.id == "stage-4" }?.title.hans == "中四至中六", "stage four label is accurate year band")
    for category in GameLibraryCatalog.Category.allCases {
        let groups = catalog.groups(category)
        check(Set(groups.map(\.id)).count == groups.count, "group IDs unique for \(category.rawValue)")
        check(groups.allSatisfy { !$0.poemIDs.isEmpty && $0.poemIDs.isSubset(of: catalog.validIDs) }, "groups contain real game poems for \(category.rawValue)")
        check(groups.reduce(into: Set<String>()) { $0.formUnion($1.poemIDs) } == catalog.validIDs, "classification covers all poems for \(category.rawValue)")
    }
    let primary = stageGroups.first { $0.id == "stage-1" }?.poemIDs ?? []
    let authors = catalog.groups(.author).first { $0.title.hans == "李白" }?.poemIDs ?? []
    let combined = catalog.adding(authors, to: primary)
    check(combined == primary.union(authors), "multiple category selection unions and deduplicates poems")
    check(catalog.removing(authors, from: combined) == primary.subtracting(authors), "explicit category removal subtracts only that category")

    let namespace = "pumpkin-game-library-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: namespace)!
    defer { defaults.removePersistentDomain(forName: namespace) }
    let store = GameLibraryStore(defaults: defaults, validIDs: catalog.validIDs)
    check(store.load().isEmpty, "fresh custom library store is empty")
    do {
        _ = try store.save(name: " ", selection: primary)
        check(false, "blank saved library name should fail")
    } catch GameLibraryStore.SaveProblem.emptyName {} catch { check(false, "blank name error classification") }
    do {
        _ = try store.save(name: "空库", selection: [])
        check(false, "empty custom library should fail")
    } catch GameLibraryStore.SaveProblem.emptySelection {} catch { check(false, "empty selection error classification") }
    do {
        let value = try store.save(name: "  我的唐诗  ", selection: primary.union(["stale-poem"]))
        check(value.name == "我的唐诗" && Set(value.poemIDs) == primary, "saved library trims title and removes unknown source IDs")
        let restarted = GameLibraryStore(defaults: defaults, validIDs: catalog.validIDs)
        check(restarted.load().first == value, "named library survives store recreation / app restart")
        do {
            _ = try restarted.save(name: "我的唐诗", selection: authors)
            check(false, "duplicate saved title must be explicit update")
        } catch GameLibraryStore.SaveProblem.duplicateName {} catch { check(false, "duplicate title error classification") }
        let changed = try restarted.save(name: value.name, selection: combined, replacing: value.id)
        check(changed.id == value.id && restarted.load().count == 1 && Set(changed.poemIDs) == combined, "updating named library preserves identity and doesn't duplicate category")
        if let retained = combined.sorted().first {
            let updatedContent = GameLibraryStore(defaults: defaults, validIDs: [retained])
            check(updatedContent.load().first?.poemIDs == [retained], "loading against updated content removes obsolete poems")
        }
        check(GameLibraryStore(defaults: defaults, validIDs: []).load().isEmpty, "entirely obsolete categories cannot produce an empty selectable saved library")
        restarted.delete(value.id)
        check(restarted.load().isEmpty, "deleting custom category leaves store empty")
    } catch { check(false, "named library persistence failed: \(error)") }

    let legacy = try? JSONDecoder().decode(GameContent.self, from: Data("{\"version\":\"legacy\",\"verses\":[],\"hantToHans\":{}}".utf8))
    check(legacy != nil && legacy?.poems == nil, "older game packages without metadata still decode")
    let fallback = GameCorpus(verses: content.verses, normalizer: normalizer)
    check(Set(fallback.poems.map(\.id)) == versePoemIDs, "legacy corpus construction derives selectable poems")
    check(fallback.poems.allSatisfy { $0.keyStages.isEmpty }, "legacy fallback does not invent school-year claims")
}
