# 古诗词内容库

本次收录 **167 首作品**：香港课程核心篇目 `core` 53 首、课外拓展 `extension` 114 首；另有 **74 份作者资料**和 **870 条语境化重点词注释**。正文、题目、朝代、体裁、作者短简介与完整简介、重点词及其解释均提供 `zh-Hant` / `zh-Hans` 两个版本。整理日期：2026-10-22。

## 香港 core 的范围

以香港教育局《中国语文课程建议篇章》第一至第四学习阶段配套资料为可核对的基准，收齐其中的诗、词、曲。组合篇目拆成独立作品，全文收录；散文、寓言、铭和家训不计入古诗词数量。官方“建议篇章”不等于全港统一教材，也不代表所有作品都是文凭试指定考核作品。

| 学习阶段 | 适用阶段 | core 数量 | 官方目录 |
| --- | --- | ---: | --- |
| 1 | 小一至小三 | 18 | [教育局第一学习阶段](https://www.edb.gov.hk/tc/curriculum-development/kla/chi-edu/key-stage1.html) |
| 2 | 小四至小六 | 14 | [教育局第二学习阶段](https://www.edb.gov.hk/tc/curriculum-development/kla/chi-edu/key-stage2.html) |
| 3 | 中一至中三 | 11 | [教育局第三学习阶段](https://www.edb.gov.hk/tc/curriculum-development/kla/chi-edu/key-stage3.html) |
| 4 | 中四至中六 | 10 | [教育局第四学习阶段](https://www.edb.gov.hk/tc/curriculum-development/kla/chi-edu/key-stage4.html) |

完整对应关系和排除的非诗词篇目在 `sources/hk-core-catalog.json`。第二阶段《题西林壁》《晓出净慈寺送林子方》的官方网页序号与 PDF 文件编号顺序不同，映射以实际题文核对结果为准。

拓展部分单独超过 100 首，包括唐诗 76 首、宋词 26 首、元曲 8 首、《诗经》3 首及曹操《观沧海》1 首。全库另包含汉、三国、东晋、南北朝、五代、明、清作品。拓展是项目编辑选目，不能把 `extension` 解读成“香港任何学校都不教”。

## 文件与字段

- `articles/<id>.json`：**一首作品一个文件，顶层为一个 JSON 对象**，不是数组或 JSONL。单文件包含全文、小序（若所据底本收录）、繁简重点词释义，以及作者资料完整快照。
- `author/<id>.json`：**一位作者／一种匿名文献传统一个文件**，为作者资料的维护主记录。`biography.short` 为短简介，`biography.full` 为完整简介。
- `manifest.json`：总目录、数量统计、作品及作者路径。
- `sources/hk-core-catalog.json`：独立 core 覆盖清单。
- `sources/text-baselines.json`：古典原文和已校对文本快照，供离线完整性回归检查；不收录来源网站的现代赏析。
- `sources/chinese-poetry-LICENSE.txt`：拓展文本整理数据来源的 MIT 许可说明。
- `scripts/validate.py`：无第三方依赖的内容校验脚本。

作品的主要字段：

| 字段 | 用途 |
| --- | --- |
| `id` / `schema_version` | 稳定标识与结构版本；修订标题或分类时保留既有 ID |
| `category` / `priority` | `core` 对应 P0，`extension` 对应 P1 |
| `title` / `dynasty` / `genre` | 两种文字版本的题目、作品所属时代、体裁 |
| `text` / `preface` | 两种文字版本的全文与小序；空字符串表示所据版本没有收录小序 |
| `lines` | 两种文字版本共用 ID 的阅读分段，按逗号及句末标点拆分；不等同于格律意义的诗行，也不标注词的上下片 |
| `annotations` | 重点词、原创释义、繁简各自的定位信息 |
| `author_id` / `author_file` / `author` | 作者关联、相对路径与完整作者快照，支持单篇离线使用 |
| `curriculum` | core 的官方依据及学习阶段；extension 为 null |
| `sources` | 公开来源链接、访问日期、可用的源文件哈希或源数据记录索引 |
| `edition_notes` / `text_edits` | 版本差异、署名争议及具体改字记录 |
| `editorial` | 注释和简介的编写来源及专业审校状态 |

双语字段形如 `{"zh-Hant": "靜夜思", "zh-Hans": "静夜思"}`。作者跨朝代时，作者生平的时代标签可与某首作品的时代不同，例如韦庄作者资料为“唐至五代”，《台城》归唐诗。

`annotations[].occurrences` 分别提供两种文字版本的位置。`scope` 为 `body`、`title` 或 `preface`；正文使用 `line_id` 指向阅读分段。`start` / `end` 是 **从 0 开始的 Unicode 码点区间，左闭右开**，不能直接当作 Swift `String.Index` 或 UTF-16 的 `NSRange`。同一词出现多次会保留多个位置。

匿名作品不合并为一个虚构人物：汉乐府、《古诗十九首》、北朝乐府、《诗经》各有独立作者记录，`is_collective_attribution` 为 true。

## 底本、繁简与内容边界

core 繁体以教育局原文 PDF 为底本，去除排版空白与网页说明，保留原有词句和字形；非标准问号统一为全角问号。简体对应同一底本，不换成另一种流行版本。例如：

- 《七步诗》采用六句本；《赋得古原草送别》保留八句全文。
- 小学《凉州词》为王翰作品，王之涣同题作品另列 extension。
- 《静夜思》保留繁体“牀”；《悯农》采用“盘中飧”；《送元二使安西》采用“裛轻尘”。
- 《木兰诗》采用“愿借明驼千里足”版本。《燕诗》《水调歌头》保留教育局所载小序。
- 《金缕衣》《满江红》等署名争议在作品及作者资料中说明。

拓展文本主要据 [chinese-poetry 数据库](https://github.com/chinese-poetry/chinese-poetry)，筛掉重复收录和误配作者的条目；元曲组曲按独立作品拆分。部分明显脱误另据维基文库、中华诗词网等核对，逐篇记录校对链接。拓展底本可能与某些教材有异文，例如《相思》的“秋来发故枝”、《凉州词》的“春光不度玉门关”；相关条目已注明，不擅自把多个版本拼合。

繁简通过 OpenCC 辅助转换，再处理具体语境、香港字形、专名及重点词定位。作者简介与重点词解释为本项目重新撰写，不直接复制教育局或其他网站的现代赏析。古典原作属于公版作品；来源网站的现代内容、音频、图片不包含在本次交付中。

本次交付是可直接读取的文本资料库，不含逐句白话翻译、粤普读音、练习题或录音。资料已做来源及程序校验；未宣称经过外部语文教师或古典文学专家逐篇审定，`specialist_review_completed` 保留为 false。对于难词、历史年代与存疑归属，说明比伪造精确结论优先。

## 校验与维护

在项目根目录执行：

```sh
python3 poems/scripts/validate.py
```

保存报告：

```sh
python3 poems/scripts/validate.py --report poems/validation-report.json
```

检查覆盖 53 首 core 的固定 ID 清单、extension 超过 100 首、繁简字段齐全、正文与基准一致、分段无缺漏、870 条注释的原文位置、作者关联与快照一致、去重及目录统计。程序校验可以发现结构和完整性问题，不能代替文学解释的专业判断。

修改作者主记录时，同步更新引用它的作品内 `author` 快照；修改正文时，重新检查繁简词义和注释位置，并在核对来源后更新 `text-baselines.json`。来源基准不能未经核对就跟随改动，以免失去回归检查作用。
