from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime, timedelta

import pytest

from app import create_app
from app import progress


@pytest.fixture
def setup(tmp_path):
    now = [datetime(2026, 11, 16, 15, tzinfo=UTC)]
    config = {"TESTING": True, "DATABASE": tmp_path / "test.sqlite3", "CLOCK": lambda: now[0]}
    app = create_app(config)
    return app, now, config


def create(client, target=1):
    response = client.post("/api/v1/habits", json={"name": " Ler ", "weekly_target": target})
    assert response.status_code == 201
    assert response.json["name"] == "Ler"
    return response.headers["Location"]


def test_persistence_and_archive(setup):
    app, _, config = setup
    with app.test_client() as client:
        url = create(client)
        assert client.patch(url, json={"name": "Ler 20 min"}).status_code == 200
        assert client.put(url + "/checkins/today").json["awarded_xp"] == 60
        assert client.post(url + "/archive").status_code == 200
        assert client.put(url + "/checkins/today").status_code == 409
    with create_app(config).test_client() as client:
        assert client.get(url).json["name"] == "Ler 20 min"
        assert len(client.get(url + "/checkins").json) == 1
        dashboard = client.get("/api/v1/dashboard").json
        assert dashboard["habits"] == []
        assert dashboard["total_xp"] == 60
        assert len([badge for badge in dashboard["achievements"] if badge["unlocked_at"]]) == 2


def test_concurrent_requests_reward_once(setup):
    app, _, _ = setup
    url = create(app.test_client()) + "/checkins/today"

    def submit(_):
        with app.test_client() as client:
            result = client.put(url)
            return result.status_code, result.json["awarded_xp"]

    with ThreadPoolExecutor(max_workers=6) as pool:
        assert sorted(pool.map(submit, range(6))) == [(200, 0)] * 5 + [(201, 60)]


def test_week_boundary_streak_and_stale_date(setup):
    app, now, _ = setup
    with app.test_client() as client:
        url = create(client, 2)
        put = url + "/checkins/today"
        now[0] = datetime(2026, 11, 23, 2, 59, tzinfo=UTC)
        assert client.put(put).json["checkin"]["local_date"] == "2026-11-22"
        now[0] += timedelta(minutes=1)
        assert client.put(put, headers={"X-Habit-Date": "2026-11-22"}).status_code == 409
        assert client.get(url).json["streak"] == 1
        first = client.put(put)
        assert first.json["progress"]["weekly_count"] == 1
        assert first.json["awarded_xp"] == 10
        now[0] += timedelta(days=1)
        assert client.put(put).json["awarded_xp"] == 60
        now[0] += timedelta(days=1)
        assert client.put(put).json["awarded_xp"] == 10
        assert client.get(url).json["streak"] == 4


def test_validation(setup):
    app, _, _ = setup
    client = app.test_client()
    for target in (0, 8, True, "2"):
        assert client.post("/api/v1/habits", json={"name": "  ", "weekly_target": target}).status_code == 422
    assert client.post("/api/v1/habits", json={"name": "Ler", "weekly_target": 1, "xp": 999}).status_code == 422
    url = create(client)
    assert client.patch(url, json={"weekly_target": 3}).status_code == 422
    assert client.get(url + "/checkins?from=2026-01-01&to=2027-01-02").status_code == 422
    assert client.get("/api/v1/health").json == {"status": "ok"}


def test_rollback_if_calculation_fails(setup, monkeypatch):
    app, _, _ = setup
    client = app.test_client()
    url = create(client)

    def fail(_db):
        raise RuntimeError("falha simulada")

    with monkeypatch.context() as patch:
        patch.setattr(progress, "score", fail)
        with pytest.raises(RuntimeError, match="falha simulada"):
            client.put(url + "/checkins/today")
    assert client.get(url + "/checkins").json == []
    assert client.get("/api/v1/dashboard").json["total_xp"] == 0
    assert client.put(url + "/checkins/today").json["awarded_xp"] == 60


def test_weekly_history_adherence_and_archive(setup):
    app, now, _ = setup
    client = app.test_client()
    url = create(client, 2)  # Monday noon: creation week is partial.
    assert client.get(url).json["adherence"] is None
    assert client.get(url).json["weekly_history"] == [{
        "week_start": "2026-11-16", "weekly_count": 0,
        "weekly_target": 2, "complete_week": False,
    }]
    client.put(url + "/checkins/today")
    now[0] += timedelta(weeks=1)
    for _ in range(3):
        client.put(url + "/checkins/today")
        now[0] += timedelta(days=1)
    now[0] = datetime(2026, 12, 7, 15, tzinfo=UTC)
    result = client.get(url).json
    assert result["adherence"] == .5  # One met week and one empty week.
    assert [w["weekly_count"] for w in result["weekly_history"]] == [1, 3, 0, 0]
    assert [w["complete_week"] for w in result["weekly_history"]] == [False, True, True, False]
    client.post(url + "/archive")
    archived = client.get(url).json
    now[0] += timedelta(weeks=12)
    assert client.get(url).json["weekly_history"] == archived["weekly_history"]
    assert client.get(url).json["adherence"] == .5


