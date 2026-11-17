-- Anonymous trial analytics (POST /v1/events). Deduplicated by client event id.
CREATE TABLE analytics_events (
    id              text PRIMARY KEY,
    install_id      text        NOT NULL,
    app_version     text        NOT NULL DEFAULT '',
    name            text        NOT NULL,
    at              timestamptz NOT NULL,
    content_version text        NOT NULL DEFAULT '',
    rule_version    integer,
    props           jsonb       NOT NULL DEFAULT '{}'::jsonb,
    received_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX analytics_events_at_idx ON analytics_events (at);

CREATE TABLE feedback (
    id              text PRIMARY KEY,
    install_id      text        NOT NULL,
    at              timestamptz NOT NULL,
    category        text        NOT NULL,
    message         text        NOT NULL,
    content_version text        NOT NULL DEFAULT '',
    app_version     text        NOT NULL DEFAULT '',
    received_at     timestamptz NOT NULL DEFAULT now()
);

-- Parent accounts. subject is "apple:<sub>" or "dev:<key>"; no e-mail or name is stored.
CREATE TABLE parents (
    id         uuid PRIMARY KEY,
    subject    text        NOT NULL UNIQUE,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- Opaque access tokens, stored as sha256(token).
CREATE TABLE sessions (
    token_hash bytea PRIMARY KEY,
    parent_id  uuid        NOT NULL REFERENCES parents (id) ON DELETE CASCADE,
    expires_at timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX sessions_parent_idx ON sessions (parent_id);

-- Child profiles. last_seq is the per-profile sync counter, updated under
-- SELECT ... FOR UPDATE in the same transaction that inserts changes.
CREATE TABLE profiles (
    id         text PRIMARY KEY,
    parent_id  uuid        NOT NULL REFERENCES parents (id) ON DELETE CASCADE,
    nickname   text        NOT NULL,
    stage      text,
    created_at timestamptz NOT NULL,
    last_seq   bigint      NOT NULL DEFAULT 0
);
CREATE INDEX profiles_parent_idx ON profiles (parent_id);

CREATE TABLE sync_events (
    profile_id text        NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
    id         text        NOT NULL,
    seq        bigint      NOT NULL,
    kind       text        NOT NULL,
    poem_id    text,
    at         timestamptz NOT NULL,
    device_id  text        NOT NULL DEFAULT '',
    payload    json        NOT NULL, -- json (not jsonb) keeps the client's bytes verbatim
    PRIMARY KEY (profile_id, id),
    UNIQUE (profile_id, seq)
);

-- Latest version of each draft; deleted rows are tombstones and are kept.
CREATE TABLE sync_drafts (
    profile_id text        NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
    id         text        NOT NULL,
    seq        bigint      NOT NULL,
    revision   bigint      NOT NULL,
    deleted    boolean     NOT NULL,
    updated_at timestamptz NOT NULL,
    data       json        NOT NULL,
    PRIMARY KEY (profile_id, id),
    UNIQUE (profile_id, seq)
);
