from datetime import UTC, date, timedelta
import json
import re

from flask import Blueprint, current_app, jsonify, request, url_for

from .db import connection, transaction
from .progress import COLORS, ICONS, ZONE, badges, habit_summary, score, set_today_quantity, week_start, weekly_summary

api = Blueprint("api", __name__)
FIELDS = ("name", "description", "icon", "color", "weekly_target", "scheduled_days", "reminder_time", "daily_target", "unit")
EDIT_FIELDS = ("name", "description", "icon", "color", "scheduled_days", "reminder_time")


def error(code, message, status, fields=None):
    body = {"code": code, "message": message}
    if fields:
        body["fields"] = fields
    return jsonify(error=body), status


def clock():
    now = current_app.config["CLOCK"]()
    return now.astimezone(ZONE).date(), now.astimezone(UTC).isoformat()


def habit_by_id(db, habit_id):
    if not 1 <= habit_id <= 2**63 - 1:
        return None
    return db.execute("SELECT * FROM habits WHERE id = ?", (habit_id,)).fetchone()


def not_found():
    return error("not_found", "Hábito não encontrado.", 404)


def validate(payload, *, existing=None):
    if not isinstance(payload, dict):
        return None, {"body": "Envie um objeto JSON."}
    allowed = EDIT_FIELDS if existing else FIELDS
    errors = {key: "Campo não permitido." for key in payload.keys() - set(allowed)}
    values = dict(existing) if existing else {
        "description": "", "icon": "spark", "color": "violet", "scheduled_days": [],
        "reminder_time": None, "daily_target": 1, "unit": "vez",
    }
    if existing:
        values['scheduled_days'] = json.loads(values['scheduled_days'])
    values.update({key: value.strip() if isinstance(value, str) else value
                   for key, value in payload.items() if key in allowed})
    for field, limit in (("name", 80), ("description", 280)):
        value = values.get(field)
        if not isinstance(value, str) or len(value) > limit or (field == "name" and not value):
            errors[field] = f"Informe um texto de {1 if field == 'name' else 0} a {limit} caracteres."
    if values.get("color") not in COLORS:
        errors["color"] = "Escolha uma cor disponível."
    if values.get("icon") not in ICONS:
        errors["icon"] = "Escolha um ícone disponível."
    target = values.get("weekly_target")
    if type(target) is not int or not 1 <= target <= 7:
        errors["weekly_target"] = "Informe um inteiro de 1 a 7."
    days = values.get('scheduled_days')
    if not isinstance(days, list) or any(type(day) is not int or not 1 <= day <= 7 for day in days) or len(days) != len(set(days)):
        errors['scheduled_days'] = 'Escolha dias distintos de segunda (1) a domingo (7).'
    elif days and type(target) is int and len(days) < target:
        errors['scheduled_days'] = 'Escolha pelo menos tantos dias quanto a meta semanal.'
    reminder = values.get('reminder_time')
    if reminder is not None and (not isinstance(reminder, str) or not re.fullmatch(r'(?:[01]\d|2[0-3]):[0-5]\d', reminder)):
        errors['reminder_time'] = 'Informe o horário no formato HH:mm.'
    daily = values.get('daily_target')
    if type(daily) is not int or not 1 <= daily <= 1000000:
        errors['daily_target'] = 'Informe uma meta diária inteira de 1 a 1000000.'
    unit = values.get('unit')
    if not isinstance(unit, str) or not 1 <= len(unit) <= 24:
        errors['unit'] = 'Informe uma unidade de 1 a 24 caracteres.'
    return values, errors


def persisted_values(values, fields):
    return [json.dumps(values[field]) if field == 'scheduled_days' else values[field] for field in fields]


@api.get("/health")
def health():
    connection().execute("SELECT 1 FROM habits LIMIT 1")
    return jsonify(status="ok")


@api.get("/profile")
def profile():
    avatar = connection().execute('SELECT avatar FROM profile WHERE id=1').fetchone()['avatar']
    return jsonify(display_name="Explorador", timezone=ZONE.key, avatar=avatar)


@api.patch('/profile')
def edit_profile():
    payload = request.get_json()
    if not isinstance(payload, dict) or set(payload) != {'avatar'} or payload.get('avatar') not in ('compass', 'leaf', 'flame'):
        return error('validation_error', 'Escolha um avatar disponível.', 422)
    db = connection()
    with transaction(db, write=True):
        db.execute('UPDATE profile SET avatar=? WHERE id=1', (payload['avatar'],))
    return profile()


@api.get("/habits")
def list_habits():
    status = request.args.get("status", "active")
    filters = {"active": "WHERE archived_at IS NULL", "archived": "WHERE archived_at IS NOT NULL", "all": ""}
    if status not in filters:
        return error("validation_error", "Filtro de status inválido.", 422)
    db = connection()
    today, _ = clock()
    with transaction(db):
        rows = db.execute(f"SELECT * FROM habits {filters[status]} ORDER BY id DESC").fetchall()
        result = [habit_summary(db, row, today) for row in rows]
    return jsonify(result)


@api.post("/habits")
def create_habit():
    payload = request.get_json()
    values, errors = validate(payload)
    if errors:
        return error("validation_error", "Revise os campos informados.", 422, errors)
    db = connection()
    with transaction(db, write=True):
        today, now = clock()
        result = db.execute(
            """INSERT INTO habits (name, description, icon, color, weekly_target, scheduled_days, reminder_time, daily_target, unit, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""", (*persisted_values(values, FIELDS), now),
        )
        habit_id = result.lastrowid
        body = habit_summary(db, habit_by_id(db, habit_id), today)
    return jsonify(body), 201, {"Location": url_for("api.get_habit", habit_id=habit_id)}