def test_weekly_history_limit_and_midnight_creation(setup):
    app, now, _ = setup
    now[0] = datetime(2026, 11, 16, 3, tzinfo=UTC)
    client = app.test_client()
    url = create(client)
    client.put(url + "/checkins/today")
    now[0] += timedelta(weeks=1)
    result = client.get(url).json
    assert result["adherence"] == 1
    assert result["weekly_history"][0]["complete_week"] is True
    now[0] += timedelta(weeks=10)
    history = client.get(url).json["weekly_history"]
    assert len(history) == 8
    assert history[-1]["week_start"] == "2027-02-01"
    assert all(w["weekly_count"] == 0 for w in history)


def test_streak_achievements_and_year_boundary(setup):
    app, now, _ = setup
    now[0] = datetime(2026, 12, 28, 15, tzinfo=UTC)
    client = app.test_client()
    url = create(client)
    earned_at_seven = None
    for day in range(30):
        response = client.put(url + "/checkins/today")
        assert response.json["awarded_xp"] == (60 if day % 7 == 0 else 10)
        badges = {b["code"]: b for b in client.get("/api/v1/achievements").json}
        assert all(b["requirement"] for b in badges.values())
        assert bool(badges["streak_7"]["unlocked_at"]) == (day >= 6)
        assert bool(badges["streak_30"]["unlocked_at"]) == (day >= 29)
        if day == 6:
            earned_at_seven = badges["streak_7"]["unlocked_at"]
        if day >= 6:
            assert badges["streak_7"]["unlocked_at"] == earned_at_seven
        assert client.put(url + "/checkins/today").json["awarded_xp"] == 0
        if day < 29:
            now[0] += timedelta(days=1)
    assert client.get(url).json["streak"] == 30
    dashboard = client.get("/api/v1/dashboard").json
    assert dashboard["total_xp"] == 550
    assert dashboard["level"] == 6
    now[0] += timedelta(days=1)
    assert client.get(url).json["streak"] == 30
    now[0] += timedelta(days=1)
    assert client.get(url).json["streak"] == 0


@pytest.mark.parametrize("fields", [
    {"name": ""}, {"name": "x" * 81}, {"name": None},
    {"description": "x" * 281}, {"description": 1},
    {"icon": "unknown"}, {"color": "unknown"},
    {"weekly_target": False}, {"weekly_target": 0}, {"weekly_target": 8},
    {"weekly_target": "2"}, {"weekly_target": 2.5}, {"xp": 5},
])
def test_invalid_fields_are_independently_rejected(setup, fields):
    app, _, _ = setup
    client = app.test_client()
    payload = {"name": "Ler", "weekly_target": 2, **fields}
    assert client.post("/api/v1/habits", json=payload).status_code == 422
    assert client.get("/api/v1/habits").json == []


def test_protocol_errors_and_history_boundaries(setup):
    app, _, _ = setup
    client = app.test_client()
    assert client.post("/api/v1/habits", data="{}").status_code == 415
    malformed = client.post("/api/v1/habits", data="{", content_type="application/json")
    assert malformed.status_code == 400
    assert "error" in malformed.json
    assert client.post("/api/v1/habits", json=[]).status_code == 422
    assert client.get("/api/v1/habits/999").status_code == 404
    assert client.put("/api/v1/habits/999/checkins/today").status_code == 404
    url = create(client)
    client.put(url + "/checkins/today")
    history = client.get(url + "/checkins?from=2026-11-16&to=2026-11-16")
    assert [r["local_date"] for r in history.json] == ["2026-11-16"]
    assert client.get(url + "/checkins?from=2026-11-17&to=2026-11-18").json == []
    for query in ("from=2026-11-18&to=2026-11-16", "from=invalid", "from=2026-02-30"):
        assert client.get(url + "/checkins?" + query).status_code == 422
    assert client.get(url + "/checkins?from=2026-01-01&to=2027-01-01").status_code == 200
    assert client.get(url + "/checkins?from=2026-01-01&to=2027-01-02").status_code == 422


def test_cors_is_limited_to_configured_origin(setup):
    app, _, _ = setup
    client = app.test_client()
    response = client.options("/api/v1/habits/1/checkins/today", headers={
        "Origin": "http://localhost:7357", "Access-Control-Request-Method": "PUT",
        "Access-Control-Request-Headers": "X-Habit-Date",
    })
    assert response.status_code == 200
    assert response.headers["Access-Control-Allow-Origin"] == "http://localhost:7357"
    assert "X-Habit-Date" in response.headers["Access-Control-Allow-Headers"]
    assert "PUT" in response.headers["Access-Control-Allow-Methods"]
    response = client.get("/api/v1/dashboard", headers={"Origin": "https://example.org"})
    assert "Access-Control-Allow-Origin" not in response.headers


def test_database_unavailability_is_reported_as_json(setup, tmp_path):
    app, _, _ = setup
    # A directory cannot be opened as a database; no live database is changed.
    app.config["DATABASE"] = tmp_path
    response = app.test_client().get("/api/v1/health")
    assert response.status_code == 503
    assert response.json["error"]["code"] == "database_unavailable"
