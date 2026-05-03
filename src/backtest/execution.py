"""Simulated order execution against historical candle data."""
from __future__ import annotations

import uuid
from typing import Optional

import pandas as pd

from src.backtest.costs import CostModel
from src.backtest.trade_log import Trade
from src.strategies.base import Signal


def simulate_fill(
    signal: Signal,
    candle: pd.Series,
    cost_model: CostModel,
    symbol: str = "UNKNOWN",
    quantity: float = 1.0,
    spread_pips: float = 0.5,
) -> Optional[Trade]:
    """Simulate trade execution on a single candle.

    Applies slippage to the entry price in the adverse direction, checks
    whether the stop-loss or take-profit is hit within the candle using
    high/low, and computes PnL inclusive of all costs.

    If both SL and TP could be hit within the same candle the worst case
    is assumed (SL hit first).

    Parameters
    ----------
    signal : Signal
        Trade signal containing direction, entry, SL, TP.
    candle : pd.Series
        OHLC candle with ``open``, ``high``, ``low``, ``close`` and a
        datetime index or ``timestamp`` field.
    cost_model : CostModel
        Transaction cost model.
    symbol : str
        Instrument symbol for the trade record.
    quantity : float
        Position size in lots.
    spread_pips : float
        Current spread in pips.  Trade is rejected when this exceeds
        ``cost_model.max_spread_pips``.

    Returns
    -------
    Trade or None
        Completed trade record, or ``None`` if the spread is too wide.
    """
    if spread_pips > cost_model.max_spread_pips:
        return None

    direction = signal.direction
    pip_size = (
        cost_model.pip_value / 10_000
        if cost_model.pip_value >= 1.0
        else cost_model.pip_value / 100
    )

    # Apply slippage to entry price (adverse direction)
    slippage_offset = cost_model.slippage_pips * pip_size
    if direction == "long":
        fill_price = signal.entry_price + slippage_offset
    else:
        fill_price = signal.entry_price - slippage_offset

    # Determine exit using candle high/low
    candle_high = candle["high"]
    candle_low = candle["low"]
    candle_close = candle["close"]

    sl_hit = False
    tp_hit = False

    if direction == "long":
        sl_hit = candle_low <= signal.stop_loss
        tp_hit = candle_high >= signal.take_profit
    else:
        sl_hit = candle_high >= signal.stop_loss
        tp_hit = candle_low <= signal.take_profit

    # Resolve exit price and reason
    if sl_hit and tp_hit:
        # Worst-case: SL hit first
        exit_price = signal.stop_loss
        exit_reason = "sl"
    elif sl_hit:
        exit_price = signal.stop_loss
        exit_reason = "sl"
    elif tp_hit:
        exit_price = signal.take_profit
        exit_reason = "tp"
    else:
        exit_price = candle_close
        exit_reason = "signal"

    # Gross PnL: convert price movement to pips, then to dollar value
    price_diff = (exit_price - fill_price) if direction == "long" else (fill_price - exit_price)
    pips_moved = price_diff / pip_size
    pnl_gross = pips_moved * cost_model.pip_value * quantity

    # Costs
    commission, slippage_cost, spread_cost, total_cost = cost_model.total_cost(
        quantity, spread_pips, direction, signal.entry_price
    )
    pnl_net = pnl_gross - total_cost

    # Timestamps
    entry_time = signal.timestamp
    exit_time = candle.name if isinstance(candle.name, pd.Timestamp) else pd.Timestamp(candle.name)
    duration = (exit_time - entry_time).total_seconds() if entry_time is not None else 0.0

    return Trade(
        trade_id=str(uuid.uuid4()),
        symbol=symbol,
        direction=direction,
        entry_time=entry_time,
        exit_time=exit_time,
        entry_price=fill_price,
        exit_price=exit_price,
        stop_loss=signal.stop_loss,
        take_profit=signal.take_profit,
        quantity=quantity,
        pnl_gross=pnl_gross,
        pnl_net=pnl_net,
        commission=commission,
        slippage_cost=slippage_cost,
        spread_cost=spread_cost,
        duration_seconds=duration,
        exit_reason=exit_reason,
        metadata=signal.metadata.copy(),
    )
