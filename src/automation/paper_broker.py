"""Paper trading broker for simulated order execution."""
from __future__ import annotations

import json
import uuid
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional

from src.export.payloads import AlertPayload


@dataclass
class PaperTrade:
    """Record of a simulated trade."""

    trade_id: str
    symbol: str
    direction: str
    entry_time: datetime
    entry_price: float
    stop_loss: float
    take_profit: float
    quantity: float
    status: str = "open"
    exit_time: Optional[datetime] = None
    exit_price: Optional[float] = None
    pnl: Optional[float] = None
    exit_reason: Optional[str] = None


class PaperBroker:
    """Simulated broker that tracks paper trades."""

    def __init__(self) -> None:
        self._open: list[PaperTrade] = []
        self._closed: list[PaperTrade] = []

    def submit_order(self, payload: AlertPayload) -> PaperTrade:
        """Create a new paper trade from an alert payload.

        Parameters
        ----------
        payload : AlertPayload
            Incoming alert with trade details.

        Returns
        -------
        PaperTrade
            The newly opened paper trade.
        """
        trade = PaperTrade(
            trade_id=uuid.uuid4().hex[:12],
            symbol=payload.symbol,
            direction=payload.direction,
            entry_time=datetime.now(timezone.utc),
            entry_price=payload.entry_price,
            stop_loss=payload.sl,
            take_profit=payload.tp,
            quantity=payload.quantity,
        )
        self._open.append(trade)
        return trade

    def update_positions(self, current_prices: dict[str, float]) -> list[PaperTrade]:
        """Check open positions against current prices for SL/TP hits.

        Parameters
        ----------
        current_prices : dict[str, float]
            Mapping of symbol to current price.

        Returns
        -------
        list[PaperTrade]
            Trades that were closed during this update.
        """
        closed_this_tick: list[PaperTrade] = []
        still_open: list[PaperTrade] = []

        for trade in self._open:
            price = current_prices.get(trade.symbol)
            if price is None:
                still_open.append(trade)
                continue

            exit_reason: Optional[str] = None

            if trade.direction == "long":
                if price <= trade.stop_loss:
                    exit_reason = "stop_loss"
                elif price >= trade.take_profit:
                    exit_reason = "take_profit"
            else:
                if price >= trade.stop_loss:
                    exit_reason = "stop_loss"
                elif price <= trade.take_profit:
                    exit_reason = "take_profit"

            if exit_reason is not None:
                trade.status = "closed"
                trade.exit_time = datetime.now(timezone.utc)
                trade.exit_price = price
                multiplier = 1.0 if trade.direction == "long" else -1.0
                trade.pnl = (price - trade.entry_price) * trade.quantity * multiplier
                trade.exit_reason = exit_reason
                self._closed.append(trade)
                closed_this_tick.append(trade)
            else:
                still_open.append(trade)

        self._open = still_open
        return closed_this_tick

    def get_open_positions(self) -> list[PaperTrade]:
        """Return a copy of all open positions."""
        return list(self._open)

    def get_closed_positions(self) -> list[PaperTrade]:
        """Return a copy of all closed positions."""
        return list(self._closed)

    def get_performance(self) -> dict[str, Any]:
        """Compute aggregate performance statistics.

        Returns
        -------
        dict[str, Any]
            Summary including total trades, win rate, total PnL, and
            average PnL.
        """
        total = len(self._closed)
        if total == 0:
            return {
                "total_trades": 0,
                "wins": 0,
                "losses": 0,
                "win_rate": 0.0,
                "total_pnl": 0.0,
                "avg_pnl": 0.0,
            }

        wins = sum(1 for t in self._closed if (t.pnl or 0) > 0)
        total_pnl = sum(t.pnl or 0 for t in self._closed)
        return {
            "total_trades": total,
            "wins": wins,
            "losses": total - wins,
            "win_rate": wins / total,
            "total_pnl": total_pnl,
            "avg_pnl": total_pnl / total,
        }

    def save_state(self, path: Path) -> None:
        """Persist broker state to a JSON file.

        Parameters
        ----------
        path : Path
            Destination file path.
        """
        state = {
            "open": [asdict(t) for t in self._open],
            "closed": [asdict(t) for t in self._closed],
        }
        path.parent.mkdir(parents=True, exist_ok=True)
        with open(path, "w") as fh:
            json.dump(state, fh, default=str, indent=2)

    def load_state(self, path: Path) -> None:
        """Restore broker state from a JSON file.

        Parameters
        ----------
        path : Path
            Source file path.
        """
        with open(path) as fh:
            state = json.load(fh)

        def _parse_trade(d: dict[str, Any]) -> PaperTrade:
            for key in ("entry_time", "exit_time"):
                if d.get(key) is not None:
                    d[key] = datetime.fromisoformat(str(d[key]))
            return PaperTrade(**d)

        self._open = [_parse_trade(t) for t in state.get("open", [])]
        self._closed = [_parse_trade(t) for t in state.get("closed", [])]
