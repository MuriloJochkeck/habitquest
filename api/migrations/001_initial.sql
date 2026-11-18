CREATE TABLE habits (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL CHECK (length(name) BETWEEN 1 AND 80),
    description TEXT NOT NULL DEFAULT '' CHECK (length(description) <= 280),
    icon TEXT NOT NULL,
    color TEXT NOT NULL,
    weekly_target INTEGER NOT NULL CHECK (weekly_target BETWEEN 1 AND 7),
    created_at TEXT NOT NULL,
    archived_at TEXT
);

CREATE TABLE checkins (
    habit_id INTEGER NOT NULL REFERENCES habits(id),
    local_date TEXT NOT NULL,
    created_at TEXT NOT NULL,
    PRIMARY KEY (habit_id, local_date)
);

CREATE TABLE reward_events (
    habit_id INTEGER NOT NULL REFERENCES habits(id),
    kind TEXT NOT NULL CHECK (kind IN ('daily', 'weekly')),
    period_key TEXT NOT NULL,
    xp INTEGER NOT NULL CHECK (xp > 0),
    created_at TEXT NOT NULL,
    PRIMARY KEY (habit_id, kind, period_key)
);

CREATE TABLE achievements (
    habit_id INTEGER NOT NULL REFERENCES habits(id),
    code TEXT NOT NULL,
    unlocked_at TEXT NOT NULL,
    PRIMARY KEY (habit_id, code)
);
