"""Main backtest engine for sequential candle processing."""
from __future__ import annotations

from dataclasses import dataclass
from typing import Optional

import pandas as pd

from src.backtest.costs import CostModel
from src.backtest.execution import simulate_fill
from src.backtest.metrics import (
    BacktestMetrics,
    calculate_equity_curve,
    calculate_metrics,
)
from src.backtest.trade_log import Trade, TradeLog
from src.strategies.base import BaseStrategy, Signal


@dataclass
class BacktestResult:
    """Container for a completed backtest run."""

    trade_log: TradeLog
    metrics: BacktestMetrics
    equity_curve: pd.Series
    params: dict


class BacktestEngine:
    """Event-driven backtest engine.

    Processes candles sequentially, generates signals via a provided
    strategy, executes simulated fills, and enforces a single-position
    constraint.

    Parameters
    ----------
    symbol : str
        Instrument being traded.
    quantity : float
        Default position size in lots.
    spread_pips : float
        Assumed constant spread in pips.
    """

    def __init__(
        self,
        symbol: str = "UNKNOWN",
        quantity: float = 1.0,
        spread_pips: float = 0.5,
    ) -> None:
        self.symbol = symbol
        self.quantity = quantity
        self.spread_pips = spread_pips

    def run(
        self,
        strategy: BaseStrategy,
        candle_df: pd.DataFrame,
        cost_model: CostModel,
        initial_capital: float = 10_000.0,
    ) -> BacktestResult:
        """Execute a full backtest.

        Parameters
        ----------
        strategy : BaseStrategy
            Strategy instance that produces signals.
        candle_df : pd.DataFrame
            OHLC DataFrame indexed by datetime with columns
            ``open``, ``high``, ``low``, ``close``.
        cost_model : CostModel
            Transaction cost model.
        initial_capital : float
            Starting account balance.

        Returns
        -------
        BacktestResult
            Trade log, metrics, equity curve, and strategy params.
        """
        trade_log = TradeLog()

        # Generate signals up front
        signals = strategy.generate_signals(candle_df)
        signal_map: dict[pd.Timestamp, Signal] = {}
        for sig in signals:
            signal_map[sig.timestamp] = sig

        open_signal: Optional[Signal] = None
        equity = initial_capital
        equity_values: list[float] = [initial_capital]
        equity_times: list[pd.Timestamp] = [candle_df.index[0]]

        for ts, candle in candle_df.iterrows():
            ts = pd.Timestamp(ts)

            # If a position is open, attempt to close on this candle
            if open_signal is not None:
                trade = simulate_fill(
                    signal=open_signal,
                    candle=candle,
                    cost_model=cost_model,
                    symbol=self.symbol,
                    quantity=self.quantity,
                    spread_pips=self.spread_pips,
                )
                if trade is not None:
                    trade_log.add(trade)
                    equity += trade.pnl_net
                    open_signal = None

            # If no position, check for a new signal on this bar
            if open_signal is None and ts in signal_map:
                open_signal = signal_map[ts]

            equity_values.append(equity)
            equity_times.append(ts)

        equity_curve = pd.Series(equity_values, index=pd.DatetimeIndex(equity_times))
        metrics = calculate_metrics(trade_log, initial_capital)

        return BacktestResult(
            trade_log=trade_log,
            metrics=metrics,
            equity_curve=equity_curve,
            params=strategy.params.params if strategy.params else {},
        )
