# 贝贝古诗 · 第二阶段学习试用版

Phase 2 (`docs/phase-2-learning-release.md`) is built on top of the phase-1 demo described further down. The Go
service lives in `pumpkin-poems-backend/`; the client ↔ server contract is `docs/api/phase2-api.md`.

## Phase 2 at a glance

| ID | What the app does now | Where |
| --- | --- | --- |
| L01 | 30 poems, 5 themes. The base pack (18 poems: 月与思乡、山水田园、四季景物) is bundled; 友情送别 and 生活与志趣 are downloadable packs. Every poem has 6 questions (理解: 诗意 / 字词 / 配对; 记忆: 填字 / 上下句 / 排序), difficulty, imagery and sources | `content/phase2-learning.json`, `scripts/build_content.py` |
| L02 | Manifest + packs from the server; size and SHA-256 checked before switching; a failed download keeps the old version; removing a pack keeps all records | `Content/ContentStore.swift`, `Features/Library/ContentPackViews.swift` |
| L03 | 每日目标 5 / 10 / 15 min → review and new-poem quota, mistakes first, backlog split over days, rest day. Review rule v2: nodes on day 1/3/7/14/30 from the first pass, failed or hinted reviews retry the node tomorrow, overdue nodes never stack, 记忆较稳 = ≥2 unaided review days and ≥7 days span | `Progress/DailyPlan.swift`, `Progress/ReviewScheduler.swift`, `Features/Today` |
| L04 | Pass = 80% and ≥1 right in both 理解 and 记忆; first submissions only; 提示 marks 有提示完成. 错题 by category, 待巩固 → 已订正 → 已巩固 (only after an unaided correct answer on a later day); revised / withdrawn questions show the version that was missed | `Features/Quiz`, `Features/Profile/MistakesView.swift` |
| L05 | 小小诗人: 看例句 (with author and source) → 仿写 / 自由写, 五言 / 七言 / 不限 with live Han-character counts, autosave + resume, copy, delete with undo | `Features/Workshop` |
| L06 | Review checklist `content/review-status.json` (all poems `pending` until a teacher signs off); `contentctl validate / publish / rollback / withdraw-question` in the backend | `pumpkin-poems-backend/cmd/contentctl` |
| L07 | Anonymous trial events (no drafts, no free text) queued and batched; 意见反馈 in 家长区域 | `Network/Telemetry.swift`, `Features/Parent` |
| L08 | 家长区域 behind a parent gate (not authentication); parent account = account ID + password (register / login / change password / logout); child profiles (nickname, optional stage); each learner has its own SwiftData store | `Account/`, `Features/Parent/ParentAreaView.swift` |
| L09 | Learning records are an append-only event log, replayed into progress, so two devices converge; writing syncs with revisions, 冲突副本 and tombstones; the guest's records move into a chosen profile once | `Progress/ProgressStore.swift`, `Account/SyncEngine.swift` |
| L10 | 学习周报: 理解, 记忆 and 复习 separately, 记录还不够 below 5 answers, one concrete 陪学建议 | `Progress/WeeklyReport.swift`, `Features/Parent/WeeklyReportView.swift` |
| L11 | 诗境配对 for 月与思乡: 5 rounds, picture and evidence judged separately | `Features/SceneMatch` |

Not in this build: L12 (family co-learning, card export — P2, separately estimated), reviewed 粤普 recordings
(the manifest has an `audio` list ready; read-aloud still uses device voices), teacher review of the new content.

**Upgrade path.** On first launch a phase-1 install converts its records into `legacySnapshot` events and replays them:
favourites, passed poems, review dates, mistakes and earned 记忆较稳 are kept.

**Parent account.** Account ID (4–32 chars, `a-z 0-9 . _ -`, case-insensitive) plus password (8–128 chars). The server
stores no e-mail or phone, so there is no password reset; the sign-in form says so. No Apple or third-party sign-in.

### Running against the local service

```sh
cd pumpkin-poems-backend
go run ./cmd/contentctl publish --packs ../pumpkin-poems-app/build/packs \
  --review ../pumpkin-poems-app/content/review-status.json --out ./content-releases \
  --release 2026-11-01.1 --allow-unreviewed
ADMIN_TOKEN=dev-admin go run ./cmd/server                     # ADDR=:18080 if 8080 is taken
```

The debug app talks to `http://127.0.0.1:8080` (change it in 设置 → 服务地址, or launch with
`-server.baseURL http://127.0.0.1:18080`). Empty means no server; everything except packs, sync and feedback works offline.

Extra debug launch arguments: `-demoDownloadPacks YES`, `-demoSignIn <accountID>` with optional `-demoPassword <pw>`
(registers if needed, signs in, creates 小明, moves the guest records in and syncs), routes `pack:<id>`, `mistake:<questionID>`, `parent`, `report`, `scenematch:moon`, `feedback`.

Missing artwork for phase 2 shows grey areas; prompts are in `docs/design/phase2-artwork-delivery.md`.

---

# 第一阶段本地 Demo（原说明）

SwiftUI app implementing the phase-1 scope in `docs/product-design-and-roadmap.md` §6, styled per `docs/visual-design-guidelines.md`. Fully offline: no backend, no login.

## What's in it

