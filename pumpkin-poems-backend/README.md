# 贝贝古诗 · 第二阶段 Go 服务

Implements [`docs/api/phase2-api.md`](../docs/api/phase2-api.md): content release manifest and packs, anonymous trial events and feedback, trial metrics, parent accounts (account ID + password), child profiles, per-profile sync and account deletion. A modular monolith: one binary, PostgreSQL for structured data, plus `contentctl` for controlled content releases (no CMS).

## 目录结构

```
cmd/server            HTTP server (env config, graceful shutdown, slog)
cmd/contentctl        content release tool: validate / publish / rollback / withdraw-question / list
internal/api          HTTP handlers, auth middleware, JSON errors
internal/auth         account ID rules, Argon2id password hashing, login throttling, access tokens
internal/cloudsync    sync rules: event dedupe + seq, draft revisions, conflicts, tombstones, paging
internal/metrics      the five trial metrics (phase-2 plan §8)
internal/content      release layout on disk, pack validation, publishing
internal/store        storage interfaces
internal/store/memstore   in-memory store (dev, simulator, tests)
internal/store/pgstore    PostgreSQL store (pgx v5) + embedded migrations
internal/store/storetest  conformance suite run against both stores
```

## 本地运行（模拟器）

In-memory store; register a parent account from the app (家长区域 → 注册) or with curl. Data is lost on restart.

```sh
make publish-dev     # publish ../pumpkin-poems-app/build/packs into ./content-releases (trial, unreviewed)
make run             # = ADMIN_TOKEN=dev-admin go run ./cmd/server
curl localhost:8080/healthz
curl -d '{"accountID":"mama.lee","password":"correct horse battery"}' localhost:8080/v1/auth/register
```

Port 8080 is often taken; use `ADDR=:18080 make run`. The simulator reaches the host Mac at `http://localhost:<port>`.

| Env | Default | |
| --- | --- | --- |
| `ADDR` | `:8080` | listen address |
| `DATABASE_URL` | empty | empty → in-memory store |
| `CONTENT_DIR` | `./content-releases` | release directory written by `contentctl` |
| `ADMIN_TOKEN` | empty | bearer token for `/v1/admin/metrics`; empty disables it |
| `LOG_FORMAT` | `json` | `text` for readable local logs |

## 使用 PostgreSQL

```sh
make db-up                               # docker compose, postgres:16 (PG_PORT=55432 make db-up if 5432 is taken)
make run-pg                              # migrations are applied automatically at startup
make test-pg                             # runs the store conformance suite against pumpkin_test
```

Migrations live in `internal/store/pgstore/migrations/NNNN_name.sql`, are embedded in the binary and recorded in `schema_migrations`. Add new files; never edit applied ones.

## 内容发布

Input: `pumpkin-poems-app/build/packs/<packID>.json` (produced by the app's content build) and the review checklist `pumpkin-poems-app/content/review-status.json`.

```sh
go run ./cmd/contentctl validate --packs ../pumpkin-poems-app/build/packs \
  --review ../pumpkin-poems-app/content/review-status.json

go run ./cmd/contentctl publish --packs ../pumpkin-poems-app/build/packs \
  --review ../pumpkin-poems-app/content/review-status.json \
  --out ./content-releases --release 2026-11-01.1 [--allow-unreviewed]
```

- `validate` checks required fields, `formatVersion` 2, file name = `packID`, poem and question IDs unique across all packs (base included), at least 5 questions per poem, known themes, and that every poem has a valid entry in the review checklist.
- `publish` refuses packs with poems that are not `approved`/`published`. `--allow-unreviewed` overrides this for the closed trial and prints a loud warning; `withdrawn` poems are always refused. The `base` pack is validated but never published (it ships in the app).
- Output: `content-releases/releases/<release>/manifest.json` and `packs/<id>/<version>.json`; the pack's `version` is rewritten to the release name. A pack whose content is unchanged keeps its previous version, so clients do not download it again. `current` is then switched atomically (temp file + rename). The server reads `current` on every manifest request, so no restart is needed.
- Releases are immutable and must never be deleted: later manifests may point at pack files in older release directories.
- Every action is appended to `content-releases/audit.log`.

```sh
go run ./cmd/contentctl list --out ./content-releases
go run ./cmd/contentctl rollback --out ./content-releases                 # previous release
go run ./cmd/contentctl rollback --out ./content-releases --to 2026-11-01.1
go run ./cmd/contentctl withdraw-question --out ./content-releases --question hk-ks1-10-q-word \
  [--release 2026-11-02.1] [--packs ../pumpkin-poems-app/build/packs]
```

`withdraw-question` creates a new release that is identical to the current one, adds the ID to `withdrawnQuestions` and makes it current. Withdrawn IDs carry over into later publishes. A fixed question should get a new ID. Questions in the built-in base pack can be withdrawn too; pass `--packs` to check that the ID exists.

## 审核清单流程

`review-status.json` holds one entry per poem: `status`, `textReviewed`, `audioReviewed`, `reviewer`, `note`.

`draft` → `pending` (ready for the teacher) → `approved` (text, explanations, questions and audio checked) → `published` (shipped in a release; set after publishing) → `withdrawn` (pulled: remove the poem from its pack before the next publish).

Only `approved`/`published` poems can be published without `--allow-unreviewed`. The checklist is edited and reviewed in git like code, so every change has an author and a history.

## 权限隔离

- Publishing is done with `contentctl` by operators who can write to `CONTENT_DIR` on the server host. There is no publishing API.
- `/v1/admin/metrics` uses a separate `ADMIN_TOKEN`.
- Parent accounts can only reach their own profiles; anything else returns `404`. The server stores only the lower-cased account ID and an Argon2id password hash (PHC string, 19 MiB / 2 iterations / 1 lane), with no e-mail, phone or name. There is therefore no password reset: a parent who forgets the password registers a new account (local learning data is unaffected).
- Account IDs: 4–32 characters, `a-z 0-9 . _ -`, case-insensitive. Passwords: 8–128 characters, no composition rules, must differ from the account ID.
- Login: unknown account and wrong password return the same `401 invalid_credentials` and take the same time (a dummy hash is verified). After 10 failures on one account within 15 minutes the account is throttled (`429 too_many_attempts`, `Retry-After`). The limiter is in-memory, per process.
- Access tokens are 32 random bytes, stored only as SHA-256 hashes, and valid for 30 days. `POST /v1/auth/logout` revokes the presented token; `POST /v1/auth/password` revokes every other session. `DELETE /v1/account` cascades to sessions, profiles, sync events and drafts.

## 测试

```sh
make test            # go vet + go test ./... (Postgres tests skip without TEST_DATABASE_URL)
make test-pg         # also runs the Postgres conformance suite
```
