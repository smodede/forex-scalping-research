"""Robustness testing: Monte Carlo, parameter perturbation, cost stress."""
from __future__ import annotations

import logging
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Optional, Type

import numpy as np
import pandas as pd
import yaml

from src.backtest.costs import CostModel
from src.backtest.engine import BacktestEngine, BacktestResult
from src.backtest.metrics import BacktestMetrics
from src.backtest.trade_log import TradeLog
from src.strategies.base import BaseStrategy, StrategyParams

logger = logging.getLogger(__name__)

_CONFIG_ROOT = Path(__file__).resolve().parents[2] / "config"


def _load_robustness_config() -> dict[str, Any]:
    """Load robustness thresholds from config files."""
    gates: dict[str, Any] = {}

    vg_path = _CONFIG_ROOT / "validation_gates.yaml"
    if vg_path.exists():
        with open(vg_path) as fh:
            raw = yaml.safe_load(fh) or {}
        gates.update(raw.get("gates", {}).get("robustness", {}))

    ss_path = _CONFIG_ROOT / "strategy_search.yaml"
    if ss_path.exists():
        with open(ss_path) as fh:
            raw = yaml.safe_load(fh) or {}
        gates.update(raw.get("search", {}).get("robustness", {}))

    return gates


# ---------------------------------------------------------------------------
# Monte Carlo equity simulation
# ---------------------------------------------------------------------------


@dataclass
class MonteCarloResult:
    """Results from Monte Carlo trade-order randomisation.

    Attributes
    ----------
    median_final_equity : float
        Median final equity across all runs.
    percentile_5_equity : float
        5th-percentile final equity (worst realistic case).
    percentile_95_equity : float
        95th-percentile final equity.
    median_max_drawdown : float
        Median max drawdown across runs.
    percentile_95_drawdown : float
        95th-percentile max drawdown (worst realistic case).
    profitable_pct : float
        Percentage of runs that ended profitably.
    passed : bool
        Whether the result meets configured robustness thresholds.
    details : dict[str, Any]
        Threshold checks with values.
    """

    median_final_equity: float
    percentile_5_equity: float
    percentile_95_equity: float
    median_max_drawdown: float
    percentile_95_drawdown: float
    profitable_pct: float
    passed: bool
    details: dict[str, Any] = field(default_factory=dict)


def monte_carlo_equity(
    trade_log: TradeLog,
    n_runs: int = 1000,
    initial_capital: float = 10_000.0,
) -> MonteCarloResult:
    """Randomise trade order and compute equity distribution.

    Shuffles the order of completed trades ``n_runs`` times to assess
    how sensitive the equity curve is to trade sequencing.

    Parameters
    ----------
    trade_log : TradeLog
        Completed trades from a backtest.
    n_runs : int
        Number of random permutations.
    initial_capital : float
        Starting capital.

    Returns
    -------
    MonteCarloResult
        Distribution statistics and pass/fail assessment.
    """
    cfg = _load_robustness_config()
    pnls = np.array([t.pnl_net for t in trade_log.trades])
    n_trades = len(pnls)

    if n_trades == 0:
        return MonteCarloResult(
            median_final_equity=initial_capital,
            percentile_5_equity=initial_capital,
            percentile_95_equity=initial_capital,
            median_max_drawdown=0.0,
            percentile_95_drawdown=0.0,
            profitable_pct=0.0,
            passed=False,
            details={"error": "No trades to simulate"},
        )

    rng = np.random.default_rng(seed=42)
    final_equities = np.empty(n_runs)
    max_drawdowns = np.empty(n_runs)

    for i in range(n_runs):
        shuffled = rng.permutation(pnls)
        equity = initial_capital + np.cumsum(shuffled)
        equity = np.insert(equity, 0, initial_capital)

        final_equities[i] = equity[-1]

        peak = np.maximum.accumulate(equity)
        dd = (equity - peak) / np.where(peak > 0, peak, 1.0)
        max_drawdowns[i] = abs(float(dd.min())) * 100  # percent

    median_equity = float(np.median(final_equities))
    p5_equity = float(np.percentile(final_equities, 5))
    p95_equity = float(np.percentile(final_equities, 95))
    median_dd = float(np.median(max_drawdowns))
    p95_dd = float(np.percentile(max_drawdowns, 95))
    profitable_pct = float(np.mean(final_equities > initial_capital) * 100)

    # Pass/fail check
    min_profitable = cfg.get("min_profitable_mc_pct", 80)
    confidence = cfg.get("monte_carlo_confidence", 0.95)

    passed = profitable_pct >= min_profitable
    details = {
        "profitable_pct": profitable_pct,
        "min_profitable_pct": min_profitable,
        "confidence": confidence,
        "n_runs": n_runs,
    }

    return MonteCarloResult(
        median_final_equity=median_equity,
        percentile_5_equity=p5_equity,
        percentile_95_equity=p95_equity,
        median_max_drawdown=median_dd,
        percentile_95_drawdown=p95_dd,
        profitable_pct=profitable_pct,
        passed=passed,
        details=details,
    )


