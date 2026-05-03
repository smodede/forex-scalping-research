"""Strategy selection and validation gate checking."""
from __future__ import annotations

import logging
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Optional

import yaml

from src.backtest.metrics import BacktestMetrics
from src.optimization.robustness import (
    MonteCarloResult,
    PerturbationResult,
    StressResult,
)

logger = logging.getLogger(__name__)

_CONFIG_ROOT = Path(__file__).resolve().parents[2] / "config"


@dataclass
class GateResult:
    """Outcome of a single validation gate check.

    Attributes
    ----------
    passed : bool
        Whether the gate was passed.
    gate_name : str
        Human-readable gate identifier.
    details : dict[str, Any]
        Threshold values and actual values for transparency.
    """

    passed: bool
    gate_name: str
    details: dict[str, Any] = field(default_factory=dict)

    def __repr__(self) -> str:
        status = "PASS" if self.passed else "FAIL"
        return f"GateResult({status}: {self.gate_name})"


@dataclass
class SelectedStrategy:
    """A strategy that passed all validation gates.

    Attributes
    ----------
    strategy_id : str
        Unique identifier (typically class name).
    params : dict[str, Any]
        Optimized parameter set.
    metrics : BacktestMetrics
        Performance metrics from evaluation.
    gates_passed : list[str]
        Names of all gates that were passed.
    """

    strategy_id: str
    params: dict[str, Any]
    metrics: BacktestMetrics
    gates_passed: list[str] = field(default_factory=list)


