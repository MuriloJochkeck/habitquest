"""Observable routine, reward correction and migration contracts."""
import sqlite3
from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime, timedelta
from pathlib import Path

import pytest

from app import create_app


@pytest.fixture
def routine(tmp_path):
    now = [datetime(2026, 11, 16, 15, tzinfo=UTC)]
    config = {'TESTING': True, 'DATABASE': tmp_path / 'routine.sqlite3', 'CLOCK': lambda: now[0]}
    app = create_app(config)
    return app, app.test_client(), now, config


def create(client, **fields):
    response = client.post('/api/v1/habits', json={'name': 'Leitura', 'weekly_target': 1, **fields})
    assert response.status_code == 201
    return response.headers['Location']


def test_quantity_progress_persists_and_only_completion_rewards(routine):
    app, client, _, config = routine
    url = create(client, daily_target=20, unit='minutos')
    endpoint = url + '/checkins/today'
    for quantity in (5, 15, 15):
        response = client.put(endpoint, json={'quantity': quantity})
        assert response.status_code == 200
        assert response.json['awarded_xp'] == 0
        assert response.json['completed_today'] is False
    with create_app(config).test_client() as reopened:
        assert reopened.get(url).json['today_quantity'] == 15
        assert reopened.get(url + '/checkins').json == []
    assert client.put(endpoint, json={'quantity': 20}).json['awarded_xp'] == 60
    assert client.put(endpoint, json={'quantity': 25}).json['awarded_xp'] == 0
    assert client.get(url).json['today_quantity'] == 25
    assert client.put(endpoint, json={'quantity': 19}).json['awarded_xp'] == -60
    assert client.get('/api/v1/dashboard').json['total_xp'] == 0
    assert all(b['unlocked_at'] is None for b in client.get('/api/v1/achievements').json)
    assert client.put(endpoint).json['awarded_xp'] == 60
    assert client.get(url).json['today_quantity'] == 20


def test_undo_is_idempotent_and_recalculates_weekly_bonus(routine):
    _, client, now, _ = routine
    url = create(client, weekly_target=2)
    endpoint = url + '/checkins/today'
    assert client.put(endpoint).json['awarded_xp'] == 10
    now[0] += timedelta(days=1)
    assert client.put(endpoint).json['awarded_xp'] == 60
    assert client.delete(endpoint).json['awarded_xp'] == -60
    assert client.delete(endpoint).json['awarded_xp'] == 0
    habit = client.get(url).json
    assert habit['weekly_count'] == 1
    assert habit['today_quantity'] == 0
    assert habit['completed_today'] is False
    badges = {badge['code']: badge['unlocked_at'] for badge in client.get('/api/v1/achievements').json}
    assert badges['first_checkin'] is not None
    assert badges['first_weekly_goal'] is None
    assert client.get('/api/v1/dashboard').json['total_xp'] == 10
    assert client.put(endpoint).json['awarded_xp'] == 60
    now[0] += timedelta(days=1)
    assert client.put(endpoint).json['awarded_xp'] == 10
    assert client.delete(endpoint).json['awarded_xp'] == -10
    assert client.get('/api/v1/dashboard').json['total_xp'] == 70
    stale = client.delete(endpoint, headers={'X-Habit-Date': '2026-11-16'})
    assert stale.status_code == 409
    assert stale.json['error']['code'] == 'day_changed'


def test_undo_revokes_streak_badge_but_keeps_previous_earned_badges(routine):
    _, client, now, _ = routine
    endpoint = create(client) + '/checkins/today'
    for day in range(7):
        client.put(endpoint)
        if day < 6:
            now[0] += timedelta(days=1)
    badges = client.get('/api/v1/achievements').json
    assert next(b for b in badges if b['code'] == 'streak_7')['unlocked_at'] is not None
    client.delete(endpoint)
    badges = client.get('/api/v1/achievements').json
    assert next(b for b in badges if b['code'] == 'streak_7')['unlocked_at'] is None
    assert next(b for b in badges if b['code'] == 'first_weekly_goal')['unlocked_at'] is not None
    client.put(endpoint)
    now[0] += timedelta(days=2)
    client.put(endpoint)
    client.delete(endpoint)
    badges = client.get('/api/v1/achievements').json
    assert next(b for b in badges if b['code'] == 'streak_7')['unlocked_at'] is not None


def test_scheduling_reminder_edit_and_avatar_persistence(routine):
    _, client, now, config = routine
    url = create(client, weekly_target=3, scheduled_days=[1, 3, 5], reminder_time='21:30')
    habit = client.get(url).json
    assert habit['scheduled_days'] == [1, 3, 5]
    assert habit['scheduled_today'] is True
    now[0] += timedelta(days=1)
    assert client.get(url).json['scheduled_today'] is False
    assert client.put(url + '/checkins/today').status_code == 201  # Extra-day completion allowed.
    assert client.patch(url, json={'reminder_time': None, 'scheduled_days': []}).status_code == 200
    assert client.get(url).json['scheduled_today'] is True
    assert client.patch('/api/v1/profile', json={'avatar': 'leaf'}).json['avatar'] == 'leaf'
    with create_app(config).test_client() as reopened:
        assert reopened.get(url).json['reminder_time'] is None
        assert reopened.get('/api/v1/profile').json['avatar'] == 'leaf'
        assert reopened.get('/api/v1/dashboard').json['avatar'] == 'leaf'
    client.post(url + '/archive')
    assert client.delete(url + '/checkins/today').status_code == 409


