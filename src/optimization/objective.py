"""Optimization objective functions for Optuna trials."""
from __future__ import annotations

import logging
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Optional, Type

import optuna
import pandas as pd
import yaml

from src.backtest.costs import CostModel
from src.backtest.engine import BacktestEngine, BacktestResult
from src.backtest.metrics import BacktestMetrics
from src.optimization.search_space import SearchSpace
from src.strategies.base import BaseStrategy, StrategyParams

logger = logging.getLogger(__name__)

_CONFIG_ROOT = Path(__file__).resolve().parents[2] / "config"


def _load_validation_gates() -> dict[str, Any]:
    """Load validation gate thresholds from config."""
    path = _CONFIG_ROOT / "validation_gates.yaml"
    if path.exists():
        with open(path) as fh:
            return yaml.safe_load(fh) or {}
    return {}


@dataclass
class ObjectiveWeights:
    """Weights for the composite objective function.

    All weights are positive.  The drawdown weight is applied to the
    *negated* drawdown so that minimising drawdown is rewarded.
    """

    sharpe: float = 0.40
    profit_factor: float = 0.30
    drawdown: float = 0.20
    win_rate: float = 0.10


def composite_objective(
    metrics: BacktestMetrics,
    weights: Optional[ObjectiveWeights] = None,
) -> float:
    """Compute a weighted composite score from backtest metrics.

    Higher is better.

    Parameters
    ----------
    metrics : BacktestMetrics
        Backtest performance metrics.
    weights : ObjectiveWeights, optional
        Component weights.  Defaults to a balanced set.

    Returns
    -------
    float
        Composite objective value.
    """
    w = weights or ObjectiveWeights()
    return (
        w.sharpe * metrics.sharpe_ratio
        + w.profit_factor * metrics.profit_factor
        + w.drawdown * (-metrics.max_drawdown_pct)
        + w.win_rate * metrics.win_rate
    )


def _apply_pruning_gates(
    trial: optuna.Trial,
    metrics: BacktestMetrics,
    gates: dict[str, Any],
) -> bool:
    """Check validation gates and prune the trial if it fails.

    Parameters
    ----------
    trial : optuna.Trial
        Current Optuna trial.
    metrics : BacktestMetrics
        Metrics from the current evaluation.
    gates : dict[str, Any]
        Gate thresholds loaded from config.

    Returns
    -------
    bool
        ``True`` if the trial passes all gates, ``False`` if pruned.
    """
    is_gates = gates.get("gates", {}).get("in_sample", {})

    if is_gates.get("min_trades") and metrics.total_trades < is_gates["min_trades"]:
        raise optuna.TrialPruned(
            f"Too few trades: {metrics.total_trades} < {is_gates['min_trades']}"
        )

    if is_gates.get("min_profit_factor") and metrics.profit_factor < is_gates["min_profit_factor"]:
        raise optuna.TrialPruned(
            f"Low profit factor: {metrics.profit_factor:.2f} < {is_gates['min_profit_factor']}"
        )

    if is_gates.get("max_drawdown_pct") and metrics.max_drawdown_pct > is_gates["max_drawdown_pct"]:
        raise optuna.TrialPruned(
            f"Excessive drawdown: {metrics.max_drawdown_pct:.1f}% > {is_gates['max_drawdown_pct']}%"
        )

    if is_gates.get("min_sharpe") and metrics.sharpe_ratio < is_gates["min_sharpe"]:
        raise optuna.TrialPruned(
            f"Low Sharpe: {metrics.sharpe_ratio:.2f} < {is_gates['min_sharpe']}"
        )

    return True


