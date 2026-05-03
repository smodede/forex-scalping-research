"""FastAPI webhook application for receiving trading signals."""
from __future__ import annotations

import logging
import os
from datetime import datetime, timezone
from typing import Any

from fastapi import FastAPI, Header, HTTPException

from src.automation.paper_broker import PaperBroker
from src.export.payloads import AlertPayload

logger = logging.getLogger(__name__)

app = FastAPI(title="Trading Webhook", version="0.1.0")

_signal_log: list[dict[str, Any]] = []
_paper_broker = PaperBroker()


class HealthResponse:
    """Simple health-check response."""

    def __init__(self, status: str = "ok") -> None:
        self.status = status


def _verify_api_key(api_key: str | None) -> None:
    """Validate the provided API key against the environment variable.

    Raises
    ------
    HTTPException
        If the key is missing or does not match ``WEBHOOK_API_KEY``.
    """
    expected = os.environ.get("WEBHOOK_API_KEY", "")
    if not api_key or api_key != expected:
        raise HTTPException(status_code=401, detail="Invalid or missing API key")


def get_signal_log() -> list[dict[str, Any]]:
    """Return the in-memory signal log."""
    return _signal_log


def get_paper_broker() -> PaperBroker:
    """Return the module-level paper broker instance."""
    return _paper_broker


@app.get("/health")
def health() -> dict[str, str]:
    """Return service health status."""
    return {"status": "ok"}


@app.post("/webhook")
def receive_webhook(
    payload: AlertPayload,
    x_api_key: str | None = Header(default=None),
) -> dict[str, Any]:
    """Receive a trading signal via webhook.

    The caller must supply a valid ``X-API-Key`` header.

    Parameters
    ----------
    payload : AlertPayload
        The trading signal.
    x_api_key : str | None
        API key provided in the request header.

    Returns
    -------
    dict[str, Any]
        Acknowledgement with the received payload data.
    """
    _verify_api_key(x_api_key)
    entry = {
        "received_at": datetime.now(timezone.utc).isoformat(),
        "payload": payload.model_dump(),
    }
    _signal_log.append(entry)
    logger.info("Signal received: %s %s %s", payload.action, payload.symbol, payload.direction)
    return {"status": "accepted", "payload": payload.model_dump()}


@app.post("/webhook/paper")
def receive_webhook_paper(
    payload: AlertPayload,
    x_api_key: str | None = Header(default=None),
) -> dict[str, Any]:
    """Receive a signal and route it through the paper broker.

    Parameters
    ----------
    payload : AlertPayload
        The trading signal.
    x_api_key : str | None
        API key provided in the request header.

    Returns
    -------
    dict[str, Any]
        Acknowledgement with the paper trade details.
    """
    _verify_api_key(x_api_key)
    entry = {
        "received_at": datetime.now(timezone.utc).isoformat(),
        "payload": payload.model_dump(),
    }
    _signal_log.append(entry)

    trade = _paper_broker.submit_order(payload)
    logger.info(
        "Paper trade opened: %s %s %s @ %s",
        trade.trade_id,
        trade.symbol,
        trade.direction,
        trade.entry_price,
    )
    return {
        "status": "accepted",
        "trade_id": trade.trade_id,
        "payload": payload.model_dump(),
    }
