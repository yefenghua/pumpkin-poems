# 第二阶段 API 约定（客户端 ↔ Go 服务）

- 状态：第二阶段实现所依据的接口约定。客户端与服务端都以本文为准；改动时两边同时更新。
- 依据：[第二阶段规划](../phase-2-learning-release.md) §3、§5。

所有接口 JSON、UTF-8；时间一律 RFC 3339（UTC，带 `Z`）。错误响应统一为
`{"error": {"code": "snake_case_code", "message": "human readable"}}`，HTTP 状态码表示类别。
服务不可用时客户端照常离线使用；任何接口失败都不能阻塞学习。

## 1. 内容发布（L02、L06）

内置基础包随 App 发布、始终可用。其余主题以“主题包”下载。内容与（未来的）音频在同一发布清单里。

### `GET /v1/content/manifest`

```json
{
  "release": "2026-11-01.1",
  "formatVersion": 2,
  "publishedAt": "2026-11-01T02:00:00Z",
  "packs": [
    {
      "id": "farewell",
      "version": "2026-11-01.1",
      "title": {"zh-Hant": "友情送別", "zh-Hans": "友情送别"},
      "summary": {"zh-Hant": "…", "zh-Hans": "…"},
      "poemCount": 6,
      "size": 48213,
      "sha256": "hex",
      "url": "/v1/content/packs/farewell/2026-11-01.1.json",
      "audio": []
    }
  ],
  "withdrawnQuestions": ["hk-ks1-10-q-word"]
}
```

- `size` / `sha256` 针对 pack 文件原始字节。客户端下载完成后校验两项，都相符才切换；失败保留旧版本。
- `audio`：`[{ "path": "...", "size": n, "sha256": "hex", "url": "..." }]`，本阶段为空数组（录音未交付）。
- `withdrawnQuestions`：已撤回的题目 ID（任何包，包括内置包）。客户端不再出这些题，旧错题记录保留但标为“题目已撤回”，不影响学习判断。
- 只有状态为 `published` 的包出现在清单中。

### `GET /v1/content/packs/{packID}/{version}.json`

返回 pack 文件（不可变，可长期缓存）。格式与 App 内置的 `PoemContent.json` 一致（`formatVersion: 2`）：

```json
{
  "formatVersion": 2,
  "packID": "farewell",
  "version": "2026-11-01.1",
  "themes": [ … ],
  "poems": [ … ],
  "hantToHans": { … },
  "sceneMatch": null
}
```

内置包 `packID` 为 `base`。

## 2. 试用反馈与统计（L07）

匿名：`installID` 为安装时生成的 UUID，不含真实身份。默认不上传作品正文或自由输入全文。

### `POST /v1/events`

```json
{
  "installID": "uuid",
  "appVersion": "1.1",
  "events": [
    {
      "id": "uuid",
      "name": "quiz_completed",
      "at": "2026-11-01T03:04:05Z",
      "contentVersion": "2026-11-01.1",
      "ruleVersion": 2,
      "props": {"poemID": "hk-ks1-10", "passed": true, "isReview": false, "usedHints": false}
    }
  ]
}
```

响应 `200 {"accepted": 3, "duplicates": 0}`。事件 `id` 去重，重复上传不重复计数。`props` 的值只允许字符串、数字、布尔。

事件名：`poem_learning_started`、`quiz_completed`、`review_completed`、`creation_started`、`creation_saved`、
`content_download_failed`、`content_pack_installed`、`sync_failed`、`feedback_sent`。

### `POST /v1/feedback`

```json
{"id": "uuid", "installID": "uuid", "at": "…", "category": "content|bug|idea|other",
 "message": "家长写的反馈", "contentVersion": "…", "appVersion": "1.1"}
```

响应 `201 {}`；同一 `id` 重复提交返回 `200 {}`。反馈是用户主动填写，正文允许保存。

### `GET /v1/admin/metrics?from=2026-11-01&to=2026-11-15`

需 `Authorization: Bearer <ADMIN_TOKEN>`。按 `contentVersion` 分组返回第二阶段 §8 的五项观测口径：

```json
{"from": "…", "to": "…", "groups": [{"contentVersion": "…",
  "learningCompletion": {"numerator": 8, "denominator": 10},
  "dueReviewParticipation": {"numerator": 5, "denominator": 9},
  "crossDayUnaidedPass": {"numerator": 4, "denominator": 6},
  "secondWeekReturn": {"numerator": 3, "denominator": 7},
  "creationCompletion": {"numerator": 2, "denominator": 4}}]}
```

口径（均按 installID，统计窗口内）：
- learningCompletion：有 `quiz_completed`（首次，`isReview=false`）的 install ／有 `poem_learning_started` 的 install。
- dueReviewParticipation：有 `review_completed` 的 install-日 ／ 上报过 `props.dueCount > 0` 的 `poem_learning_started` 或 `review_completed` 或 `app_day_opened` 的 install-日。客户端每天首次打开发送 `app_day_opened {dueCount}`。
- crossDayUnaidedPass：`review_completed` 中 `passed && !usedHints` 的条数 ／ `review_completed` 总条数。
- secondWeekReturn：首个 `poem_learning_started` 之后第 8–14 天内又有 `quiz_completed` 的 install ／ 首次学习至少已过 14 天的 install。
- creationCompletion：有 `creation_saved` 的 install ／ 有 `creation_started` 的 install。

## 3. 家长账号与儿童档案（L08）

儿童不登录。家长用**账号 ID + 密码**建立账号。服务端只保存小写的账号 ID 和密码的 Argon2id 哈希，不保存邮箱、手机、姓名。
因此没有“忘记密码”流程：忘记密码只能重新注册一个账号（本机学习记录不受影响）。客户端在注册和修改密码时都要把这点告诉家长。

