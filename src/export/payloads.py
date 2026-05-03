"""Alert payload generation for webhook and TradingView alerts."""
from __future__ import annotations

import json
from datetime import datetime, timezone
from typing import Any, Optional

from pydantic import BaseModel, Field

from src.strategies.base import Signal
from src.backtest.trade_log import Trade


class AlertPayload(BaseModel):
    """Standardised alert payload for external systems."""

    action: str  # "entry" or "exit"
    symbol: str
    direction: str  # "long" or "short"
    entry_price: float
    sl: float
    tp: float
    quantity: float
    strategy_name: str
    timestamp: str


def generate_entry_payload(signal: Signal, strategy_name: str) -> dict[str, Any]:
    """Build an entry alert payload from a trading signal."""
    payload = AlertPayload(
        action="entry",
        symbol=signal.metadata.get("symbol", "UNKNOWN"),
        direction=signal.direction,
        entry_price=signal.entry_price,
        sl=signal.stop_loss,
        tp=signal.take_profit,
        quantity=signal.metadata.get("quantity", 1.0),
        strategy_name=strategy_name,
        timestamp=signal.timestamp.isoformat(),
    )
    return payload.model_dump()


def generate_exit_payload(trade: Trade, strategy_name: str) -> dict[str, Any]:
    """Build an exit alert payload from a completed trade."""
    payload = AlertPayload(
        action="exit",
        symbol=trade.symbol,
        direction=trade.direction,
        entry_price=trade.entry_price,
        sl=trade.stop_loss,
        tp=trade.take_profit,
        quantity=trade.quantity,
        strategy_name=strategy_name,
        timestamp=trade.exit_time.isoformat(),
    )
    return payload.model_dump()


def format_tradingview_alert(payload: dict[str, Any]) -> str:
    """Format a payload as a TradingView-compatible alert message string.

    Produces a simple key=value format that TradingView webhook alerts
    can parse.
    """
    lines = [f"{k}={v}" for k, v in payload.items()]
    return "\n".join(lines)


def format_webhook_json(payload: dict[str, Any]) -> str:
    """Serialise a payload as a compact JSON string for webhook delivery."""
    return json.dumps(payload, separators=(",", ":"))
