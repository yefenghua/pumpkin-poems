# 贝贝古诗 · 原生 UI 图片交付包

正式交付 **16 张 PNG**，包括三张带贝贝的首页一体场景。全部使用内置 image_gen 生成或基于现有图片编辑，完整提示词见 `generation-prompts.json`；其中保留了中间修订记录，但正式资源只以 `manifest.json` 和资源目录为准。

## 导入 Xcode

将 `PoetryArtwork.xcassets` 拖入工程并确认目标成员，或将其中 imageset 合并到现有 Asset Catalog。二选一，避免同名资源重复。图片按 Single Scale / Universal 配置；保留原始像素，通过 SwiftUI 明确显示尺寸，不要按图片原始像素推断 pt。导入后将渲染方式保持为 Original。

```swift
Image("home_seasons")
    .resizable()
    .scaledToFit()
    .accessibilityHidden(true)
```

以上为资源使用示例，尚未接入或编译用户 App。

## 关键约定

- 首页主题一共三张，分别为月与思乡、山水田园、四季景物，全部已包含读书的贝贝。不要再叠加独立南瓜图层。
- 成长页 `scene_growth_with_mascot` 已包含庆祝角色。
- 四季系列沿用用户选定的明亮蓝天桃花绘本风：贝贝坐在树下，配套图沿用同一棵树和小鸟。没有山水亭台，也不采用中间的米白花鸟特写版本。
- 月夜与田园系列分别从各自现有母图衍生；继续学习小景与首页保持同主题。
- 首页三图均为正方形。尽量保持完整构图，角色约在下半部；不要用严重裁切的横幅容器。月夜底部没有奶油色渐隐，可用原生渐变或卡片覆盖衔接。
- 首页的标题文字在左上。月夜版使用暖白文字，田园和四季版用深色文字；必要时增加轻微局部遮罩保证对比度。
- “继续学习按钮图”是卡片右侧的场景插画。按钮、文字、卡片边框仍由 SwiftUI 绘制。
- 书封「古詩」及复习卷轴《靜夜思》的诗文已经画入素材。它们是装饰，不替代原生可访问诗歌正文。简体界面中也会保留这两处繁体书法。
- 当前四季系列表现春日花鸟，后续冬雪等明确题材应另配变体；不要把全部季节都解释成春天。
- `mascot_peeking` 仅用于解释框助手。无角色背景、独立读书/庆祝角色和旧主题图留在原始生成目录供参考，未混入本交付包。

## 主题资源映射

| 主题 | 首页 | 继续学习 | 学习页 | 收藏封面 |
|---|---|---|---|---|
| 月与思乡 | `home_moonlight` | `art_continue_moonlight` | `scene_poem_moonlight` | `cover_moon` |
| 山水田园 | `home_landscape` | `art_continue_landscape` | `scene_poem_landscape` | `cover_landscape` |
| 四季景物 | `home_seasons` | `art_continue_seasons` | `scene_poem_seasons` | `cover_seasons` |

使用诗歌显式分类选图，同一首诗跨页面保持一致；没有分类时使用原生纸面作为中性兜底，不默认月夜图。已有多分类规则由产品数据决定。

## 实际尺寸与格式

| 资源 | 像素尺寸 | 透明背景 |
|---|---|---|
| `home_moonlight` | 1254 × 1254 | 否 |
| `home_landscape` | 1254 × 1254 | 否 |
| `home_seasons` | 1254 × 1254 | 否 |
| `scene_growth_with_mascot` | 1313 × 1198 | 否 |
| `scene_poem_moonlight` | 1374 × 1145 | 否 |
| `scene_poem_landscape` | 1374 × 1145 | 否 |
| `scene_poem_seasons` | 1374 × 1145 | 否 |
| `cover_moon` | 971 × 1619 | 否 |
| `cover_landscape` | 972 × 1619 | 否 |
| `cover_seasons` | 971 × 1619 | 否 |
| `art_continue_moonlight` | 1254 × 1254 | 是 |
| `art_continue_landscape` | 1254 × 1254 | 是 |
| `art_continue_seasons` | 1254 × 1254 | 是 |
| `art_review_scroll` | 1355 × 1160 | 是 |
| `art_flower_game` | 1355 × 1161 | 是 |
| `mascot_peeking` | 1254 × 1254 | 是 |

## 验证范围

已检查 PNG 签名、数据块校验和、解压长度及图片尺寸；透明素材验证存在 0–255 的实际 alpha 范围。已逐张检查生成结果的视觉内容。资源目录与清单名称一致。尚未在真实 SwiftUI 页面中验证布局与裁切，接入 AI 需按 `ui-instruction.md` 完成设备验证。

双击 `preview.html` 可查看主题素材总览；不会请求网络。