# ---------------------------------------------------------------------------
# Parameter perturbation
# ---------------------------------------------------------------------------


@dataclass
class PerturbationResult:
    """Results from parameter perturbation testing.

    Attributes
    ----------
    base_score : float
        Composite score with the original parameters.
    perturbed_scores : list[float]
        Scores from perturbed parameter sets.
    mean_score : float
        Mean of perturbed scores.
    min_score : float
        Worst perturbed score.
    max_drop_pct : float
        Maximum percentage drop from base score.
    passed : bool
        Whether parameter sensitivity is within acceptable bounds.
    details : dict[str, Any]
        Threshold checks.
    """

    base_score: float
    perturbed_scores: list[float]
    mean_score: float
    min_score: float
    max_drop_pct: float
    passed: bool
    details: dict[str, Any] = field(default_factory=dict)


def param_perturbation(
    strategy_class: Type[BaseStrategy],
    best_params: dict[str, Any],
    candle_df: pd.DataFrame,
    cost_model: CostModel,
    perturbation_pct: float = 10.0,
    n_samples: int = 20,
    initial_capital: float = 10_000.0,
    symbol: str = "UNKNOWN",
    quantity: float = 1.0,
    spread_pips: float = 0.5,
) -> PerturbationResult:
    """Test parameter sensitivity by perturbing best params.

    Each numeric parameter is randomly varied within
    ``±perturbation_pct`` percent of its value.  Non-numeric parameters
    are left unchanged.

    Parameters
    ----------
    strategy_class : Type[BaseStrategy]
        Strategy class.
    best_params : dict[str, Any]
        Optimized parameter set.
    candle_df : pd.DataFrame
        OHLC data.
    cost_model : CostModel
        Cost model.
    perturbation_pct : float
        Maximum perturbation as a percentage (e.g. 10 = ±10 %).
    n_samples : int
        Number of perturbed evaluations.
    initial_capital : float
        Starting capital.
    symbol : str
        Instrument.
    quantity : float
        Position size.
    spread_pips : float
        Assumed spread.

    Returns
    -------
    PerturbationResult
        Stability assessment of the parameter neighbourhood.
    """
    from src.optimization.objective import composite_objective

    cfg = _load_robustness_config()
    engine = BacktestEngine(symbol=symbol, quantity=quantity, spread_pips=spread_pips)

    # Base evaluation
    base_strat = strategy_class(
        StrategyParams(name=strategy_class.__name__, params=best_params)
    )
    base_result = engine.run(base_strat, candle_df, cost_model, initial_capital)
    base_score = composite_objective(base_result.metrics)

    rng = np.random.default_rng(seed=123)
    perturbed_scores: list[float] = []
    frac = perturbation_pct / 100.0

    for _ in range(n_samples):
        new_params: dict[str, Any] = {}
        for k, v in best_params.items():
            if isinstance(v, (int, float)):
                delta = v * frac * rng.uniform(-1.0, 1.0)
                new_val = v + delta
                new_params[k] = type(v)(round(new_val)) if isinstance(v, int) else new_val
            else:
                new_params[k] = v

        strat = strategy_class(
            StrategyParams(name=strategy_class.__name__, params=new_params)
        )
        result = engine.run(strat, candle_df, cost_model, initial_capital)
        perturbed_scores.append(composite_objective(result.metrics))

    mean_score = float(np.mean(perturbed_scores))
    min_score = float(np.min(perturbed_scores)) if perturbed_scores else base_score

    if base_score > 0:
        max_drop_pct = max(0.0, (base_score - min_score) / base_score * 100)
    else:
        max_drop_pct = 0.0

    max_allowed_drop = cfg.get("param_sensitivity_max_drop_pct", 30)
    passed = max_drop_pct <= max_allowed_drop

    return PerturbationResult(
        base_score=base_score,
        perturbed_scores=perturbed_scores,
        mean_score=mean_score,
        min_score=min_score,
        max_drop_pct=max_drop_pct,
        passed=passed,
        details={
            "max_drop_pct": max_drop_pct,
            "max_allowed_drop_pct": max_allowed_drop,
            "perturbation_pct": perturbation_pct,
            "n_samples": n_samples,
        },
    )


