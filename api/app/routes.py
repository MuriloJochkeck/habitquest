from datetime import UTC, date, timedelta

from flask import Blueprint, current_app, jsonify, request, url_for

from .db import connection, transaction
from .progress import COLORS, ICONS, ZONE, badges, habit_summary, record_checkin, score, week_start

api = Blueprint("api", __name__)
FIELDS = ("name", "description", "icon", "color", "weekly_target")


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
    allowed = FIELDS[:-1] if existing else FIELDS
    errors = {key: "Campo não permitido." for key in payload.keys() - set(allowed)}
    values = dict(existing) if existing else {"description": "", "icon": "spark", "color": "violet"}
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
    return values, errors


@api.get("/health")
def health():
    connection().execute("SELECT 1 FROM habits LIMIT 1")
    return jsonify(status="ok")


@api.get("/profile")
def profile():
    return jsonify(display_name="Explorador", timezone=ZONE.key)


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
            """INSERT INTO habits (name, description, icon, color, weekly_target, created_at)
            VALUES (?, ?, ?, ?, ?, ?)""", (*[values[field] for field in FIELDS], now),
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
            "UPDATE habits SET name=?, description=?, icon=?, color=? WHERE id=?",
            (*[values[field] for field in FIELDS[:-1]], habit_id),
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
        outcome = record_checkin(db, habit, today, now)
    return jsonify(outcome), 201 if outcome["created"] else 200


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
        )


@api.get("/achievements")
def achievements():
    db = connection()
    with transaction(db):
        return jsonify(badges(db))
