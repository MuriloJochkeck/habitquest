"""Contract checks for the JSON Schema subset used by our OpenAPI document.

This deliberately does not claim to replace a full OpenAPI/JSON Schema validator.
It catches route drift and validates real response shapes without a new dependency.
"""
import json
import re
from datetime import UTC, date, datetime
from pathlib import Path

from app import create_app


SPEC = json.loads((Path(__file__).parents[2] / "docs/openapi.json").read_text(encoding="utf-8"))


def resolve(reference):
    assert reference.startswith("#/")
    value = SPEC
    for part in reference[2:].split("/"):
        value = value[part.replace("~1", "/").replace("~0", "~")]
    return value


def validate(value, schema):
    if "$ref" in schema:
        return validate(value, resolve(schema["$ref"]))
    kind = schema["type"]
    kinds = kind if isinstance(kind, list) else [kind]
    actual = ("null" if value is None else "boolean" if type(value) is bool else
              "integer" if type(value) is int else "number" if type(value) is float else
              "string" if isinstance(value, str) else "array" if isinstance(value, list) else
              "object" if isinstance(value, dict) else "unknown")
    assert actual in kinds or (actual == "integer" and "number" in kinds)
    if "const" in schema:
        assert value == schema["const"]
    if "enum" in schema:
        assert value in schema["enum"]
    if value is None:
        return
    if actual == "object":
        properties = schema.get("properties", {})
        assert set(schema.get("required", [])) <= value.keys()
        if schema.get("additionalProperties") is False:
            assert value.keys() <= properties.keys()
        for key, item in value.items():
            target = properties.get(key, schema.get("additionalProperties"))
            if isinstance(target, dict):
                validate(item, target)
    elif actual == "array":
        assert len(value) <= schema.get("maxItems", float("inf"))
        for item in value:
            validate(item, schema["items"])
    elif actual == "string":
        assert schema.get("minLength", 0) <= len(value) <= schema.get("maxLength", float("inf"))
        if "pattern" in schema:
            assert re.fullmatch(schema["pattern"], value)
        if schema.get("format") == "date":
            assert date.fromisoformat(value).isoformat() == value
        if schema.get("format") == "date-time":
            assert datetime.fromisoformat(value).tzinfo is not None
    elif actual in ("integer", "number"):
        assert schema.get("minimum", float("-inf")) <= value <= schema.get("maximum", float("inf"))


def test_document_references_and_flask_routes(tmp_path):
    def walk(value):
        if isinstance(value, dict):
            if "$ref" in value:
                resolve(value["$ref"])
            for child in value.values():
                walk(child)
        elif isinstance(value, list):
            for child in value:
                walk(child)

    walk(SPEC)
    app = create_app({"DATABASE": tmp_path / "contract.sqlite3", "TESTING": True})
    actual = {
        (re.sub(r"<int:(\w+)>", r"{\1}", rule.rule.removeprefix("/api/v1")), method.lower())
        for rule in app.url_map.iter_rules() if rule.rule.startswith("/api/v1/")
        for method in rule.methods - {"HEAD", "OPTIONS"}
    }
    documented = {(path, method) for path, item in SPEC["paths"].items()
                  for method in item if method != "parameters"}
    assert actual == documented


def test_real_responses_match_documented_schemas(tmp_path):
    now = [datetime(2026, 11, 16, 15, tzinfo=UTC)]
    app = create_app({"DATABASE": tmp_path / "responses.sqlite3", "TESTING": True, "CLOCK": lambda: now[0]})
    client = app.test_client()

    def check(method, path, template=None, expected=200, **kwargs):
        response = client.open("/api/v1" + path, method=method, **kwargs)
        assert response.status_code == expected
        operation = SPEC["paths"][template or path][method.lower()]
        schema = operation["responses"][str(expected)]["content"]["application/json"]["schema"]
        validate(response.json, schema)
        return response

    check("GET", "/health")
    check("GET", "/profile")
    check("GET", "/habits")
    payload = {"name": "Ler", "weekly_target": 1}
    validate(payload, SPEC["components"]["schemas"]["HabitCreate"])
    created = check("POST", "/habits", expected=201, json=payload)
    assert created.headers["Location"] == "/api/v1/habits/1"
    check("GET", "/habits/1", "/habits/{habit_id}")
    check("PATCH", "/habits/1", "/habits/{habit_id}", json={"description": "Antes de dormir"})
    check("PUT", "/habits/1/checkins/today", "/habits/{habit_id}/checkins/today", expected=201)
    check("PUT", "/habits/1/checkins/today", "/habits/{habit_id}/checkins/today")
    stale = check("PUT", "/habits/1/checkins/today", "/habits/{habit_id}/checkins/today",
                  expected=409, headers={"X-Habit-Date": "2026-11-15"})
    assert stale.json["error"]["code"] == "day_changed"
    check("GET", "/habits/1/checkins", "/habits/{habit_id}/checkins")
    check("GET", "/dashboard")
    check("GET", "/achievements")
    check("POST", "/habits/1/archive", "/habits/{habit_id}/archive")
    check("PUT", "/habits/1/checkins/today", "/habits/{habit_id}/checkins/today", expected=409)
    check("GET", "/habits/999", "/habits/{habit_id}", expected=404)
    check("POST", "/habits", expected=422, json={"name": "", "weekly_target": 0})
    check("POST", "/habits", expected=400, data="{", content_type="application/json")
    check("POST", "/habits", expected=415, data="{}")
    check("POST", "/habits", expected=413, data="x" * 16385, content_type="application/json")
    app.config["DATABASE"] = tmp_path
    check("GET", "/health", expected=503)
