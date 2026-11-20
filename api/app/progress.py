from collections import Counter
import json
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
REQUIREMENTS = {
    "first_checkin": "Registre a primeira realização deste hábito.",
    "first_weekly_goal": "Cumpra a meta semanal deste hábito pela primeira vez.",
    "streak_7": "Realize este hábito por 7 dias consecutivos.",
    "streak_30": "Realize este hábito por 30 dias consecutivos.",
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
    habit['scheduled_days'] = json.loads(habit['scheduled_days'])
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
    last_week = min(start, week_start(archived)) if archived else start
    first_week = max(week_start(created.date()), last_week - timedelta(weeks=7))
    history = []
    cursor = first_week
    while cursor <= last_week:
        history.append({
            "week_start": cursor.isoformat(), "weekly_count": weekly[cursor],
            "weekly_target": target, "complete_week": first_full <= cursor < end,
        })
        cursor += timedelta(weeks=1)
    habit.update(
        completed_today=today in days,
        weekly_count=weekly[start],
        week_days=[(start + DAY * i).isoformat() for i in range(7) if start + DAY * i in days],
        streak=0 if archived else streak(days, today),
        adherence=attended / (complete_weeks * target) if complete_weeks else None,
        weekly_history=history,
        scheduled_today=not habit['scheduled_days'] or today.isoweekday() in habit['scheduled_days'],
    )
    quantity = db.execute(
        'SELECT quantity FROM daily_progress WHERE habit_id=? AND local_date=?',
        (habit['id'], today.isoformat()),
    ).fetchone()
    habit['today_quantity'] = quantity['quantity'] if quantity else (habit['daily_target'] if today in days else 0)
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
            "title": title, "requirement": REQUIREMENTS[code],
            "unlocked_at": earned.get((habit["id"], code)),
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


def refresh_achievements(db, habit):
    """Revoke only achievements no longer supported by any completed history."""
    days = checkin_days(db, habit['id'])
    weekly = Counter(week_start(day) for day in days)
    longest = run = 0
    previous = None
    for day in sorted(days):
        run = run + 1 if previous is not None and day - previous == DAY else 1
        longest = max(longest, run)
        previous = day
    qualified = {
        'first_checkin': bool(days),
        'first_weekly_goal': any(count >= habit['weekly_target'] for count in weekly.values()),
        'streak_7': longest >= 7,
        'streak_30': longest >= 30,
    }
    for code, valid in qualified.items():
        if not valid:
            db.execute('DELETE FROM achievements WHERE habit_id=? AND code=?', (habit['id'], code))


def set_today_quantity(db, habit, today, now, quantity):
    """Absolute, repeatable progress update; caller owns the write transaction."""
    before = score(db)['total_xp']
    key = (habit['id'], today.isoformat())
    db.execute(
        '''INSERT INTO daily_progress VALUES (?, ?, ?, ?)
        ON CONFLICT(habit_id, local_date) DO UPDATE SET quantity=excluded.quantity, updated_at=excluded.updated_at''',
        (*key, quantity, now),
    )
    if quantity >= habit['daily_target']:
        result = record_checkin(db, habit, today, now)
    else:
        db.execute('DELETE FROM checkins WHERE habit_id=? AND local_date=?', key)
        db.execute("DELETE FROM reward_events WHERE habit_id=? AND kind='daily' AND period_key=?", key)
        start = week_start(today)
        count = sum(start <= day < start + timedelta(days=7) for day in checkin_days(db, habit['id']))
        if count < habit['weekly_target']:
            db.execute(
                "DELETE FROM reward_events WHERE habit_id=? AND kind='weekly' AND period_key=?",
                (habit['id'], start.isoformat()),
            )
        refresh_achievements(db, habit)
        result = {
            'checkin': {'habit_id': habit['id'], 'local_date': today.isoformat()},
            'created': False, 'awarded_xp': score(db)['total_xp'] - before,
            'progress': {
                'weekly_count': count, 'weekly_target': habit['weekly_target'],
                'weekly_goal_met': count >= habit['weekly_target'], **score(db),
            },
        }
    result.update(today_quantity=quantity, completed_today=quantity >= habit['daily_target'])
    return result


def weekly_summary(db, today):
    """Compare elapsed days of this week with the same weekdays last week."""
    start = week_start(today)
    previous_start, previous_end = start - timedelta(weeks=1), today - timedelta(weeks=1)
    current = db.execute(
        'SELECT COUNT(*) FROM checkins WHERE local_date BETWEEN ? AND ?',
        (start.isoformat(), today.isoformat()),
    ).fetchone()[0]
    previous = db.execute(
        'SELECT COUNT(*) FROM checkins WHERE local_date BETWEEN ? AND ?',
        (previous_start.isoformat(), previous_end.isoformat()),
    ).fetchone()[0]
    best = db.execute(
        '''SELECT h.name, COUNT(*) AS total FROM checkins c JOIN habits h ON h.id=c.habit_id
        WHERE c.local_date BETWEEN ? AND ? GROUP BY h.id ORDER BY total DESC, h.id ASC LIMIT 1''',
        (start.isoformat(), today.isoformat()),
    ).fetchone()
    return {
        'current_count': current, 'previous_count': previous, 'delta': current - previous,
        'current_start': start.isoformat(), 'current_end': today.isoformat(),
        'previous_start': previous_start.isoformat(), 'previous_end': previous_end.isoformat(),
        'best_habit_name': best['name'] if best else None,
    }
