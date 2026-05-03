"""Performance metrics for backtest evaluation."""
from __future__ import annotations

from dataclasses import dataclass
from typing import Optional

import numpy as np
import pandas as pd

from src.backtest.trade_log import TradeLog


@dataclass
class BacktestMetrics:
    """Standard performance metrics for a backtest run."""

    total_trades: int
    win_rate: float
    profit_factor: float
    sharpe_ratio: float
    sortino_ratio: float
    max_drawdown_pct: float
    max_drawdown_duration: float  # seconds
    avg_trade_pnl: float
    avg_winner: float
    avg_loser: float
    expectancy: float
    total_pnl: float
    return_pct: float
    avg_trade_duration: float  # seconds
    calmar_ratio: float


def calculate_equity_curve(
    trade_log: TradeLog,
    initial_capital: float,
) -> pd.Series:
    """Build a cumulative equity curve from the trade log.

    Parameters
    ----------
    trade_log : TradeLog
        Completed trade records.
    initial_capital : float
        Starting account balance.

    Returns
    -------
    pd.Series
        Equity indexed by trade exit time.
    """
    if not trade_log.trades:
        return pd.Series([initial_capital], dtype=float)

    sorted_trades = sorted(trade_log.trades, key=lambda t: t.exit_time)
    times = [sorted_trades[0].entry_time]
    equity = [initial_capital]

    running = initial_capital
    for t in sorted_trades:
        running += t.pnl_net
        times.append(t.exit_time)
        equity.append(running)

    return pd.Series(equity, index=pd.DatetimeIndex(times))


def _max_drawdown(equity: pd.Series) -> tuple[float, float]:
    """Return (max_drawdown_pct, max_drawdown_duration_seconds)."""
    if len(equity) < 2:
        return 0.0, 0.0

    peak = equity.expanding().max()
    drawdown = (equity - peak) / peak

    max_dd_pct = abs(float(drawdown.min()))

    # Duration: longest streak below previous peak
    is_dd = equity < peak
    if not is_dd.any():
        return max_dd_pct, 0.0

    groups: list[float] = []
    start: Optional[pd.Timestamp] = None
    for ts, below in is_dd.items():
        if below:
            if start is None:
                start = ts
        else:
            if start is not None:
                groups.append((ts - start).total_seconds())
                start = None
    if start is not None:
        groups.append((equity.index[-1] - start).total_seconds())

    max_dd_dur = max(groups) if groups else 0.0
    return max_dd_pct, max_dd_dur


def calculate_metrics(
    trade_log: TradeLog,
    initial_capital: float,
) -> BacktestMetrics:
    """Compute all standard performance metrics.

    Parameters
    ----------
    trade_log : TradeLog
        Completed trade records.
    initial_capital : float
        Starting account balance.

    Returns
    -------
    BacktestMetrics
        Aggregated performance statistics.
    """
    total = trade_log.total_trades
    if total == 0:
        return BacktestMetrics(
            total_trades=0,
            win_rate=0.0,
            profit_factor=0.0,
            sharpe_ratio=0.0,
            sortino_ratio=0.0,
            max_drawdown_pct=0.0,
            max_drawdown_duration=0.0,
            avg_trade_pnl=0.0,
            avg_winner=0.0,
            avg_loser=0.0,
            expectancy=0.0,
            total_pnl=0.0,
            return_pct=0.0,
            avg_trade_duration=0.0,
            calmar_ratio=0.0,
        )

    pnls = np.array([t.pnl_net for t in trade_log.trades])
    winners = pnls[pnls > 0]
    losers = pnls[pnls <= 0]

    win_rate = len(winners) / total if total else 0.0
    total_pnl = float(pnls.sum())
    avg_trade_pnl = float(pnls.mean())
    avg_winner = float(winners.mean()) if len(winners) else 0.0
    avg_loser = float(losers.mean()) if len(losers) else 0.0

    gross_profit = float(winners.sum()) if len(winners) else 0.0
    gross_loss = abs(float(losers.sum())) if len(losers) else 0.0
    profit_factor = gross_profit / gross_loss if gross_loss > 0 else float("inf")

    # Expectancy: (win_rate * avg_winner) + ((1 - win_rate) * avg_loser)
    expectancy = (win_rate * avg_winner) + ((1 - win_rate) * avg_loser)

    # Sharpe & Sortino (per-trade, annualized assuming 252 trading days)
    pnl_std = float(pnls.std(ddof=1)) if total > 1 else 0.0
    sharpe_ratio = (avg_trade_pnl / pnl_std * np.sqrt(252)) if pnl_std > 0 else 0.0

    downside = pnls[pnls < 0]
    downside_std = float(downside.std(ddof=1)) if len(downside) > 1 else 0.0
    sortino_ratio = (avg_trade_pnl / downside_std * np.sqrt(252)) if downside_std > 0 else 0.0

    # Equity curve & drawdown
    equity = calculate_equity_curve(trade_log, initial_capital)
    max_dd_pct, max_dd_dur = _max_drawdown(equity)

    return_pct = total_pnl / initial_capital * 100 if initial_capital > 0 else 0.0

    durations = [t.duration_seconds for t in trade_log.trades]
    avg_trade_duration = float(np.mean(durations)) if durations else 0.0

    # Calmar: annualized return / max drawdown
    # Rough annualization: return_pct * (252 / total_trades) -- simplistic
    calmar_ratio = (return_pct / max_dd_pct) if max_dd_pct > 0 else 0.0

    return BacktestMetrics(
        total_trades=total,
        win_rate=win_rate,
        profit_factor=profit_factor,
        sharpe_ratio=sharpe_ratio,
        sortino_ratio=sortino_ratio,
        max_drawdown_pct=max_dd_pct,
        max_drawdown_duration=max_dd_dur,
        avg_trade_pnl=avg_trade_pnl,
        avg_winner=avg_winner,
        avg_loser=avg_loser,
        expectancy=expectancy,
        total_pnl=total_pnl,
        return_pct=return_pct,
        avg_trade_duration=avg_trade_duration,
        calmar_ratio=calmar_ratio,
    )
