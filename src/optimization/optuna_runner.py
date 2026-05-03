"""Optuna-based optimization runner."""
from __future__ import annotations

import logging
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Optional, Type

import optuna
import pandas as pd
import yaml

from src.backtest.costs import CostModel
from src.backtest.metrics import BacktestMetrics
from src.optimization.objective import (
    MultiObjective,
    Objective,
    ObjectiveWeights,
)
from src.optimization.search_space import SearchSpace, build_search_space
from src.strategies.base import BaseStrategy

logger = logging.getLogger(__name__)

_CONFIG_ROOT = Path(__file__).resolve().parents[2] / "config"


def _load_search_config() -> dict[str, Any]:
    """Load search configuration from config/strategy_search.yaml."""
    path = _CONFIG_ROOT / "strategy_search.yaml"
    if path.exists():
        with open(path) as fh:
            return yaml.safe_load(fh) or {}
    return {}


@dataclass
class OptimizationResult:
    """Container for optimization run outputs.

    Attributes
    ----------
    best_params : dict[str, Any]
        Parameters that achieved the best objective value.
    best_value : float
        Best objective value found.
    study : optuna.Study
        The underlying Optuna study object.
    all_trials_df : pd.DataFrame
        DataFrame of all trial results with params, values, and state.
    """

    best_params: dict[str, Any]
    best_value: float
    study: optuna.Study
    all_trials_df: pd.DataFrame


def _build_sampler(sampler_name: str) -> optuna.samplers.BaseSampler:
    """Instantiate a sampler by name.

    Parameters
    ----------
    sampler_name : str
        One of ``"TPE"``, ``"CmaEs"``, ``"Random"``.

    Returns
    -------
    optuna.samplers.BaseSampler
    """
    name = sampler_name.lower()
    if name == "tpe":
        return optuna.samplers.TPESampler()
    if name == "cmaes":
        return optuna.samplers.CmaEsSampler()
    if name == "random":
        return optuna.samplers.RandomSampler()
    logger.warning("Unknown sampler '%s', falling back to TPE", sampler_name)
    return optuna.samplers.TPESampler()


def _build_pruner(pruner_name: str) -> optuna.pruners.BasePruner:
    """Instantiate a pruner by name.

    Parameters
    ----------
    pruner_name : str
        One of ``"MedianPruner"``, ``"Hyperband"``, ``"NopPruner"``.

    Returns
    -------
    optuna.pruners.BasePruner
    """
    name = pruner_name.lower().replace("_", "")
    if name == "medianpruner":
        return optuna.pruners.MedianPruner()
    if name == "hyperband":
        return optuna.pruners.HyperbandPruner()
    if name in ("noppruner", "none"):
        return optuna.pruners.NopPruner()
    logger.warning("Unknown pruner '%s', falling back to MedianPruner", pruner_name)
    return optuna.pruners.MedianPruner()


def _trials_to_dataframe(study: optuna.Study) -> pd.DataFrame:
    """Convert study trials to a DataFrame including params."""
    records: list[dict[str, Any]] = []
    for trial in study.trials:
        row: dict[str, Any] = {
            "number": trial.number,
            "value": trial.value if trial.value is not None else float("nan"),
            "state": trial.state.name,
        }
        row.update(trial.params)
        records.append(row)
    return pd.DataFrame(records)


