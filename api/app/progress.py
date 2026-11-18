from collections import Counter
from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo

ZONE = ZoneInfo("America/Sao_Paulo")
DAY = timedelta(days=1)
ICONS = ("book", "fitness", "water", "mind", "spark")
COLORS = ("violet", "mint", "amber", "blue", "rose")
ACHIEVEMENTS = {
    "first_checkin": "Primeiro passo",
    "first_weekly_goal": "Meta conquistada",
    "streak_7": "Sete dias de ritmo",
    "streak_30": "Trinta dias de ritmo",
}


def week_start(day):
    return day - timedelta(days=day.weekday())


def checkin_days(db, habit_id):
    return {
        date.fromisoformat(row["local_date"])
        for row in db.execute("SELECT local_date FROM checkins WHERE habit_id = ?", (habit_id,))
    }


def streak(days, today):
    cursor = today if today in days else today - DAY
    length = 0
    while cursor in days:
        length += 1
        cursor -= DAY
    return length


def habit_summary(db, habit, today):
    habit = dict(habit)
    days = checkin_days(db, habit["id"])
    weekly = Counter(week_start(day) for day in days)
    start = week_start(today)
    target = habit["weekly_target"]
    created = datetime.fromisoformat(habit["created_at"]).astimezone(ZONE)
    archived = datetime.fromisoformat(habit["archived_at"]).astimezone(ZONE).date() if habit["archived_at"] else None
    first_full = week_start(created.date())
    if created.weekday() or created.hour or created.minute or created.second or created.microsecond:
        first_full += timedelta(weeks=1)
    end = min(start, week_start(archived)) if archived else start
    complete_weeks = max(0, (end - first_full).days // 7)
    attended = sum(min(count, target) for week, count in weekly.items() if first_full <= week < end)
    habit.update(
        completed_today=today in days,
        weekly_count=weekly[start],
        week_days=[(start + DAY * i).isoformat() for i in range(7) if start + DAY * i in days],
        streak=0 if archived else streak(days, today),
        adherence=attended / (complete_weeks * target) if complete_weeks else None,
    )
    return habit


def score(db):
    total = db.execute("SELECT COALESCE(SUM(xp), 0) FROM reward_events").fetchone()[0]
    return {"total_xp": total, "level": 1 + total // 100}


def badges(db):
    earned = {
        (row["habit_id"], row["code"]): row["unlocked_at"]
        for row in db.execute("SELECT * FROM achievements")
    }
    return [
        {
            "habit_id": habit["id"], "habit_name": habit["name"], "code": code,
            "title": title, "unlocked_at": earned.get((habit["id"], code)),
        }
        for habit in db.execute("SELECT id, name FROM habits ORDER BY id")
        for code, title in ACHIEVEMENTS.items()
    ]


def record_checkin(db, habit, today, now):
    key = (habit["id"], today.isoformat())
    insert = db.execute(
        "INSERT INTO checkins VALUES (?, ?, ?) ON CONFLICT(habit_id, local_date) DO NOTHING",
        (*key, now),
    )
    created = insert.rowcount == 1
    awarded = 0
    days = checkin_days(db, habit["id"])
    start = week_start(today)
    count = sum(start <= day <= today for day in days)
    if created:
        db.execute("INSERT INTO reward_events VALUES (?, 'daily', ?, 10, ?)", (*key, now))
        awarded = 10
        milestones = ["first_checkin"]
        if count >= habit["weekly_target"]:
            bonus = db.execute(
                """INSERT INTO reward_events VALUES (?, 'weekly', ?, 50, ?)
                ON CONFLICT(habit_id, kind, period_key) DO NOTHING""",
                (habit["id"], start.isoformat(), now),
            )
            awarded += 50 * bonus.rowcount
            milestones.append("first_weekly_goal")
        length = streak(days, today)
        milestones.extend(f"streak_{threshold}" for threshold in (7, 30) if length >= threshold)
        db.executemany(
            """INSERT INTO achievements VALUES (?, ?, ?)
            ON CONFLICT(habit_id, code) DO NOTHING""",
            [(habit["id"], code, now) for code in milestones],
        )
    return {
        "checkin": {"habit_id": key[0], "local_date": key[1]},
        "created": created,
        "awarded_xp": awarded,
        "progress": {
            "weekly_count": count, "weekly_target": habit["weekly_target"],
            "weekly_goal_met": count >= habit["weekly_target"], **score(db),
        },
    }
