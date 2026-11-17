# 第二阶段插画交付单（给 ChatGPT 生成）

第二阶段新增的页面已经写好，缺图的位置现在显示**中性灰色占位区**（右上角写着资源名）。
把下面每张图生成好后，放进
`pumpkin-poems-app/pumpkin-poems-app/PoetryArtwork.xcassets/<资源名>.imageset/<资源名>.png`，
`Contents.json` 照抄任意现有 imageset（单一通用尺寸），重新编译即可自动换上真图，不需要改代码。

## 怎么用

1. 每次生成时**附上参考图**，保证和现有画风一致：
   - 画风参考：`docs/design/ui-delivery/PoetryArtwork.xcassets/home_seasons.imageset/home_seasons.png`
   - 贝贝角色参考（只在写明“含贝贝”的图使用）：`docs/design/ui-assets/mascot_reading.png`
2. 一次只生成一张，复制对应代码块里的英文提示词。
3. 检查清单：没有文字、没有边框和 UI；画面要符合诗意（例如“疑是地上霜”不能画成真雪）；透明图必须是真正的透明背景，不能是白底或棋盘格。

贝贝设定不变：金黄色南瓜身体、绿色卷曲藤柄和一片小叶、深棕色圆眼睛、柔和腮红、开心的表情、蓝色小围巾、短而圆润的四肢。
他不是戴南瓜头的人，也没有万圣节元素。

## 总表（按优先级）

| # | 资源名 | 用在哪里 | 画幅 / 建议像素 | 透明 | 含贝贝 |
|---|---|---|---|---|---|
| 1 | `cover_farewell` | 成长册、诗库主题封面、诗词卡 | 竖版 3:5，约 971×1619 | 否 | 否 |
| 2 | `cover_life` | 同上 | 竖版 3:5，约 971×1619 | 否 | 否 |
| 3 | `scene_poem_farewell` | 友情送别诗的阅读页背景 | 横版 6:5，约 1374×1145 | 否 | 否 |
| 4 | `scene_poem_life` | 生活与志趣诗的阅读页背景 | 横版 6:5，约 1374×1145 | 否 | 否 |
| 5 | `art_continue_farewell` | 今天页“继续学习”卡右侧小图 | 正方形，约 1254×1254 | **是** | 否 |
| 6 | `art_continue_life` | 同上 | 正方形，约 1254×1254 | **是** | 否 |
| 7 | `home_farewell` | 今天页顶部场景（每日轮换） | 正方形，约 1254×1254 | 否 | **是** |
| 8 | `home_life` | 同上 | 正方形，约 1254×1254 | 否 | **是** |
| 9–15 | `match_moon_*`（共 7 张） | 诗境配对的选项画 | 正方形 1:1，1024×1024 | 否 | 否 |
| 16 | `scene_scene_match` | 诗境配对页顶部场景 | 横版约 3:2，1536×1024 | 否 | **是** |
| 17 | `scene_parent_corner` | 家长区域入口顶部 | 横版约 3:2，1536×1024 | 否 | **是** |

说明：

- 1–6 一到位，两个新主题就有完整的封面和阅读页。
- 7、8 到位之前，今天页只在已有的三个场景之间轮换，所以不会出现灰块。
- 9–15 到位之前，诗境配对用文字描述代替图片，也能完整玩下去；但真正的“看图配对”需要这 7 张图。

---

## 1. cover_farewell

```
Use case: illustration-story. One full-bleed portrait illustration for a collectible Chinese poetry theme cover
"friendship and farewell". Portrait aspect ratio 3:5. Match the attached watercolor gouache storybook style.
A quiet riverside ferry landing in early spring: graceful weeping willow branches with fresh pale-green leaves sweep
down from the upper right, a small wooden pier, one small sailboat with a cream sail drifting away on a wide calm
blue-green river toward soft distant mountains, a low stone pavilion half-hidden by willows at middle left, light
spring mist, a few drifting willow catkins. Gentle, a little wistful but warm morning light. Delicate painterly texture,
high quality children's illustrated book, composition recognisable even at 110pt wide (willow + lone sail are the
key motifs). No pumpkin, no people in the foreground, no phone, no UI, no text, no frame, no border, no caption strip,
no rounded corners. Opaque art fills the whole rectangle.
```

## 2. cover_life

