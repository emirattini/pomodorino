-- Users who connected their task manager, the watches linked to them, and what Todoist can't store.
-- Apply with: npx wrangler d1 migrations apply pomodorino --remote   (--local for `wrangler dev`)

CREATE TABLE users (
    id            TEXT PRIMARY KEY,      -- random, ours
    provider      TEXT NOT NULL,         -- 'todoist'
    account       TEXT NOT NULL,         -- the provider's user id
    access_token  TEXT NOT NULL,
    refresh_token TEXT,                  -- NULL: the token doesn't expire
    expires_at    INTEGER,               -- unix seconds; NULL: never
    created_at    INTEGER NOT NULL,
    UNIQUE (provider, account)           -- connecting the same account again reuses the user
);

-- One row per watch. While pairing, user_id is NULL and code (and, once the browser has started the
-- Todoist login, nonce) are set. The watch keeps the key; we only store its SHA-256.
CREATE TABLE devices (
    key_hash   TEXT PRIMARY KEY,
    user_id    TEXT REFERENCES users (id) ON DELETE CASCADE,
    code       TEXT UNIQUE,
    nonce      TEXT UNIQUE,
    created_at INTEGER NOT NULL
);

-- Session ids already recorded, so the watch's retries aren't counted twice.
CREATE TABLE sessions (
    user_id    TEXT NOT NULL,
    id         TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    PRIMARY KEY (user_id, id)
);

-- Minutes spent per task, for providers without time tracking.
CREATE TABLE spent (
    user_id TEXT NOT NULL,
    task_id TEXT NOT NULL,
    minutes INTEGER NOT NULL,
    PRIMARY KEY (user_id, task_id)
);