@pytest.mark.parametrize('fields', [
    {'scheduled_days': [0]}, {'scheduled_days': [1, 1]}, {'scheduled_days': [True]},
    {'scheduled_days': [[1]]}, {'scheduled_days': '1'}, {'scheduled_days': [1]},
    {'reminder_time': '24:00'}, {'reminder_time': '9:30'}, {'reminder_time': 930},
    {'daily_target': 0}, {'daily_target': True}, {'daily_target': 2.5},
    {'daily_target': 1000001}, {'unit': ''}, {'unit': 2}, {'unit': 'x' * 25},
])
def test_routine_invalid_creation_fields(routine, fields):
    _, client, _, _ = routine
    response = client.post('/api/v1/habits', json={'name': 'Ler', 'weekly_target': 3, **fields})
    assert response.status_code == 422
    assert client.get('/api/v1/habits').json == []


@pytest.mark.parametrize('body', [
    {'quantity': True}, {'quantity': -1}, {'quantity': 0.5}, {'quantity': 1000000001},
    {'quantity': '2'}, {'quantity': []}, {'quantity': 2, 'xp': 999}, {}, [],
])
def test_invalid_quantity_cannot_change_completion(routine, body):
    _, client, _, _ = routine
    url = create(client)
    assert client.put(url + '/checkins/today', json=body).status_code == 422
    assert client.get(url).json['completed_today'] is False
    assert client.get('/api/v1/dashboard').json['total_xp'] == 0


def test_immutable_quantity_contract_and_invalid_profile(routine):
    _, client, _, _ = routine
    url = create(client)
    assert client.patch(url, json={'daily_target': 20}).status_code == 422
    assert client.patch(url, json={'unit': 'minutos'}).status_code == 422
    for fields in ({'avatar': 'unknown'}, {'avatar': []}, {}, {'avatar': 'leaf', 'xp': 99}):
        assert client.patch('/api/v1/profile', json=fields).status_code == 422


def test_weekly_summary_compares_same_elapsed_days(routine):
    _, client, now, _ = routine
    url = create(client)
    client.put(url + '/checkins/today')
    now[0] += timedelta(days=1)
    client.put(url + '/checkins/today')
    now[0] += timedelta(days=3)  # Friday last week is excluded in Tuesday-to-Tuesday comparison.
    client.put(url + '/checkins/today')
    now[0] = datetime(2026, 11, 24, 15, tzinfo=UTC)
    client.put(url + '/checkins/today')
    summary = client.get('/api/v1/dashboard').json['weekly_summary']
    assert summary == {
        'current_count': 1, 'previous_count': 2, 'delta': -1,
        'current_start': '2026-11-23', 'current_end': '2026-11-24',
        'previous_start': '2026-11-16', 'previous_end': '2026-11-17',
        'best_habit_name': 'Leitura',
    }


def test_concurrent_quantity_updates_award_only_once(routine):
    app, client, _, _ = routine
    endpoint = create(client, daily_target=20) + '/checkins/today'

    def complete(_):
        with app.test_client() as concurrent:
            return concurrent.put(endpoint, json={'quantity': 20}).json['awarded_xp']

    with ThreadPoolExecutor(max_workers=4) as pool:
        assert sorted(pool.map(complete, range(4))) == [0, 0, 0, 60]
    assert client.get('/api/v1/dashboard').json['total_xp'] == 60


def test_migration_preserves_v1_history_and_rewards(tmp_path):
    database = tmp_path / 'legacy.sqlite3'
    initial = Path(__file__).parents[1] / 'migrations' / '001_initial.sql'
    with sqlite3.connect(database) as db:
        db.executescript(initial.read_text(encoding='utf-8'))
        db.execute('PRAGMA user_version=1')
        db.execute("INSERT INTO habits VALUES (1, 'Legado', '', 'book', 'violet', 1, '2026-11-16T15:00:00+00:00', NULL)")
        db.execute("INSERT INTO checkins VALUES (1, '2026-11-16', '2026-11-16T15:00:00+00:00')")
        db.execute("INSERT INTO reward_events VALUES (1, 'daily', '2026-11-16', 10, '2026-11-16T15:00:00+00:00')")
    config = {'TESTING': True, 'DATABASE': database, 'CLOCK': lambda: datetime(2026, 11, 16, 15, tzinfo=UTC)}
    for _ in range(2):
        client = create_app(config).test_client()
        habit = client.get('/api/v1/habits/1').json
        assert habit['name'] == 'Legado'
        assert habit['today_quantity'] == 1
        assert habit['scheduled_days'] == []
        assert habit['reminder_time'] is None
        assert habit['unit'] == 'vez'
        assert habit['completed_today'] is True
        assert client.get('/api/v1/dashboard').json['total_xp'] == 10
    with sqlite3.connect(database) as db:
        assert db.execute('PRAGMA user_version').fetchone()[0] == 2


def test_delete_cors_preflight(routine):
    _, client, _, _ = routine
    response = client.options('/api/v1/habits/1/checkins/today', headers={
        'Origin': 'http://localhost:7357', 'Access-Control-Request-Method': 'DELETE',
    })
    assert 'DELETE' in response.headers['Access-Control-Allow-Methods']
