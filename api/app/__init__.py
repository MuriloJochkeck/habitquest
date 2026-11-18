import os
import sqlite3
from datetime import UTC, datetime
from pathlib import Path

from flask import Flask, jsonify, request
from werkzeug.exceptions import HTTPException

from . import db
from .routes import api


def create_app(config=None):
    app = Flask(__name__)
    app.config.from_mapping(
        DATABASE=os.environ.get("HABITQUEST_DB", str(Path(app.instance_path) / "habitquest.sqlite3")),
        CLOCK=lambda: datetime.now(UTC),
        WEB_ORIGIN=os.environ.get("HABITQUEST_WEB_ORIGIN", "http://localhost:7357"),
        MAX_CONTENT_LENGTH=16_384,
    )
    if config:
        app.config.update(config)
    Path(app.config["DATABASE"]).parent.mkdir(parents=True, exist_ok=True)
    app.json.ensure_ascii = False
    app.teardown_appcontext(db.close)
    app.register_blueprint(api, url_prefix="/api/v1")

    @app.after_request
    def response_headers(response):
        response.headers["Cache-Control"] = "no-store"
        response.vary.add("Origin")
        if request.headers.get("Origin") == app.config["WEB_ORIGIN"]:
            response.headers["Access-Control-Allow-Origin"] = app.config["WEB_ORIGIN"]
            response.headers["Access-Control-Allow-Methods"] = "GET, POST, PATCH, PUT, OPTIONS"
            response.headers["Access-Control-Allow-Headers"] = "Content-Type, X-Habit-Date"
        return response

    @app.errorhandler(HTTPException)
    def http_error(error):
        messages = {
            400: "Requisição inválida.", 404: "Recurso não encontrado.",
            405: "Método não permitido.", 413: "Requisição muito grande.",
            415: "Envie o corpo como application/json.",
        }
        response = error.get_response()
        response.set_data(app.json.dumps({"error": {
            "code": error.name.lower().replace(" ", "_"),
            "message": messages.get(error.code, "Não foi possível processar a requisição."),
        }}))
        response.content_type = "application/json"
        return response

    @app.errorhandler(sqlite3.Error)
    def database_error(error):
        app.logger.error("Erro no SQLite", exc_info=error)
        return jsonify(error={"code": "database_unavailable", "message": "Banco indisponível."}), 503

    with app.app_context():
        db.migrate()
    return app