```
Use case: illustration-story. One full-bleed portrait illustration for a collectible Chinese poetry theme cover
"everyday life and aspirations". Portrait aspect ratio 3:5. Match the attached watercolor gouache storybook style.
A sunny countryside courtyard in late spring: a white goose with an orange beak floating on a small clear pond at the
bottom, golden rice stalks at the lower left, a proud rooster with a red comb standing on a low stone wall at middle
right, a few honeybees hovering over pink and yellow flowers, a pale limestone rock face with green moss and a young pine
in the upper background, bright blue sky. Cheerful, lively, wholesome. Delicate painterly texture, high quality children's
illustrated book, motifs readable at 110pt wide (goose, rooster, bees). No pumpkin, no people, no phone, no UI, no text,
no frame, no border, no caption strip, no rounded corners. Opaque art fills the whole rectangle.
```

## 3. scene_poem_farewell

```
Use case: illustration-story. Standalone full-bleed 6:5 landscape header artwork for a Chinese farewell-poetry
learning page, using the farewell cover as visual/style reference but recomposed horizontally. Wide calm river in
spring, weeping willows framing the right third, a small wooden ferry pier and one sailboat moving away toward the
middle distance, soft blue-green mountains and a faint riverside tower far away on the left horizon, light mist on the
water. Top 30% is pale quiet sky with minimal clouds for a dark native title and controls; keep willow tips and mountain
peaks below that zone. Warm morning light, fine hand-painted watercolor gouache. No pumpkin, no people in the foreground,
no lettering, no UI, no border. Fully opaque 6:5 rectangle.
```

## 4. scene_poem_life

```
Use case: illustration-story. Standalone full-bleed 6:5 landscape header artwork for a Chinese "everyday life and
aspirations" poetry learning page, using the life cover as visual/style reference but recomposed horizontally. A sunny
farm courtyard and field edge: golden rice paddy in the lower left, a small pond with a white goose at lower middle,
a rooster on a low stone wall at the right, bees over a flowering shrub, a pale limestone hillside with a young pine in
the far right background. Top 30% is pale quiet blue sky for a dark native title and controls. Bright, wholesome, warm
midday light, fine hand-painted watercolor gouache. No pumpkin, no people in the foreground, no lettering, no UI, no
border. Fully opaque 6:5 rectangle.
```

## 5. art_continue_farewell（透明）

```
Use case: illustration-story. Create a transparent right-aligned watercolor vignette for a continue-learning card,
using the farewell cover as subject/style reference. Compact scene: a few weeping willow branches with fresh green
leaves hanging from the upper right, a small sailboat with a cream sail on a short strip of blue-green river, a hint of a
distant mountain. All subject matter clustered on the RIGHT 60% of a square canvas; the left 40% truly transparent and
empty for a native title. Organic watercolor edges feather into transparent alpha, especially at the left and bottom; no
rectangular backing. Recognisable at small size. No text, no UI frame, no pumpkin, no people. True transparent
background — no white, no cream, no checkerboard.
```

## 6. art_continue_life（透明）

```
Use case: illustration-story. Create a transparent right-aligned watercolor vignette for a continue-learning card,
using the life cover as subject/style reference. Compact scene: a white goose swimming on a small patch of clear water
with green reeds, two honeybees above a sprig of pink flowers, a few golden rice stalks. All subject matter on the RIGHT
60% of a square canvas; the left 40% truly transparent and empty for a native title. Organic watercolor edges feather into
transparent alpha at the left and bottom; no rectangular backing. Recognisable at small size. No text, no UI frame, no
pumpkin, no people. True transparent background — no white, no cream, no checkerboard.
```

## 7. home_farewell（含贝贝）

```
Use case: compositing. First image is the style reference home scene; second image is the exact Beibei character
reference. Make a SQUARE home hero illustration in the same luminous watercolor storybook style: a spring riverside
ferry landing with weeping willows, a small wooden pier, a sailboat with a cream sail drifting away on a wide blue-green
river toward soft distant mountains. Beibei the pumpkin (same identity as the reference: golden pumpkin body, green
curled stem with one leaf, brown eyes, blue scarf) sits on the grassy bank at lower right/center-right (about x65% y70%),
waving goodbye toward the boat with one short arm, a gentle warm smile. Entire body visible, about 30% of canvas width,
fully integrated into the painting (grass overlaps feet, soft shadow), not a sticker. Upper-left 35–40% open light
sky for a native heading. Lower 10% softly blends into warm cream #FFF9ED. No text, no UI, no device, no border.
```

## 8. home_life（含贝贝）

```
Use case: compositing. First image is the style reference home scene; second image is the exact Beibei character
reference. Make a SQUARE home hero illustration in the same luminous watercolor storybook style: a sunny countryside
courtyard by a rice field, a small pond with a white goose, a rooster on a low stone wall, bees around flowering shrubs,
a pale limestone hill with a young pine in the distance. Beibei the pumpkin (same identity as the reference) stands at
lower right/center-right (about x65% y70%) holding a small bamboo basket of rice ears, cheerful and proud, watching a
bee. Entire body visible, about 30% of canvas width, fully integrated into the painting, not a sticker. Upper-left
35–40% open light blue sky for a native heading. Lower 10% softly blends into warm cream #FFF9ED. No text, no UI, no
device, no border.
```

