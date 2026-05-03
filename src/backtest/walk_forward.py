"""Walk-forward analysis for robust strategy evaluation."""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Callable, Optional, Type

import pandas as pd

from src.backtest.costs import CostModel
from src.backtest.engine import BacktestEngine, BacktestResult
from src.backtest.metrics import BacktestMetrics, calculate_metrics
from src.backtest.trade_log import TradeLog
from src.strategies.base import BaseStrategy, StrategyParams


@dataclass
class WalkForwardSplit:
    """Definition of a single walk-forward window."""

    train_start: pd.Timestamp
    train_end: pd.Timestamp
    test_start: pd.Timestamp
    test_end: pd.Timestamp


@dataclass
class WalkForwardResult:
    """Aggregated walk-forward analysis results."""

    in_sample_metrics: list[BacktestMetrics]
    out_of_sample_metrics: list[BacktestMetrics]
    combined_oos_metrics: BacktestMetrics
    retention_ratio: float


def generate_splits(
    df: pd.DataFrame,
    n_splits: int,
    train_ratio: float = 0.7,
    gap_bars: int = 0,
) -> list[WalkForwardSplit]:
    """Generate walk-forward train/test splits.

    The data is divided into ``n_splits`` anchored-forward windows.
    Each window uses ``train_ratio`` of the available bars for training
    and the remainder for testing, with an optional gap between them to
    prevent look-ahead.

    Parameters
    ----------
    df : pd.DataFrame
        OHLC DataFrame with a DatetimeIndex.
    n_splits : int
        Number of walk-forward folds.
    train_ratio : float
        Proportion of each fold used for training (0–1).
    gap_bars : int
        Number of bars to skip between train and test sets.

    Returns
    -------
    list[WalkForwardSplit]
        Ordered list of split definitions.
    """
    n_rows = len(df)
    fold_size = n_rows // n_splits
    splits: list[WalkForwardSplit] = []

    for i in range(n_splits):
        start_idx = i * fold_size
        end_idx = (i + 1) * fold_size if i < n_splits - 1 else n_rows

        fold_len = end_idx - start_idx
        train_len = int(fold_len * train_ratio)

        train_start_idx = start_idx
        train_end_idx = start_idx + train_len - 1
        test_start_idx = min(train_end_idx + 1 + gap_bars, end_idx - 1)
        test_end_idx = end_idx - 1

        if test_start_idx >= test_end_idx:
            continue

        splits.append(
            WalkForwardSplit(
                train_start=df.index[train_start_idx],
                train_end=df.index[train_end_idx],
                test_start=df.index[test_start_idx],
                test_end=df.index[test_end_idx],
            )
        )

    return splits


def run_walk_forward(
    strategy_class: Type[BaseStrategy],
    candle_df: pd.DataFrame,
    param_space: list[dict[str, Any]],
    cost_model: CostModel,
    n_splits: int = 5,
    optimize_fn: Optional[Callable[[BacktestMetrics], float]] = None,
    initial_capital: float = 10_000.0,
    symbol: str = "UNKNOWN",
    quantity: float = 1.0,
    spread_pips: float = 0.5,
    train_ratio: float = 0.7,
    gap_bars: int = 0,
) -> WalkForwardResult:
    """Execute walk-forward optimization and validation.

    For each split the strategy is optimized on the training window by
    iterating over ``param_space`` and selecting the parameters that
    maximize ``optimize_fn``.  The best parameters are then evaluated
    on the out-of-sample test window.

    Parameters
    ----------
    strategy_class : Type[BaseStrategy]
        Strategy class to instantiate for each param set.
    candle_df : pd.DataFrame
        Full OHLC DataFrame with DatetimeIndex.
    param_space : list[dict[str, Any]]
        List of parameter dictionaries to search.
    cost_model : CostModel
        Transaction cost model.
    n_splits : int
        Number of walk-forward folds.
    optimize_fn : callable, optional
        Function that maps ``BacktestMetrics`` → ``float`` (higher is
        better).  Defaults to ``profit_factor``.
    initial_capital : float
        Starting capital per fold.
    symbol : str
        Instrument symbol.
    quantity : float
        Position size in lots.
    spread_pips : float
        Assumed spread in pips.
    train_ratio : float
        Fraction of each fold used for training.
    gap_bars : int
        Bars to skip between train and test sets.

    Returns
    -------
    WalkForwardResult
        In-sample and out-of-sample metrics with retention ratio.
    """
    if optimize_fn is None:
        optimize_fn = lambda m: m.profit_factor  # noqa: E731

    splits = generate_splits(candle_df, n_splits, train_ratio, gap_bars)
    engine = BacktestEngine(symbol=symbol, quantity=quantity, spread_pips=spread_pips)

    is_metrics_list: list[BacktestMetrics] = []
    oos_metrics_list: list[BacktestMetrics] = []
    combined_oos_trade_log = TradeLog()

    for split in splits:
        train_df = candle_df.loc[split.train_start : split.train_end]
        test_df = candle_df.loc[split.test_start : split.test_end]

        # Optimize: iterate param_space on training data
        best_score = float("-inf")
        best_params: dict[str, Any] = param_space[0] if param_space else {}
        best_is_metrics: Optional[BacktestMetrics] = None

        for params in param_space:
            strat = strategy_class(StrategyParams(name=strategy_class.__name__, params=params))
            result = engine.run(strat, train_df, cost_model, initial_capital)
            score = optimize_fn(result.metrics)
            if score > best_score:
                best_score = score
                best_params = params
                best_is_metrics = result.metrics

        if best_is_metrics is not None:
            is_metrics_list.append(best_is_metrics)

        # Test: evaluate best params on out-of-sample data
        best_strat = strategy_class(StrategyParams(name=strategy_class.__name__, params=best_params))
        oos_result = engine.run(best_strat, test_df, cost_model, initial_capital)
        oos_metrics_list.append(oos_result.metrics)

        for trade in oos_result.trade_log.trades:
            combined_oos_trade_log.add(trade)

    combined_oos_metrics = calculate_metrics(combined_oos_trade_log, initial_capital)

    # Retention ratio: average OOS metric / average IS metric
    if is_metrics_list and oos_metrics_list:
        avg_is = sum(optimize_fn(m) for m in is_metrics_list) / len(is_metrics_list)
        avg_oos = sum(optimize_fn(m) for m in oos_metrics_list) / len(oos_metrics_list)
        retention = avg_oos / avg_is if avg_is != 0 else 0.0
    else:
        retention = 0.0

    return WalkForwardResult(
        in_sample_metrics=is_metrics_list,
        out_of_sample_metrics=oos_metrics_list,
        combined_oos_metrics=combined_oos_metrics,
        retention_ratio=retention,
    )