class Objective:
    """Optuna-compatible objective wrapping strategy evaluation.

    Parameters
    ----------
    strategy_class : Type[BaseStrategy]
        Strategy class to instantiate per trial.
    search_space : SearchSpace
        Parameter search space.
    candle_df : pd.DataFrame
        OHLC data with ``DatetimeIndex``.
    cost_model : CostModel
        Transaction cost model.
    initial_capital : float
        Starting capital for each backtest.
    weights : ObjectiveWeights, optional
        Composite objective weights.
    apply_gates : bool
        Whether to enforce validation gates as pruning criteria.
    symbol : str
        Trading instrument symbol.
    quantity : float
        Position size in lots.
    spread_pips : float
        Assumed spread in pips.
    """

    def __init__(
        self,
        strategy_class: Type[BaseStrategy],
        search_space: SearchSpace,
        candle_df: pd.DataFrame,
        cost_model: CostModel,
        initial_capital: float = 10_000.0,
        weights: Optional[ObjectiveWeights] = None,
        apply_gates: bool = True,
        symbol: str = "UNKNOWN",
        quantity: float = 1.0,
        spread_pips: float = 0.5,
    ) -> None:
        self.strategy_class = strategy_class
        self.search_space = search_space
        self.candle_df = candle_df
        self.cost_model = cost_model
        self.initial_capital = initial_capital
        self.weights = weights or ObjectiveWeights()
        self.apply_gates = apply_gates
        self.engine = BacktestEngine(
            symbol=symbol, quantity=quantity, spread_pips=spread_pips
        )
        self._gates_config = _load_validation_gates() if apply_gates else {}

    def __call__(self, trial: optuna.Trial) -> float:
        """Evaluate a single Optuna trial.

        Parameters
        ----------
        trial : optuna.Trial
            Active trial providing parameter suggestions.

        Returns
        -------
        float
            Composite objective value (higher is better).

        Raises
        ------
        optuna.TrialPruned
            If validation gates are not met.
        """
        params = self.search_space.to_optuna_suggest(trial)

        strategy = self.strategy_class(
            StrategyParams(name=self.strategy_class.__name__, params=params)
        )
        result: BacktestResult = self.engine.run(
            strategy, self.candle_df, self.cost_model, self.initial_capital
        )

        if self.apply_gates:
            _apply_pruning_gates(trial, result.metrics, self._gates_config)

        score = composite_objective(result.metrics, self.weights)

        # Report intermediate value for Optuna pruning
        trial.report(score, step=0)
        if trial.should_prune():
            raise optuna.TrialPruned()

        logger.debug(
            "Trial %d: score=%.4f sharpe=%.2f pf=%.2f dd=%.1f%%",
            trial.number,
            score,
            result.metrics.sharpe_ratio,
            result.metrics.profit_factor,
            result.metrics.max_drawdown_pct,
        )
        return score


class MultiObjective:
    """Multi-objective wrapper returning (sharpe, -drawdown).

    For use with ``optuna.create_study(directions=["maximize", "minimize"])``.

    Parameters
    ----------
    strategy_class : Type[BaseStrategy]
        Strategy class.
    search_space : SearchSpace
        Parameter search space.
    candle_df : pd.DataFrame
        OHLC data.
    cost_model : CostModel
        Cost model.
    initial_capital : float
        Starting capital.
    symbol : str
        Instrument symbol.
    quantity : float
        Position size.
    spread_pips : float
        Assumed spread.
    """

    def __init__(
        self,
        strategy_class: Type[BaseStrategy],
        search_space: SearchSpace,
        candle_df: pd.DataFrame,
        cost_model: CostModel,
        initial_capital: float = 10_000.0,
        symbol: str = "UNKNOWN",
        quantity: float = 1.0,
        spread_pips: float = 0.5,
    ) -> None:
        self.strategy_class = strategy_class
        self.search_space = search_space
        self.candle_df = candle_df
        self.cost_model = cost_model
        self.initial_capital = initial_capital
        self.engine = BacktestEngine(
            symbol=symbol, quantity=quantity, spread_pips=spread_pips
        )

    def __call__(self, trial: optuna.Trial) -> tuple[float, float]:
        """Return (sharpe_ratio, max_drawdown_pct) for multi-objective optimisation.

        Parameters
        ----------
        trial : optuna.Trial
            Active trial.

        Returns
        -------
        tuple[float, float]
            ``(sharpe_ratio, max_drawdown_pct)`` — study should maximise
            sharpe and minimise drawdown.
        """
        params = self.search_space.to_optuna_suggest(trial)
        strategy = self.strategy_class(
            StrategyParams(name=self.strategy_class.__name__, params=params)
        )
        result = self.engine.run(
            strategy, self.candle_df, self.cost_model, self.initial_capital
        )
        return result.metrics.sharpe_ratio, result.metrics.max_drawdown_pct
