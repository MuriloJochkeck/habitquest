"""Archive lifecycle preserves history on restore and removes it on deletion."""
from datetime import UTC, datetime

import pytest

from app import create_app
from app.db import connection


@pytest.fixture
def lifecycle(tmp_path):
    config = {
        'TESTING': True, 'DATABASE': tmp_path / 'lifecycle.sqlite3',
        'CLOCK': lambda: datetime(2026, 11, 20, 15, tzinfo=UTC),
    }
    app = create_app(config)
    return app, app.test_client(), config


def create(client, name='Leitura'):
    response = client.post('/api/v1/habits', json={
        'name': name, 'weekly_target': 1, 'daily_target': 20, 'unit': 'minutos',
        'scheduled_days': [1, 3, 5], 'reminder_time': '20:30',
    })
    assert response.status_code == 201
    return response.headers['Location'], response.json['id']


def snapshot(app, habit_id):
    with app.app_context():
        db = connection()
        return {
            table: [tuple(row) for row in db.execute(
                f'SELECT * FROM {table} WHERE {"id" if table == "habits" else "habit_id"}=?',
                (habit_id,),
            )]
            for table in ('habits', 'daily_progress', 'checkins', 'reward_events', 'achievements')
        }


def test_restore_is_idempotent_and_persists_history_rewards_and_configuration(lifecycle):
    app, client, config = lifecycle
    url, habit_id = create(client)
    assert client.put(url + '/checkins/today').json['awarded_xp'] == 60
    before = snapshot(app, habit_id)
    assert client.post(url + '/archive').status_code == 200
    assert client.get('/api/v1/dashboard').json['habits'] == []
    assert len(client.get('/api/v1/habits?status=archived').json) == 1
    for _ in range(2):
        restored = client.post(url + '/restore')
        assert restored.status_code == 200
        assert restored.json['archived_at'] is None
        assert restored.json['today_quantity'] == 20
        assert restored.json['completed_today'] is True
        assert restored.json['scheduled_days'] == [1, 3, 5]
        assert restored.json['reminder_time'] == '20:30'
    assert snapshot(app, habit_id) == before
    with create_app(config).test_client() as reopened:
        dashboard = reopened.get('/api/v1/dashboard').json
        assert dashboard['total_xp'] == 60
        assert dashboard['habits'][0]['id'] == habit_id
        assert reopened.get('/api/v1/habits?status=archived').json == []
        assert reopened.put(url + '/checkins/today').json['awarded_xp'] == 0


def test_delete_removes_all_owned_data_and_preserves_other_habit(lifecycle):
    app, client, config = lifecycle
    url, habit_id = create(client)
    other_url, other_id = create(client, 'Outro hábito')
    client.put(url + '/checkins/today')
    client.put(other_url + '/checkins/today')
    client.post(url + '/archive')
    other_before = snapshot(app, other_id)
    assert all(snapshot(app, habit_id).values())
    result = client.delete(url)
    assert result.status_code == 200
    assert result.json == {'deleted': True, 'id': habit_id}
    assert all(not rows for rows in snapshot(app, habit_id).values())
    assert snapshot(app, other_id) == other_before
    with app.app_context():
        assert list(connection().execute('PRAGMA foreign_key_check')) == []
    with create_app(config).test_client() as reopened:
        dashboard = reopened.get('/api/v1/dashboard').json
        assert dashboard['total_xp'] == 60
        assert dashboard['level'] == 1
        assert dashboard['weekly_summary']['current_count'] == 1
        assert dashboard['weekly_summary']['best_habit_name'] == 'Outro hábito'
        assert {badge['habit_id'] for badge in dashboard['achievements']} == {other_id}
        assert reopened.get(url).status_code == 404
        assert reopened.get(url + '/checkins').status_code == 404
        assert reopened.get('/api/v1/habits?status=archived').json == []
        assert reopened.delete(url).status_code == 404
        assert reopened.post(url + '/restore').status_code == 404


def test_delete_active_habit_is_rejected_without_data_changes(lifecycle):
    app, client, _ = lifecycle
    url, habit_id = create(client)
    client.put(url + '/checkins/today', json={'quantity': 10})
    before = snapshot(app, habit_id)
    response = client.delete(url)
    assert response.status_code == 409
    assert response.json['error']['code'] == 'habit_active'
    assert snapshot(app, habit_id) == before


def test_delete_rolls_back_child_deletes_if_parent_delete_fails(lifecycle):
    app, client, _ = lifecycle
    url, habit_id = create(client)
    client.put(url + '/checkins/today')
    client.post(url + '/archive')
    before = snapshot(app, habit_id)
    with app.app_context():
        connection().execute('''CREATE TRIGGER reject_delete BEFORE DELETE ON habits
            BEGIN SELECT RAISE(ABORT, 'forced test failure'); END''')
    assert client.delete(url).status_code == 503
    assert snapshot(app, habit_id) == before


@pytest.mark.parametrize('habit_id', [999, 9223372036854775808])
def test_lifecycle_unknown_habit_is_not_found(lifecycle, habit_id):
    _, client, _ = lifecycle
    assert client.delete(f'/api/v1/habits/{habit_id}').status_code == 404
    assert client.post(f'/api/v1/habits/{habit_id}/restore').status_code == 404