---

## 9–15. 诗境配对选项画（7 张，正方形 1024×1024，不透明，无贝贝）

孩子看诗句，从 3 幅画里选出最符合的一幅。**错的选项故意画成常见的误读**，例如真的下雪，
所以每张图都要**严格照提示词画**，不要“美化”成更符合诗意的样子。提示词由内容整理时写好，原文在
`pumpkin-poems-app/content/phase2-learning.json` 的 `sceneMatch.pictures`。

| 资源名 | 画面 | 在哪一组是正确答案 |
|---|---|---|
| `match_moon_moonlit_room` | 月光照进房间，床前地板一片银白（不是霜和雪） | 《静夜思》 |
| `match_moon_snowy_night` | 大雪夜的江边村子，到处积着真雪，没有月亮 | 都不是（误读：把“霜”当成雪） |
| `match_moon_maple_river_night` | 秋夜江边：落月、乌鸦、红枫、渔火、停泊的船、城外寺庙 | 《枫桥夜泊》 |
| `match_moon_spring_river_moon` | 春夜大江，南岸新绿，明月升起，渡口小船 | 《泊船瓜洲》 |
| `match_moon_double_ninth_hill` | 秋日山顶小亭，茱萸红果、菊花 | 《九月九日忆山东兄弟》 |
| `match_moon_midautumn_courtyard` | 中秋庭院，灯笼、月饼、空凳子 | 都不是（误读：一看到月亮就是中秋） |
| `match_moon_sewing_lamp` | 灯下针线和缝得密密的衣裳，门边放着行李 | 《游子吟》 |

### match_moon_moonlit_room

```
Children's storybook watercolor illustration, warm and luminous, Chinese quiet bedroom at night in an old house: bright moonlight streams through an open wooden lattice window and lays a pale silver-white patch of light across the dry wooden floor beside a simple wooden bed. Through the window, a bright round moon hangs in a clear sky. The white on the floor is clearly light from the window (soft edges, window-lattice shadow pattern inside it), not frost or snow. A small writing desk with a candle that is not lit. Calm, still, a little lonely. Soft gouache texture; clear foreground, middle ground and background; palette of pumpkin gold #FFB928, sky blue #5B9BF3, leaf green #61B879 and cream #FFF8E8, with deep night blue for the sky. Square 1:1, 1024×1024. No people in the foreground, no mascot, no animals other than those described, no text, no border, not 3D.
```

### match_moon_snowy_night

```
Children's storybook watercolor illustration, warm and luminous, Chinese riverside village on a winter night during heavy snowfall: thick real snow piled on tiled roofs, on the ground of a courtyard and on a small moored boat; big snowflakes falling from an overcast sky with no moon visible; bare trees heavy with snow; a few windows glowing faintly warm. Soft gouache texture; clear foreground, middle ground and background; palette of pumpkin gold #FFB928, sky blue #5B9BF3, leaf green #61B879 and cream #FFF8E8, with deep night blue for the sky. Square 1:1, 1024×1024. No people in the foreground, no mascot, no animals other than those described, no text, no border, not 3D.
```

### match_moon_maple_river_night

```
Children's storybook watercolor illustration, warm and luminous, Chinese autumn river near an old southern water town late at night: a thin crescent moon sinking low near the horizon, two or three crows on a branch, red-orange maple trees along the riverbank, small warm lantern lights of fishing boats glowing on the dark water, a covered passenger boat moored in the foreground, and beyond an old city wall the roof of a temple with a bell tower faintly in the distance. Cold, misty air with a pale frosty sheen, no snow on the ground. Soft gouache texture; clear foreground, middle ground and background; palette of pumpkin gold #FFB928, sky blue #5B9BF3, leaf green #61B879 and cream #FFF8E8, with deep night blue for the sky. Square 1:1, 1024×1024. No people in the foreground, no mascot, no animals other than those described, no text, no border, not 3D.
```

### match_moon_spring_river_moon

```
Children's storybook watercolor illustration, warm and luminous, Chinese wide river (the Yangtze) on a mild spring night: the near south bank covered in fresh green grass and new willow leaves, a bright full moon rising over the water and reflecting on gentle waves, a small boat moored at a ferry landing in the foreground, a small town on the opposite bank and a few layers of soft hills behind it. Soft gouache texture; clear foreground, middle ground and background; palette of pumpkin gold #FFB928, sky blue #5B9BF3, leaf green #61B879 and cream #FFF8E8, with deep night blue for the sky. Square 1:1, 1024×1024. No people in the foreground, no mascot, no animals other than those described, no text, no border, not 3D.
```

