import sqlite3
from contextlib import contextmanager
from pathlib import Path

from flask import current_app, g

MIGRATIONS = Path(__file__).resolve().parents[1] / "migrations"


def connection():
    if "db" not in g:
        db = sqlite3.connect(current_app.config["DATABASE"], isolation_level=None)
        db.row_factory = sqlite3.Row
        db.execute("PRAGMA foreign_keys = ON")
        g.db = db
    return g.db


def close(_error):
    if db := g.pop("db", None):
        db.close()


@contextmanager
def transaction(db, *, write=False):
    db.execute("BEGIN IMMEDIATE" if write else "BEGIN")
    try:
        yield
        db.commit()
    except BaseException:
        db.rollback()
        raise


def migrate():
    db = connection()
    migrations = sorted(MIGRATIONS.glob("*.sql"))
    with transaction(db, write=True):
        version = db.execute("PRAGMA user_version").fetchone()[0]
        if version > len(migrations):
            raise RuntimeError("O banco requer uma versão mais recente da API.")
        for index, path in enumerate(migrations[version:], start=version + 1):
            for statement in path.read_text(encoding="utf-8").split(";"):
                if statement.strip():
                    db.execute(statement)
            db.execute(f"PRAGMA user_version = {index}")
