"""Backtest engine layer for strategy evaluation."""

from src.backtest.trade_log import Trade, TradeLog
from src.backtest.costs import CostModel
from src.backtest.execution import simulate_fill
from src.backtest.metrics import BacktestMetrics, calculate_metrics, calculate_equity_curve
from src.backtest.engine import BacktestEngine, BacktestResult
from src.backtest.walk_forward import (
    WalkForwardSplit,
    WalkForwardResult,
    generate_splits,
    run_walk_forward,
)

__all__ = [
    "Trade",
    "TradeLog",
    "CostModel",
    "simulate_fill",
    "BacktestMetrics",
    "calculate_metrics",
    "calculate_equity_curve",
    "BacktestEngine",
    "BacktestResult",
    "WalkForwardSplit",
    "WalkForwardResult",
    "generate_splits",
    "run_walk_forward",
]