### match_moon_double_ninth_hill

```
Children's storybook watercolor illustration, warm and luminous, Chinese hilltop on a clear autumn day for the Double Ninth Festival: a small wooden pavilion on the summit, dogwood (zhuyu) shrubs with clusters of small red berries beside the stone path, a few cut sprigs of dogwood laid on a stone bench, yellow chrysanthemums, layered blue hills and a far-away village below. At most one tiny distant silhouette climbing the path far away, faceless. Bright, crisp and airy. Soft gouache texture; clear foreground, middle ground and background; palette of pumpkin gold #FFB928, sky blue #5B9BF3, leaf green #61B879 and cream #FFF8E8. Square 1:1, 1024×1024. No people in the foreground, no mascot, no animals other than those described, no text, no border, not 3D.
```

### match_moon_midautumn_courtyard

```
Children's storybook watercolor illustration, warm and luminous, Chinese family courtyard on Mid-Autumn Festival night: a huge full moon above the roofs, many round red and gold paper lanterns glowing along the eaves, a round table set with mooncakes, pomelos, grapes and a teapot, several empty stools waiting for a family gathering, osmanthus tree in bloom. Festive and cheerful. Soft gouache texture; clear foreground, middle ground and background; palette of pumpkin gold #FFB928, sky blue #5B9BF3, leaf green #61B879 and cream #FFF8E8, with deep night blue for the sky. Square 1:1, 1024×1024. No people in the foreground, no mascot, no animals other than those described, no text, no border, not 3D.
```

### match_moon_sewing_lamp

```
Children's storybook watercolor illustration, warm and luminous, Chinese home interior in the evening, still life: on a wooden table under the warm glow of an oil lamp lie a needle and thread, a sewing basket and a traveller's cloth robe being finished with many neat, close stitches; beside the door, a packed cloth travel bundle, a bamboo hat and a walking stick ready for a long journey; through the window, a deep blue evening sky. Soft gouache texture; clear foreground, middle ground and background; palette of pumpkin gold #FFB928, sky blue #5B9BF3, leaf green #61B879 and cream #FFF8E8, with deep night blue for the sky. Square 1:1, 1024×1024. No people in the foreground, no mascot, no animals other than those described, no text, no border, not 3D.
```

---

## 16. scene_scene_match（含贝贝）

页面会从图片顶部向下裁切，底部约 30% 淡入奶白色；左上角放标题和返回按钮。

```
Children's storybook watercolor illustration, warm and luminous, a Chinese garden terrace at dusk under a rising full
moon. The small golden-orange pumpkin character "Beibei" (round pumpkin body with five soft ribs, green curled stem with
one small leaf, dark brown oval eyes, soft pink cheeks, curious happy smile, small sky-blue scarf, short rounded arms and
feet) stands on the right third of the picture holding up three small blank cream-coloured picture cards fanned out in
one hand, looking at them thoughtfully, the other arm pointing at the moon. Behind: a low garden wall, a willow, soft blue
hills and a deep-blue-to-peach evening sky. The upper-left quarter is calm sky with almost no detail, reserved for a
title. Palette pumpkin gold #FFB928, sky blue #5B9BF3, leaf green #61B879, cream #FFF8E8, deep evening blue. Soft gouache
texture, clear layers. Landscape 3:2, 1536×1024, the cards are blank, no text, no border, no other characters, not 3D,
no Halloween face.
```

## 17. scene_parent_corner（含贝贝）

显示在家长区域入口（算术题上方），高约 170pt，四角是圆角，所以主体要放在画面中间。

```
Children's storybook watercolor illustration, warm and cozy, a quiet Chinese reading corner in late afternoon: a
wooden armchair with a folded blanket and a cup of tea on a small side table (for a parent), a low bookshelf with
hand-bound books, a window with a soft blue sky and a willow branch. The small golden-orange pumpkin character "Beibei"
(round pumpkin body, green curled stem with one leaf, brown eyes, pink cheeks, small sky-blue scarf) sits on a floor
cushion beside the armchair reading a blue book, calm and content, at the centre-right. Warm wooden tones, cream
#FFF8E8, pumpkin gold #FFB928, sky blue #5B9BF3, leaf green #61B879. Main subjects kept within the central 70% of the
frame. Soft gouache texture. Landscape 3:2, 1536×1024, no text anywhere, no border, no people, not 3D, no Halloween face.
```