- `accountID`：4–32 个字符，只能是 `a-z`、`0-9`、`.`、`_`、`-`，首字符须为字母或数字；不区分大小写，服务端统一转小写并原样返回。
- `password`：8–128 个字符（按 Unicode 字符计），不限制组成，不得与账号 ID 相同。

### `POST /v1/auth/register`

`{"accountID": "mama.lee", "password": "…"}` → `201 {"accessToken": "…", "expiresAt": "…", "parentID": "uuid", "accountID": "mama.lee"}`

错误：`400 invalid_account_id`、`400 weak_password`、`409 account_id_taken`。注册成功即已登录。

### `POST /v1/auth/login`

`{"accountID": "…", "password": "…"}` → `200`，响应同上（每次登录发新令牌，旧令牌继续有效到过期）。

- 账号不存在和密码错误都返回 `401 invalid_credentials`，不区分。
- 同一账号 15 分钟内失败 10 次后返回 `429 too_many_attempts`（带 `Retry-After` 秒数），窗口过后自动解除。

### `POST /v1/auth/logout`

需 `Authorization`。使当前令牌失效 → `204`。只影响这一部装置。

### `POST /v1/auth/password`

需 `Authorization`。`{"currentPassword": "…", "newPassword": "…"}` → `204`。
错误：`403 wrong_password`、`400 weak_password`。成功后**其他装置全部登出**（只保留发起请求的令牌）。

### `GET /v1/account`

需 `Authorization`。→ `200 {"parentID": "uuid", "accountID": "mama.lee", "createdAt": "…"}`

其余接口都需 `Authorization: Bearer <accessToken>`；令牌失效返回 `401`，客户端回到“未登录”状态但本地数据保留。

### 档案

- `GET /v1/profiles` → `{"profiles": [{"id": "uuid", "nickname": "小明", "stage": "p4|p5|p6|s1|null", "createdAt": "…"}]}`
- `POST /v1/profiles` `{"id": "uuid(客户端生成)", "nickname": "…", "stage": null}` → `201 profile`；同一 `id` 再次提交返回 `200` 原记录（幂等）。
- `PATCH /v1/profiles/{id}` `{"nickname"?: "…", "stage"?: "…"}` → `200 profile`
- `DELETE /v1/profiles/{id}` → `204`，同时删除该档案的全部学习事件与作品。
- `DELETE /v1/account` → `204`，删除家长账号、全部档案和云端数据。

只能访问自己账号下的档案，否则 `404`。

## 4. 同步（L09）

每个儿童档案一条同步通道。学习记录以**不可变学习事件**同步（事件 ID 去重，客户端按规则重放得出当前状态），作品以**带修订号的记录**同步。

### `POST /v1/profiles/{id}/sync`

请求：

```json
{
  "cursor": 120,
  "events": [
    {"id": "uuid", "kind": "quiz", "poemID": "hk-ks1-10", "at": "…", "deviceID": "uuid", "payload": { … }}
  ],
  "drafts": [
    {"id": "uuid", "baseRevision": 3, "deleted": false, "updatedAt": "…", "data": { … }}
  ]
}
```

响应：

```json
{
  "cursor": 131,
  "events": [ {"seq": 121, "id": "uuid", "kind": "…", "poemID": "…", "at": "…", "deviceID": "…", "payload": { … }} ],
  "drafts": [ {"seq": 125, "id": "uuid", "revision": 4, "deleted": false, "updatedAt": "…", "data": { … }} ],
  "draftResults": [ {"id": "uuid", "status": "applied", "revision": 4} ,
                    {"id": "uuid", "status": "conflict", "revision": 6} ]
}
```

规则：
- 事件：按 `(profileID, id)` 去重；已存在的事件忽略（不报错、不改写）。每条新事件分配递增 `seq`。`payload` 原样保存，服务端不解释其内容。
- 响应的 `events` / `drafts` 是 `seq > cursor` 的全部变更（可能包含本次刚推送的，客户端按 `id` 去重）。`cursor` 为当前最大 `seq`。单次最多返回 1000 条事件；若还有更多，响应带 `"hasMore": true`，客户端用新 cursor 再请求一次（`events` / `drafts` 可为空）。
- 作品：`baseRevision` 为客户端上次见到的服务端修订号（新作品为 `0`）。
  - 服务端当前修订号等于 `baseRevision` → 写入，`revision + 1`，`status: applied`。
  - 不相等 → 不覆盖，`status: conflict`，并在 `drafts` 中返回服务端当前版本。客户端把自己的版本另存为“冲突副本”（新 `id`），两份都保留，交给孩子或家长选择。
  - 删除：`deleted: true` 作为墓碑保存（`data` 置空），之后任何 `baseRevision` 小于墓碑修订号的写入都返回 `conflict`，客户端接受删除，不能让旧设备把作品“复活”。
- 游客数据迁移：家长选择目标档案后，客户端把游客的全部事件和作品作为普通同步推送到该档案。事件 ID 不变，所以重复绑定不会重复计入。

事件 `kind`（客户端定义，服务端不解释）：`legacySnapshot`、`read`、`step`、`selfAssess`、`favorite`、`quiz`、`retry`、`game`、`goal`、`sceneMatch`。

`data`（作品）：`{"title", "themeID", "wordIDs", "lines", "mode": "imitate|free", "form": 0|5|7, "status": "draft|finished", "exampleLineID", "createdAt", "conflictOf"}`。

## 5. 健康检查

`GET /healthz` → `200 {"ok": true, "release": "2026-11-01.1"}`。
