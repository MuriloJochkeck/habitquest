ALTER TABLE habits ADD COLUMN scheduled_days TEXT NOT NULL DEFAULT '[]';
ALTER TABLE habits ADD COLUMN reminder_time TEXT;
ALTER TABLE habits ADD COLUMN daily_target INTEGER NOT NULL DEFAULT 1 CHECK (daily_target BETWEEN 1 AND 1000000);
ALTER TABLE habits ADD COLUMN unit TEXT NOT NULL DEFAULT 'vez' CHECK (length(unit) BETWEEN 1 AND 24);

CREATE TABLE daily_progress (
    habit_id INTEGER NOT NULL REFERENCES habits(id),
    local_date TEXT NOT NULL,
    quantity INTEGER NOT NULL CHECK (quantity BETWEEN 0 AND 1000000000),
    updated_at TEXT NOT NULL,
    PRIMARY KEY (habit_id, local_date)
);

CREATE TABLE profile (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    avatar TEXT NOT NULL CHECK (avatar IN ('compass', 'leaf', 'flame'))
);
INSERT INTO profile (id, avatar) VALUES (1, 'compass');
