# 贝贝古诗 · 第一阶段本地 Demo

SwiftUI app implementing the phase-1 scope in `docs/product-design-and-roadmap.md` §6, styled per `docs/visual-design-guidelines.md`. Fully offline: no backend, no login.

## Demonstration

See [the Chinese demo guide](../docs/demo-guide.md) for a 5–6 minute learning walkthrough, a three-game showcase, bilingual talk tracks and preflight checks. From the repository root:

```sh
./pumpkin-poems-app/scripts/demo.sh cantonese  # Traditional UI + Cantonese voice
./pumpkin-poems-app/scripts/demo.sh mandarin   # Simplified UI + Mandarin voice
```

The launcher builds, installs and opens a regular, non-folding iPhone simulator without erasing saved records. Use `--help` for direct routes, a specific simulator, sample data and reusing a build. In the app, 我的 → 设置 includes one-tap language presets, individual text/voice settings and both voice previews. Download the requested system voices before an offline demonstration; unavailable voices show a visible message and never silently substitute another language. Test actual audio output on the presentation device.

## What's in it

| Area | Implementation |
| --- | --- |
| 首次设置 | Choose Primary 1–6 or Secondary 1–6 and Cantonese/Mandarin; editable later in Settings |
| 今天 | Grade-based plan with progress, continue learning (reading / recitation / quiz), scoped due reviews, and three poetry games. Years share their source curriculum stage; changing grade keeps saved records |
| 诗库 | 12 existing poems in 3 themes; search titles, lines and poets in either script; filters for theme, difficulty, poet, learning state, favorites |
| 古诗详情 | Tap a line for 读懂这句 / 再想一想; tap dotted terms for word notes; 全诗理解; separate 繁简 and 粤普 menus |
| 朗读 | Whole poem or single line, current line highlighted. Uses on-device zh-HK / zh-CN voices until reviewed recordings exist |
| 背诵 | 完整 → 隐关键字 → 显首字 → 全隐藏, per-line hints, 「我记住了」 recorded as self-assessment only |
| 小测 | 5 questions per poem (诗意理解, 诗意配对, 关键字填空, 上下句, 排序), explanation after submit, tap-to-order |
| 复习 | First pass → review on day 1, 3, 7, 14, 30; mistakes or failure bring it forward to tomorrow (`Progress/ReviewScheduler.swift`) |
| 飞花令 · 飘字成诗 | Pick a concrete image such as 月、花、水. Six masked verses per game: the chosen character stays visible, and players catch drifting characters to fill the remaining slots in order. A sparse, varied field grows temporarily after a shake. Visible characters are unique and never overlap; tapping only removes its token, and an incorrect submission clears the editable slots. Other real verses matching the mask also count; a verse can score only once per game |
| 划字寻诗 | Choose a challenge library, then drag through cells to form complete verses. Turns and cross-grid jumps are allowed, with each cell used at most once per answer. Release to submit; optional character speech |
| 六轮猜诗 | Choose a challenge library and five/seven characters. Four/five poems supply candidates; three/four share a character. The keyboard has 20–30 unique characters. Only complete verses in the chosen library are accepted; invalid input costs no turn. Six attempts with frequency-aware green/yellow/grey feedback |
| 我的诗库 | Select by curriculum stage, author or verse form, or choose individual poems. Save named collections for later games. Both games validate the selected library before enabling Start |
| 游戏声音 | Original looping background music, tap/success/error/completion sounds and haptics, enabled by default with independent controls. Music becomes quieter during speech and pauses in the background |
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
- Artwork that has not been generated yet (飞花令 / 小小诗人 / 完成页 scenes, 我的诗集 vignette) shows a neutral grey
  `PendingArtwork` area with the asset name. Prompts and target sizes are in `docs/design/pending-artwork-prompts.md`;
  dropping the PNG into `PoetryArtwork.xcassets` under that name swaps it in with no code change.
- `Design/PoetryArtwork.swift` — `PoemVisualTheme` maps a poem's explicit theme (`moon` / `landscape` / `seasons`) to its
  home scene, continue-card vignette, reading background and album cover. Poems without a mapped theme fall back to a
  neutral paper area; a missing asset renders a labelled placeholder instead of crashing. Also the shared
  `IllustratedSceneHeader`, `PaperSurface`, `MascotIllustration`, `CollectionCover` and `ThemeThumbnail` components.
- 今天 — scene with 贝贝 painted in (no separate mascot layer) that rotates through the three themes one per day
  (`PoemVisualTheme.daily`, follows `-debug.dayOffset`), continue-learning card riding over it with the current
  poem's vignette, then 今日复习 (scroll artwork) and 诗词游乐园 (blossom artwork) shortcut cards.
- 古诗详情 — themed reading background, warm paper with centred lines and the current-line highlight, 读懂这句 box with
  `mascot_peeking` leaning on its corner, fixed 听一听 / 开始背诵 bar in the bottom safe area; the tab bar is hidden here.
- 我的 — garden scene with the celebrating 贝贝, three tilted collectible theme covers (unlocked by the first passed
  practice in a theme, counts from real records), and the 已读过 / 练习通过 / 记忆较稳 panel.

## Content

The app reads `pumpkin-poems-app/Resources/PoemContent.json`, generated from the corpus in `poems/articles` plus the authored learning content in `content/phase1-learning.json` (line explanations, 全诗理解, comprehension and fill-in questions). After editing either source, rebuild it from the repository root:

```sh
python3 pumpkin-poems-app/scripts/build_content.py
```

`Resources/GameContent.json` is a separate, source-attributed game corpus: **1,012 five/seven-character lines from 163 poems**. The reading/quiz library retains **12 authored lessons / 60 questions**. Primary plans use the existing two curriculum stages. Secondary grade choices and stage mappings are in place; content integration remains a code TODO, while the app offers access to the existing library without development messages. Regenerate game material with:

```sh
python3 pumpkin-poems-app/scripts/build_game_content.py
```

Direct game routes are `games`, `feihualing:月`, `versegrid` and `wordle`, for example:

```sh
./pumpkin-poems-app/scripts/demo.sh mandarin --route games
```

The authored explanations are original drafts and still need review by a Chinese-language teacher, as do 粤语 / 普通话 readings.

## Checks

Current verification is recorded in the demo guide. Sound and haptic feel should also be checked on the presentation iPhone.

```sh
pumpkin-poems-app/scripts/run_logic_tests.sh   # content, 繁简 matching, game generation/judging/scoring, review rules
pumpkin-poems-app/scripts/run_progress_tests.sh # actual SwiftData persistence and quiz/review regressions
```

## Debug launch arguments

Debug builds accept these for demos and screenshots (Xcode scheme → Arguments, or `simctl launch`):

- `-demoSeed YES` — fills sample progress on a fresh install
- `-demoLanguage cantonese|mandarin` — applies the matching text and spoken-language presentation preset, keeping learning records
- `-demoTab library|me`, `-demoRoute poem:<id>|recite:<id>|quiz:<id>|games|feihualing[:<char>]|versegrid|wordle|review|theme:<id>|workshop[:<themeID>]|mypoems|mistakes|settings`
- `-demoQuizDone YES` with `-demoRoute quiz:<id>` — opens the completion page directly (records a perfect round)
- `-debug.dayOffset 1` — shifts "today" to demo next-day review (also in 设置 → 演示工具)

Game audio is generated locally from original synthesized notes (no external recordings):

```sh
python3 pumpkin-poems-app/scripts/build_game_audio.py
```