class ValidationGates:
    """Load and apply validation gate thresholds.

    Thresholds are read from ``config/validation_gates.yaml``.  Each
    ``check_*`` method evaluates a specific gate and returns a
    ``GateResult``.

    Parameters
    ----------
    config_path : Path, optional
        Override path to the gates YAML file.
    """

    def __init__(self, config_path: Optional[Path] = None) -> None:
        path = config_path or (_CONFIG_ROOT / "validation_gates.yaml")
        self._config: dict[str, Any] = {}
        if path.exists():
            with open(path) as fh:
                raw = yaml.safe_load(fh) or {}
            self._config = raw.get("gates", {})
        else:
            logger.warning("Validation gates config not found at %s", path)

    @property
    def in_sample_config(self) -> dict[str, Any]:
        return self._config.get("in_sample", {})

    @property
    def oos_config(self) -> dict[str, Any]:
        return self._config.get("out_of_sample", {})

    @property
    def cross_source_config(self) -> dict[str, Any]:
        return self._config.get("cross_source", {})

    @property
    def robustness_config(self) -> dict[str, Any]:
        return self._config.get("robustness", {})

    # -----------------------------------------------------------------
    # In-sample gate
    # -----------------------------------------------------------------

    def check_in_sample(self, metrics: BacktestMetrics) -> GateResult:
        """Validate in-sample metrics against configured thresholds.

        Parameters
        ----------
        metrics : BacktestMetrics
            In-sample performance metrics.

        Returns
        -------
        GateResult
            Pass/fail with detail of each threshold check.
        """
        cfg = self.in_sample_config
        checks: dict[str, Any] = {}
        passed = True

        if "min_trades" in cfg:
            ok = metrics.total_trades >= cfg["min_trades"]
            checks["min_trades"] = {
                "required": cfg["min_trades"],
                "actual": metrics.total_trades,
                "passed": ok,
            }
            passed = passed and ok

        if "min_profit_factor" in cfg:
            ok = metrics.profit_factor >= cfg["min_profit_factor"]
            checks["min_profit_factor"] = {
                "required": cfg["min_profit_factor"],
                "actual": metrics.profit_factor,
                "passed": ok,
            }
            passed = passed and ok

        if "max_drawdown_pct" in cfg:
            ok = metrics.max_drawdown_pct <= cfg["max_drawdown_pct"]
            checks["max_drawdown_pct"] = {
                "required": cfg["max_drawdown_pct"],
                "actual": metrics.max_drawdown_pct,
                "passed": ok,
            }
            passed = passed and ok

        if "min_sharpe" in cfg:
            ok = metrics.sharpe_ratio >= cfg["min_sharpe"]
            checks["min_sharpe"] = {
                "required": cfg["min_sharpe"],
                "actual": metrics.sharpe_ratio,
                "passed": ok,
            }
            passed = passed and ok

        return GateResult(passed=passed, gate_name="in_sample", details=checks)

    # -----------------------------------------------------------------
    # Out-of-sample gate
    # -----------------------------------------------------------------

    def check_out_of_sample(
        self,
        metrics: BacktestMetrics,
        is_metrics: BacktestMetrics,
    ) -> GateResult:
        """Validate out-of-sample metrics, including retention vs in-sample.

        Parameters
        ----------
        metrics : BacktestMetrics
            Out-of-sample performance metrics.
        is_metrics : BacktestMetrics
            Corresponding in-sample metrics for retention check.

        Returns
        -------
        GateResult
            Pass/fail with detail of each threshold check.
        """
        cfg = self.oos_config
        checks: dict[str, Any] = {}
        passed = True

        if "min_trades" in cfg:
            ok = metrics.total_trades >= cfg["min_trades"]
            checks["min_trades"] = {
                "required": cfg["min_trades"],
                "actual": metrics.total_trades,
                "passed": ok,
            }
            passed = passed and ok

        if "min_profit_factor" in cfg:
            ok = metrics.profit_factor >= cfg["min_profit_factor"]
            checks["min_profit_factor"] = {
                "required": cfg["min_profit_factor"],
                "actual": metrics.profit_factor,
                "passed": ok,
            }
            passed = passed and ok

        if "max_drawdown_pct" in cfg:
            ok = metrics.max_drawdown_pct <= cfg["max_drawdown_pct"]
            checks["max_drawdown_pct"] = {
                "required": cfg["max_drawdown_pct"],
                "actual": metrics.max_drawdown_pct,
                "passed": ok,
            }
            passed = passed and ok

        if "min_sharpe" in cfg:
            ok = metrics.sharpe_ratio >= cfg["min_sharpe"]
            checks["min_sharpe"] = {
                "required": cfg["min_sharpe"],
                "actual": metrics.sharpe_ratio,
                "passed": ok,
            }
            passed = passed and ok

        if "min_retention_vs_is" in cfg:
            is_pf = is_metrics.profit_factor
            retention = metrics.profit_factor / is_pf if is_pf > 0 else 0.0
            ok = retention >= cfg["min_retention_vs_is"]
            checks["min_retention_vs_is"] = {
                "required": cfg["min_retention_vs_is"],
                "actual": retention,
                "passed": ok,
            }
            passed = passed and ok

        return GateResult(
            passed=passed, gate_name="out_of_sample", details=checks
        )

    # -----------------------------------------------------------------
    # Cross-source gate
    # -----------------------------------------------------------------

    def check_cross_source(
        self,
        metrics_a: BacktestMetrics,
        metrics_b: BacktestMetrics,
    ) -> GateResult:
        """Compare metrics across two data sources for consistency.

        Parameters
        ----------
        metrics_a : BacktestMetrics
            Metrics from first data source.
        metrics_b : BacktestMetrics
            Metrics from second data source.

        Returns
        -------
        GateResult
            Pass/fail based on deviation and profit factor thresholds.
        """
        cfg = self.cross_source_config
        checks: dict[str, Any] = {}
        passed = True

        if "max_metric_deviation_pct" in cfg:
            max_dev = cfg["max_metric_deviation_pct"]
            comparisons = {
                "sharpe_ratio": (metrics_a.sharpe_ratio, metrics_b.sharpe_ratio),
                "profit_factor": (metrics_a.profit_factor, metrics_b.profit_factor),
                "win_rate": (metrics_a.win_rate, metrics_b.win_rate),
            }
            deviations: dict[str, float] = {}
            all_ok = True
            for name, (va, vb) in comparisons.items():
                avg = (abs(va) + abs(vb)) / 2
                dev = abs(va - vb) / avg * 100 if avg > 0 else 0.0
                deviations[name] = dev
                if dev > max_dev:
                    all_ok = False

            checks["max_metric_deviation_pct"] = {
                "required": max_dev,
                "deviations": deviations,
                "passed": all_ok,
            }
            passed = passed and all_ok

        if "min_profit_factor" in cfg:
            min_pf = cfg["min_profit_factor"]
            ok = (
                metrics_a.profit_factor >= min_pf
                and metrics_b.profit_factor >= min_pf
            )
            checks["min_profit_factor"] = {
                "required": min_pf,
                "source_a": metrics_a.profit_factor,
                "source_b": metrics_b.profit_factor,
                "passed": ok,
            }
            passed = passed and ok

        return GateResult(
            passed=passed, gate_name="cross_source", details=checks
        )

    # -----------------------------------------------------------------
    # Robustness gate
    # -----------------------------------------------------------------

    def check_robustness(
        self,
        mc_result: MonteCarloResult,
        perturb_result: PerturbationResult,
        stress_result: StressResult,
    ) -> GateResult:
        """Validate robustness test results.

        Parameters
        ----------
        mc_result : MonteCarloResult
            Monte Carlo equity simulation result.
        perturb_result : PerturbationResult
            Parameter perturbation test result.
        stress_result : StressResult
            Cost stress test result.

        Returns
        -------
        GateResult
            Aggregated pass/fail across all robustness checks.
        """
        checks: dict[str, Any] = {
            "monte_carlo": {
                "passed": mc_result.passed,
                "profitable_pct": mc_result.profitable_pct,
            },
            "param_perturbation": {
                "passed": perturb_result.passed,
                "max_drop_pct": perturb_result.max_drop_pct,
            },
            "cost_stress": {
                "passed": stress_result.passed,
                "still_profitable": stress_result.still_profitable,
                "pf_retained": stress_result.profit_factor_retained,
            },
        }

        passed = mc_result.passed and perturb_result.passed and stress_result.passed

        return GateResult(
            passed=passed, gate_name="robustness", details=checks
        )


