# 待生成插画与提示词

这些图片在 App 中还没有正式素材，对应位置目前显示**中性灰色占位区**（带资源名）。
生成后把 PNG 放进 `pumpkin-poems-app/pumpkin-poems-app/PoetryArtwork.xcassets/<资源名>.imageset/`，
`Contents.json` 照抄现有 imageset（单一通用尺寸），界面会自动切换为真图，不需要改代码。

统一风格（与 `generation-prompts.json` 保持一致）：温暖明亮的儿童绘本水彩插画，细腻手绘笔触，中国山水意境，
清楚的前中后景，金黄与自然蓝绿为主。贝贝设定不变：金黄色南瓜身体、绿色卷曲藤柄与一片小叶、深棕色圆眼睛、
柔和腮红、开心表情、蓝色小围巾、短而圆润的四肢；不是戴南瓜头的人，没有万圣节元素。不要在图中写任何文字。

| 资源名 | 用途 | 画幅 | 透明 |
|---|---|---|---|
| `scene_feihualing` | 飞花令页顶部场景 | 横版约 3:2，建议 1536×1024 | 否 |
| `scene_poet_workshop` | 小小诗人页顶部场景 | 横版约 3:2，建议 1536×1024 | 否 |
| `scene_celebration` | 学习完成页顶部场景 | 横版约 3:2，建议 1536×1024 | 否 |
| `art_poem_book` | 我的诗集页左上小图 | 正方形，建议 512×512 | 是（透明 PNG） |

页面会从图片顶部向下裁切（保留上半部分），并在底部约 30% 高度淡入奶白色；左上角会放原生标题与返回按钮，
所以**左上角区域请保持天空、远景等干净低对比内容**，主体和贝贝放在中间偏右或右侧。

## scene_feihualing

```
Children's storybook watercolor illustration, warm and luminous, Chinese spring garden. A small golden-orange pumpkin
character "Beibei" (round pumpkin body with five soft ribs, green curled stem with one small leaf, dark brown oval eyes,
soft pink cheeks, happy open smile, small sky-blue scarf, short rounded arms and feet) stands on the right third of the
picture, reaching up with both arms to catch pink peach-blossom petals drifting down in the breeze. Blossoming peach
branches arch in from the right edge; a low stone garden wall and a round moon gate in the middle distance; soft green
hills and a pale blue sky with light clouds on the left. The upper-left quarter is calm sky with gentle clouds and
almost no detail, reserved for a title. Clear foreground, middle ground and background; soft gouache texture; palette
of pumpkin gold #FFB928, sky blue #5B9BF3, leaf green #61B879, peach pink #F58D96, cream #FFF8E8. Landscape 3:2, no
text, no border, no frame, no other characters, not 3D, not plastic, no Halloween face.
```

## scene_poet_workshop

```
Children's storybook watercolor illustration, warm and cozy, a quiet Chinese study by an open window in late afternoon.
The small golden-orange pumpkin character "Beibei" (round pumpkin body with five soft ribs, green curled stem with one
small leaf, dark brown oval eyes, soft pink cheeks, gentle thoughtful smile, small sky-blue scarf, short rounded arms)
sits at a low wooden desk on the right side, holding a Chinese calligraphy brush over a sheet of blank cream paper, with
an ink stone, a small cup of brushes and one pink blossom in a little vase beside it. Through the open lattice window on
the left: a soft blue sky, a distant pale mountain and a willow branch; a few petals float in. The upper-left quarter
is calm sky through the window, low detail, reserved for a title. Warm wooden tones, cream paper, pumpkin gold #FFB928,
sky blue #5B9BF3, leaf green #61B879. Soft gouache texture, clear layers. Landscape 3:2, the paper on the desk is blank,
no text anywhere, no border, no other characters, not 3D, no Halloween face.
```

## scene_celebration

```
Children's storybook watercolor illustration, bright and joyful, a sunny Chinese garden meadow with wildflowers. The
small golden-orange pumpkin character "Beibei" (round pumpkin body with five soft ribs, green curled stem with one small
leaf, dark brown oval eyes, soft pink cheeks, big happy smile with eyes squeezed shut in delight, small sky-blue scarf,
short rounded arms and feet) jumps into the air slightly right of centre, holding up a small blank cream-coloured card
with a thin gold border in one hand, as if it just won it. Gold sparkles, small star shapes and pink petals burst
gently around it. Behind: a low green hill, a tiny pavilion and soft mountains, pale blue sky. The upper-left quarter
is calm sky with light clouds and almost no detail, reserved for a title. Palette pumpkin gold #FFB928, sky blue
#5B9BF3, leaf green #61B879, peach pink #F58D96, cream #FFF8E8. Soft gouache texture. Landscape 3:2, the card is blank,
no text, no border, no other characters, not 3D, no Halloween face.
```

## art_poem_book

```
Small children's storybook watercolor spot illustration on a fully transparent background: a hand-bound Chinese
notebook with a cream cover and a sky-blue cloth spine, lying slightly tilted, with a wooden calligraphy brush resting
across it and two or three pink peach-blossom petals beside it. A tiny golden pumpkin sticker (no face) on the cover
corner. Soft gouache texture, warm cream, sky blue #5B9BF3, pumpkin gold #FFB928, peach pink #F58D96. Square format,
subject centred and filling about 80% of the frame, soft shadow only under the book, transparent PNG, no text, no
border, no background scene.
```