@api.get("/habits/<int:habit_id>")
def get_habit(habit_id):
    db = connection()
    today, _ = clock()
    with transaction(db):
        habit = habit_by_id(db, habit_id)
        return jsonify(habit_summary(db, habit, today)) if habit else not_found()


@api.patch("/habits/<int:habit_id>")
def edit_habit(habit_id):
    payload = request.get_json()
    db = connection()
    with transaction(db, write=True):
        habit = habit_by_id(db, habit_id)
        if not habit:
            return not_found()
        values, errors = validate(payload, existing=habit)
        if errors:
            return error("validation_error", "Revise os campos informados.", 422, errors)
        db.execute(
            "UPDATE habits SET name=?, description=?, icon=?, color=?, scheduled_days=?, reminder_time=? WHERE id=?",
            (*persisted_values(values, EDIT_FIELDS), habit_id),
        )
        today, _ = clock()
        return jsonify(habit_summary(db, habit_by_id(db, habit_id), today))


@api.post("/habits/<int:habit_id>/archive")
def archive_habit(habit_id):
    db = connection()
    with transaction(db, write=True):
        if not habit_by_id(db, habit_id):
            return not_found()
        today, now = clock()
        db.execute("UPDATE habits SET archived_at=COALESCE(archived_at, ?) WHERE id=?", (now, habit_id))
        return jsonify(habit_summary(db, habit_by_id(db, habit_id), today))


@api.put("/habits/<int:habit_id>/checkins/today")
@api.delete("/habits/<int:habit_id>/checkins/today")
def checkin_today(habit_id):
    db = connection()
    with transaction(db, write=True):
        today, now = clock()
        habit = habit_by_id(db, habit_id)
        if not habit:
            return not_found()
        if habit["archived_at"]:
            return error("habit_archived", "Este hábito foi arquivado.", 409)
        expected_day = request.headers.get("X-Habit-Date")
        if expected_day is not None and expected_day != today.isoformat():
            return error("day_changed", "O dia mudou. Atualize a lista antes de concluir.", 409)
        quantity = 0 if request.method == 'DELETE' else habit['daily_target']
        if request.method == 'PUT' and request.content_length:
            payload = request.get_json()
            if not isinstance(payload, dict) or set(payload) != {'quantity'} or type(payload.get('quantity')) is not int or not 0 <= payload['quantity'] <= 1000000000:
                return error('validation_error', 'Informe uma quantidade inteira entre 0 e 1000000000.', 422)
            quantity = payload['quantity']
        outcome = set_today_quantity(db, habit, today, now, quantity)
    return jsonify(outcome), 201 if outcome["created"] else 200


@api.post("/habits/<int:habit_id>/restore")
def restore_habit(habit_id):
    db = connection()
    with transaction(db, write=True):
        if not habit_by_id(db, habit_id):
            return not_found()
        db.execute("UPDATE habits SET archived_at=NULL WHERE id=?", (habit_id,))
        today, _ = clock()
        return jsonify(habit_summary(db, habit_by_id(db, habit_id), today))


@api.delete("/habits/<int:habit_id>")
def delete_habit(habit_id):
    db = connection()
    with transaction(db, write=True):
        habit = habit_by_id(db, habit_id)
        if not habit:
            return not_found()
        if habit["archived_at"] is None:
            return error("habit_active", "Arquive o hábito antes de excluir permanentemente.", 409)
        # Every child belongs exclusively to this habit. Removing its reward
        # events also removes its contribution to the score and level.
        for table in ("daily_progress", "checkins", "reward_events", "achievements"):
            db.execute(f"DELETE FROM {table} WHERE habit_id=?", (habit_id,))
        db.execute("DELETE FROM habits WHERE id=?", (habit_id,))
    return jsonify(deleted=True, id=habit_id)


@api.get("/habits/<int:habit_id>/checkins")
def history(habit_id):
    today, _ = clock()
    start = request.args.get("from", (today - timedelta(days=29)).isoformat())
    end = request.args.get("to", today.isoformat())
    try:
        start_day, end_day = date.fromisoformat(start), date.fromisoformat(end)
        if start_day.isoformat() != start or end_day.isoformat() != end or not 0 <= (end_day - start_day).days < 366:
            raise ValueError
    except ValueError:
        return error("validation_error", "Informe um intervalo ISO de até 366 dias.", 422)
    db = connection()
    if not habit_by_id(db, habit_id):
        return not_found()
    rows = db.execute(
        "SELECT * FROM checkins WHERE habit_id=? AND local_date BETWEEN ? AND ? ORDER BY local_date DESC",
        (habit_id, start, end),
    )
    return jsonify([dict(row) for row in rows])


@api.get("/dashboard")
def dashboard():
    db = connection()
    today, _ = clock()
    with transaction(db):
        habits = db.execute("SELECT * FROM habits WHERE archived_at IS NULL ORDER BY id DESC")
        return jsonify(
            local_date=today.isoformat(), week_start=week_start(today).isoformat(),
            habits=[habit_summary(db, habit, today) for habit in habits],
            achievements=badges(db), **score(db),
            weekly_summary=weekly_summary(db, today),
            avatar=db.execute('SELECT avatar FROM profile WHERE id=1').fetchone()['avatar'],
        )


@api.get("/achievements")
def achievements():
    db = connection()
    with transaction(db):
        return jsonify(badges(db))
