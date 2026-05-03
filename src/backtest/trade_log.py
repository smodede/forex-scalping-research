"""Trade log data structures."""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

import pandas as pd


@dataclass
class Trade:
    """Completed trade record."""

    trade_id: str
    symbol: str
    direction: str  # "long" or "short"
    entry_time: pd.Timestamp
    exit_time: pd.Timestamp
    entry_price: float
    exit_price: float
    stop_loss: float
    take_profit: float
    quantity: float
    pnl_gross: float
    pnl_net: float  # after costs
    commission: float
    slippage_cost: float
    spread_cost: float
    duration_seconds: float
    exit_reason: str  # "tp", "sl", "signal", "timeout"
    metadata: dict[str, Any] = field(default_factory=dict)


class TradeLog:
    """Collection of trades with export utilities."""

    def __init__(self) -> None:
        self.trades: list[Trade] = []

    def add(self, trade: Trade) -> None:
        """Append a completed trade to the log."""
        self.trades.append(trade)

    def to_dataframe(self) -> pd.DataFrame:
        """Convert trade log to a pandas DataFrame."""
        if not self.trades:
            return pd.DataFrame()
        records = []
        for t in self.trades:
            records.append(
                {
                    "trade_id": t.trade_id,
                    "symbol": t.symbol,
                    "direction": t.direction,
                    "entry_time": t.entry_time,
                    "exit_time": t.exit_time,
                    "entry_price": t.entry_price,
                    "exit_price": t.exit_price,
                    "stop_loss": t.stop_loss,
                    "take_profit": t.take_profit,
                    "quantity": t.quantity,
                    "pnl_gross": t.pnl_gross,
                    "pnl_net": t.pnl_net,
                    "commission": t.commission,
                    "slippage_cost": t.slippage_cost,
                    "spread_cost": t.spread_cost,
                    "duration_seconds": t.duration_seconds,
                    "exit_reason": t.exit_reason,
                }
            )
        return pd.DataFrame(records)

    def save_csv(self, path: str) -> None:
        """Export trade log to CSV."""
        self.to_dataframe().to_csv(path, index=False)

    @property
    def total_trades(self) -> int:
        """Total number of completed trades."""
        return len(self.trades)

    @property
    def winning_trades(self) -> int:
        """Number of profitable trades."""
        return sum(1 for t in self.trades if t.pnl_net > 0)

    @property
    def losing_trades(self) -> int:
        """Number of losing or break-even trades."""
        return sum(1 for t in self.trades if t.pnl_net <= 0)