def select_best_strategy(
    candidates: list[dict[str, Any]],
) -> Optional[SelectedStrategy]:
    """Select the best strategy from validated candidates.

    Each candidate dict must contain:

    - ``strategy_id`` (str)
    - ``params`` (dict)
    - ``metrics`` (BacktestMetrics)
    - ``gate_results`` (list[GateResult])

    Only candidates that pass **all** gates are considered.  Among
    passing candidates, the one with the highest composite score
    (sharpe × profit_factor) is selected.

    Parameters
    ----------
    candidates : list[dict[str, Any]]
        List of candidate dicts.

    Returns
    -------
    SelectedStrategy or None
        The best passing candidate, or ``None`` if no candidate passes
        all gates.
    """
    passing: list[dict[str, Any]] = []
    for c in candidates:
        gate_results: list[GateResult] = c.get("gate_results", [])
        if all(gr.passed for gr in gate_results):
            passing.append(c)

    if not passing:
        logger.warning("No candidates passed all validation gates")
        return None

    # Rank by composite: sharpe * profit_factor
    def _score(c: dict[str, Any]) -> float:
        m: BacktestMetrics = c["metrics"]
        return m.sharpe_ratio * m.profit_factor

    best = max(passing, key=_score)
    gate_names = [gr.gate_name for gr in best.get("gate_results", [])]

    logger.info(
        "Selected strategy: %s (score=%.4f)",
        best["strategy_id"],
        _score(best),
    )

    return SelectedStrategy(
        strategy_id=best["strategy_id"],
        params=best["params"],
        metrics=best["metrics"],
        gates_passed=gate_names,
    )