| Area | Implementation |
| --- | --- |
| 今天 | Continue learning (resumes reading / recitation / quiz), 今日复习 shortcut to the due-review list, 飞花令 entry |
| 诗库 | 12 poems in 3 themes; search titles, lines and poets in either script; filters for theme, difficulty, poet, learning state, favorites |
| 古诗详情 | Tap a line for 读懂这句 / 再想一想; tap dotted terms for word notes; 全诗理解; separate 繁简 and 粤普 menus |
| 朗读 | Whole poem or single line, current line highlighted. Uses on-device zh-HK / zh-CN voices until reviewed recordings exist |
| 背诵 | 完整 → 隐关键字 → 显首字 → 全隐藏, per-line hints, 「我记住了」 recorded as self-assessment only |
| 小测 | 5 questions per poem (诗意理解, 诗意配对, 关键字填空, 上下句, 排序), explanation after submit, tap-to-order |
| 复习 | First pass → review on day 1, 3, 7, 14, 30; mistakes or failure bring it forward to tomorrow (`Progress/ReviewScheduler.swift`) |
| 飞花令 (P1) | Entry (choose 1 of 4) and challenge (type a line, first-character hints, no timer); 繁/简 input both accepted; unknown lines are "暂未收录", not wrong; personal best per mode saved |
| 成长反馈 (P1) | 学习完成页 with the earned 诗词卡, concrete rewards, next review date, a growth-book progress strip, and entries to 飞花令 / 小小诗人 |
| 小小诗人 (P2) | `Features/Workshop`: theme → imagery words → 2 or 4 lines with sentence patterns and library examples → gentle checks (never a score) → title → saved locally to 我的诗集 (edit / delete) |
| 我的 | Growth book: three theme covers → per-theme poem cards with proficiency and badge state, 已读过 / 练习通过 / 记忆较稳, personal bests, 我的诗集, 错题回看, settings |

Learning records use SwiftData (iOS 17+) keyed by stable `poemID` / `questionID`, shared by both scripts.

## Look and feel

The UI follows `docs/design/ui-delivery/ui-instruction.md`: a storybook scene on top of each main screen, warm paper
for content, and 贝贝 the pumpkin as companion. All 16 delivered illustrations live in
`pumpkin-poems-app/PoetryArtwork.xcassets` (copied from `docs/design/ui-delivery/`, single-scale, original pixels).

- `Design/Theme.swift` — `AppTheme` colours, spacing, radii and type sizes; paper cards, gold / audio / soft buttons.
  Spacing is deliberately tight (page 16, section 14, item 10) so each main screen fits one phone height.
- `Design/StorybookPage.swift` — the shell of every illustrated screen. Upright it is the scene on top with the
  cards riding over its fade; with the phone turned sideways the scene becomes a full-height panel down the left
  (under the notch and the bars) and the content scrolls beside it, so nothing is taller than the display. 小测 and
  背诵 split into two columns sideways (question + 提示/提交 left, answers right) and 诗库 uses a two-column grid.
  iPad keeps the upright flow.
- Artwork that has not been generated yet (飞花令 / 小小诗人 / 完成页 scenes, 我的诗集 vignette) shows a neutral grey
  `PendingArtwork` area with the asset name. Prompts and target sizes are in `docs/design/pending-artwork-prompts.md`;
  dropping the PNG into `PoetryArtwork.xcassets` under that name swaps it in with no code change.
- `Design/PoetryArtwork.swift` — `PoemVisualTheme` maps a poem's explicit theme (`moon` / `landscape` / `seasons`) to its
  home scene, continue-card vignette, reading background and album cover. Poems without a mapped theme fall back to a
  neutral paper area; a missing asset renders a labelled placeholder instead of crashing. Also the shared
  `IllustratedSceneHeader`, `PaperSurface`, `MascotIllustration`, `CollectionCover` and `ThemeThumbnail` components.
- 今天 — scene with 贝贝 painted in (no separate mascot layer) that rotates through the three themes one per day
  (`PoemVisualTheme.daily`, follows `-debug.dayOffset`), continue-learning card riding over it with the current
  poem's vignette, then 今日复习 (scroll artwork) and 飞花令 (blossom artwork) shortcut cards.
- 古诗详情 — themed reading background, warm paper with centred lines and the current-line highlight, 读懂这句 box with
  `mascot_peeking` leaning on its corner, fixed 听一听 / 开始背诵 bar in the bottom safe area; the tab bar is hidden here.
- 我的 — garden scene with the celebrating 贝贝, three tilted collectible theme covers (unlocked by the first passed
  practice in a theme, counts from real records), and the 已读过 / 练习通过 / 记忆较稳 panel.

## Content

The app reads `pumpkin-poems-app/Resources/PoemContent.json`, generated from the corpus in `poems/articles` plus the authored learning content in `content/phase1-learning.json` (line explanations, 全诗理解, comprehension and fill-in questions). After editing either source, rebuild it from the repository root:

```sh
python3 pumpkin-poems-app/scripts/build_content.py
```

The authored explanations are original drafts and still need review by a Chinese-language teacher, as do 粤语 / 普通话 readings.

## Checks

```sh
python3 pumpkin-poems-app/scripts/build_content.py   # base pack + build/packs/*.json
pumpkin-poems-app/scripts/run_logic_tests.sh         # content integrity, 繁简, 飞花令, review rule v2, pass rule, daily plan, weekly report
```

## Debug launch arguments

Debug builds accept these for demos and screenshots (Xcode scheme → Arguments, or `simctl launch`):

- `-demoSeed YES` — fills sample progress on a fresh install
- `-demoTab library|me`, `-demoRoute poem:<id>|recite:<id>|quiz:<id>|feihualing[:<char>]|review|theme:<id>|workshop[:<themeID>]|mypoems|mistakes|settings`
- `-demoQuizDone YES` with `-demoRoute quiz:<id>` — opens the completion page directly (records a perfect round)
- `-demoOrientation landscape|portrait` — turns the simulator on its side (or back) at launch, for screenshots of the sideways layouts
- `-demoTerm YES` with `-demoRoute poem:<id>` — opens the first word's 字词解释 (sheet upright, inline card sideways)
- `-debug.dayOffset 1` — shifts "today" to demo next-day review (also in 设置 → 演示工具)
