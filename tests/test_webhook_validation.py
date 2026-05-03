"""Tests for webhook endpoint validation."""

import os

import pytest

os.environ["WEBHOOK_API_KEY"] = "test-secret-key"

from fastapi.testclient import TestClient

from src.automation.webhook_app import app


@pytest.fixture
def client():
    return TestClient(app)


def test_health_endpoint(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    data = resp.json()
    assert data["status"] == "ok"


def test_webhook_valid_payload(client):
    payload = {
        "action": "entry", "symbol": "EURUSD", "direction": "long",
        "entry_price": 1.10000, "sl": 1.09950, "tp": 1.10100,
        "quantity": 1.0, "strategy_name": "test_strategy",
        "timestamp": "2024-01-01T10:00:00Z",
    }
    resp = client.post("/webhook", json=payload, headers={"X-API-Key": "test-secret-key"})
    assert resp.status_code == 200


def test_webhook_rejects_missing_api_key(client):
    payload = {
        "action": "entry", "symbol": "EURUSD", "direction": "long",
        "entry_price": 1.10000, "sl": 1.09950, "tp": 1.10100,
        "quantity": 1.0, "strategy_name": "test",
        "timestamp": "2024-01-01T10:00:00Z",
    }
    resp = client.post("/webhook", json=payload)
    assert resp.status_code in (401, 422)  # missing header


def test_webhook_rejects_wrong_api_key(client):
    payload = {
        "action": "entry", "symbol": "EURUSD", "direction": "long",
        "entry_price": 1.1, "sl": 1.09, "tp": 1.11,
        "quantity": 1.0, "strategy_name": "test",
        "timestamp": "2024-01-01T10:00:00Z",
    }
    resp = client.post("/webhook", json=payload, headers={"X-API-Key": "wrong-key"})
    assert resp.status_code in (401, 403)
