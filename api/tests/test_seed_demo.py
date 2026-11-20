import sqlite3
from datetime import date

import pytest

from seed_demo import seed


def test_demo_is_separate_persistent_and_never_overwrites(tmp_path):
    database = tmp_path / "demo.sqlite3"
    seed(database, today=date(2026, 11, 19))
    with sqlite3.connect(database) as db:
        assert db.execute("SELECT COUNT(*) FROM habits").fetchone()[0] == 3
        assert db.execute("SELECT COUNT(*) FROM habits WHERE archived_at IS NOT NULL").fetchone()[0] == 1
        assert db.execute("SELECT COUNT(DISTINCT local_date) FROM checkins").fetchone()[0] >= 30
        assert db.execute("SELECT COUNT(*) FROM achievements WHERE code='streak_30'").fetchone()[0] == 1
    before = database.read_bytes()
    with pytest.raises(ValueError, match="já existe"):
        seed(database)
    assert database.read_bytes() == before