# ---------------------------------------------------------------------------
# Cost stress testing
# ---------------------------------------------------------------------------


@dataclass
class StressResult:
    """Results from cost stress testing.

    Attributes
    ----------
    base_metrics : BacktestMetrics
        Metrics with normal costs.
    stressed_metrics : BacktestMetrics
        Metrics with inflated costs.
    profit_factor_retained : float
        Fraction of base profit factor retained under stress.
    still_profitable : bool
        Whether the strategy remains profitable under stress.
    passed : bool
        Overall pass/fail.
    details : dict[str, Any]
        Comparison details.
    """

    base_metrics: BacktestMetrics
    stressed_metrics: BacktestMetrics
    profit_factor_retained: float
    still_profitable: bool
    passed: bool
    details: dict[str, Any] = field(default_factory=dict)


def stress_test_costs(
    strategy_class: Type[BaseStrategy],
    best_params: dict[str, Any],
    candle_df: pd.DataFrame,
    cost_model: CostModel,
    spread_mult: float = 1.5,
    slippage_mult: float = 2.0,
    initial_capital: float = 10_000.0,
    symbol: str = "UNKNOWN",
    quantity: float = 1.0,
    spread_pips: float = 0.5,
) -> StressResult:
    """Run the strategy with inflated transaction costs.

    Parameters
    ----------
    strategy_class : Type[BaseStrategy]
        Strategy class.
    best_params : dict[str, Any]
        Optimized parameters.
    candle_df : pd.DataFrame
        OHLC data.
    cost_model : CostModel
        Base cost model (will be inflated).
    spread_mult : float
        Multiplier for max_spread_pips.
    slippage_mult : float
        Multiplier for slippage_pips.
    initial_capital : float
        Starting capital.
    symbol : str
        Instrument.
    quantity : float
        Position size.
    spread_pips : float
        Base assumed spread.

    Returns
    -------
    StressResult
        Comparison of normal vs. stressed performance.
    """
    cfg = _load_robustness_config()
    engine = BacktestEngine(symbol=symbol, quantity=quantity, spread_pips=spread_pips)

    strat = strategy_class(
        StrategyParams(name=strategy_class.__name__, params=best_params)
    )

    # Base run
    base_result = engine.run(strat, candle_df, cost_model, initial_capital)

    # Stressed run
    stressed_cost = CostModel(
        commission_per_lot=cost_model.commission_per_lot,
        slippage_pips=cost_model.slippage_pips * slippage_mult,
        pip_value=cost_model.pip_value,
        max_spread_pips=cost_model.max_spread_pips * spread_mult,
    )
    stressed_engine = BacktestEngine(
        symbol=symbol,
        quantity=quantity,
        spread_pips=spread_pips * spread_mult,
    )
    stressed_strat = strategy_class(
        StrategyParams(name=strategy_class.__name__, params=best_params)
    )
    stressed_result = stressed_engine.run(
        stressed_strat, candle_df, stressed_cost, initial_capital
    )

    base_pf = base_result.metrics.profit_factor
    stressed_pf = stressed_result.metrics.profit_factor
    retained = stressed_pf / base_pf if base_pf > 0 else 0.0
    still_profitable = stressed_result.metrics.total_pnl > 0

    passed = still_profitable and retained > 0.5

    return StressResult(
        base_metrics=base_result.metrics,
        stressed_metrics=stressed_result.metrics,
        profit_factor_retained=retained,
        still_profitable=still_profitable,
        passed=passed,
        details={
            "spread_mult": spread_mult,
            "slippage_mult": slippage_mult,
            "base_pf": base_pf,
            "stressed_pf": stressed_pf,
            "retained_pct": retained * 100,
        },
    )
