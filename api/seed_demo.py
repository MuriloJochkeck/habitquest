"""Cria um banco novo com dados fictícios para a apresentação local."""

import argparse
from datetime import datetime, timedelta
from pathlib import Path

from app import create_app
from app.progress import ZONE, week_start


def seed(database, *, today=None):
    database = Path(database).resolve()
    if database.exists():
        raise ValueError("O arquivo já existe. Escolha outro caminho para preservar os dados.")
    today = today or datetime.now(ZONE).date()
    first = week_start(today) - timedelta(weeks=5)
    clock = [datetime.combine(first, datetime.min.time(), ZONE)]
    app = create_app({"TESTING": True, "DATABASE": str(database), "CLOCK": lambda: clock[0]})
    with app.test_client() as client:
        habits = []
        for name, target, icon, color, weekdays in (
            ("Demo · Ler por 20 minutos", 5, "book", "violet", {0, 1, 2, 3, 4}),
            ("Demo · Fazer exercício", 3, "fitness", "mint", {0, 2, 4}),
            ("Demo · Meditar", 7, "mind", "blue", set(range(7))),
        ):
            response = client.post("/api/v1/habits", json={
                "name": name, "description": "Dados fictícios para demonstração.",
                "weekly_target": target, "icon": icon, "color": color,
            })
            if response.status_code != 201:
                raise RuntimeError(f"Falha ao criar hábito: {response.status_code}")
            habits.append((response.headers["Location"], weekdays))
        day = first
        while day <= today:
            clock[0] = datetime.combine(day, datetime.min.time(), ZONE)
            for index, (url, weekdays) in enumerate(habits):
                # Inclui uma semana sem leitura para demonstrar aderência real.
                if day.weekday() in weekdays and not (index == 0 and 7 <= (day - first).days < 14):
                    response = client.put(url + "/checkins/today")
                    if response.status_code != 201:
                        raise RuntimeError(f"Falha ao registrar realização: {response.status_code}")
            day += timedelta(days=1)
        # Preserva um exemplo de histórico arquivado, incluindo XP e conquistas.
        response = client.post(habits[1][0] + "/archive")
        if response.status_code != 200:
            raise RuntimeError("Falha ao arquivar o hábito de demonstração.")
    return database


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--database", required=True, help="Caminho de um arquivo SQLite que ainda não existe.")
    args = parser.parse_args()
    try:
        result = seed(args.database)
    except ValueError as error:
        parser.exit(2, f"{error}\n")
    print(f"Banco de demonstração criado: {result}")