class OptunaRunner:
    """High-level Optuna optimization driver.

    Loads defaults from ``config/strategy_search.yaml`` and orchestrates
    study creation, objective evaluation, and result collection.

    Parameters
    ----------
    symbol : str
        Trading instrument.
    quantity : float
        Position size in lots.
    spread_pips : float
        Assumed spread.
    initial_capital : float
        Starting capital per backtest.
    weights : ObjectiveWeights, optional
        Composite objective weights.
    """

    def __init__(
        self,
        symbol: str = "UNKNOWN",
        quantity: float = 1.0,
        spread_pips: float = 0.5,
        initial_capital: float = 10_000.0,
        weights: Optional[ObjectiveWeights] = None,
    ) -> None:
        self.symbol = symbol
        self.quantity = quantity
        self.spread_pips = spread_pips
        self.initial_capital = initial_capital
        self.weights = weights
        self._config = _load_search_config()

    def run(
        self,
        strategy_class: Type[BaseStrategy],
        candle_df: pd.DataFrame,
        cost_model: CostModel,
        n_trials: Optional[int] = None,
        sampler: Optional[str] = None,
        pruner: Optional[str] = None,
        search_space: Optional[SearchSpace] = None,
        study_name: Optional[str] = None,
    ) -> OptimizationResult:
        """Run single-objective optimization.

        Parameters
        ----------
        strategy_class : Type[BaseStrategy]
            Strategy to optimize.
        candle_df : pd.DataFrame
            OHLC data with ``DatetimeIndex``.
        cost_model : CostModel
            Transaction cost model.
        n_trials : int, optional
            Number of trials.  Falls back to config then 500.
        sampler : str, optional
            Sampler name.  Falls back to config then ``"TPE"``.
        pruner : str, optional
            Pruner name.  Falls back to config then ``"MedianPruner"``.
        search_space : SearchSpace, optional
            Explicit search space.  If ``None``, built from strategy class.
        study_name : str, optional
            Optuna study name.  Defaults to ``"opt_{strategy_class_name}"``.

        Returns
        -------
        OptimizationResult
            Best params, best value, study, and all-trials DataFrame.
        """
        opt_cfg = self._config.get("search", {}).get("optimization", {})

        n_trials = n_trials or opt_cfg.get("n_trials", 500)
        sampler_name = sampler or opt_cfg.get("sampler", "TPE")
        pruner_name = pruner or opt_cfg.get("pruner", "MedianPruner")
        study_name = study_name or f"opt_{strategy_class.__name__}"

        if search_space is None:
            search_space = build_search_space(strategy_class)

        objective = Objective(
            strategy_class=strategy_class,
            search_space=search_space,
            candle_df=candle_df,
            cost_model=cost_model,
            initial_capital=self.initial_capital,
            weights=self.weights,
            symbol=self.symbol,
            quantity=self.quantity,
            spread_pips=self.spread_pips,
        )

        optuna.logging.set_verbosity(optuna.logging.WARNING)
        study = optuna.create_study(
            study_name=study_name,
            direction="maximize",
            sampler=_build_sampler(sampler_name),
            pruner=_build_pruner(pruner_name),
        )

        logger.info(
            "Starting optimization: %d trials, sampler=%s, pruner=%s",
            n_trials,
            sampler_name,
            pruner_name,
        )
        study.optimize(objective, n_trials=n_trials, show_progress_bar=False)

        best = study.best_trial
        logger.info(
            "Optimization complete. Best trial %d: value=%.4f params=%s",
            best.number,
            best.value,
            best.params,
        )

        return OptimizationResult(
            best_params=best.params,
            best_value=best.value,
            study=study,
            all_trials_df=_trials_to_dataframe(study),
        )

    def run_multi_objective(
        self,
        strategy_class: Type[BaseStrategy],
        candle_df: pd.DataFrame,
        cost_model: CostModel,
        n_trials: Optional[int] = None,
        sampler: Optional[str] = None,
        search_space: Optional[SearchSpace] = None,
        study_name: Optional[str] = None,
    ) -> optuna.Study:
        """Run multi-objective optimization (sharpe vs drawdown).

        Parameters
        ----------
        strategy_class : Type[BaseStrategy]
            Strategy to optimize.
        candle_df : pd.DataFrame
            OHLC data.
        cost_model : CostModel
            Cost model.
        n_trials : int, optional
            Number of trials.
        sampler : str, optional
            Sampler name (``"TPE"`` recommended for multi-objective).
        search_space : SearchSpace, optional
            Explicit search space.
        study_name : str, optional
            Optuna study name.

        Returns
        -------
        optuna.Study
            Study with Pareto-front trials accessible via
            ``study.best_trials``.
        """
        opt_cfg = self._config.get("search", {}).get("optimization", {})
        n_trials = n_trials or opt_cfg.get("n_trials", 500)
        sampler_name = sampler or opt_cfg.get("sampler", "TPE")
        study_name = study_name or f"mo_{strategy_class.__name__}"

        if search_space is None:
            search_space = build_search_space(strategy_class)

        objective = MultiObjective(
            strategy_class=strategy_class,
            search_space=search_space,
            candle_df=candle_df,
            cost_model=cost_model,
            initial_capital=self.initial_capital,
            symbol=self.symbol,
            quantity=self.quantity,
            spread_pips=self.spread_pips,
        )

        optuna.logging.set_verbosity(optuna.logging.WARNING)
        study = optuna.create_study(
            study_name=study_name,
            directions=["maximize", "minimize"],
            sampler=_build_sampler(sampler_name),
        )

        logger.info(
            "Starting multi-objective optimization: %d trials", n_trials
        )
        study.optimize(objective, n_trials=n_trials, show_progress_bar=False)
        logger.info(
            "Multi-objective complete. %d Pareto-optimal trials",
            len(study.best_trials),
        )
        return study
