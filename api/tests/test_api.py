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
