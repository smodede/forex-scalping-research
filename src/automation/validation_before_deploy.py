"""Pre-deployment validation checks."""
from __future__ import annotations

import logging
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Optional

import yaml

from src.backtest.metrics import BacktestMetrics

logger = logging.getLogger(__name__)

_CONFIG_ROOT = Path(__file__).resolve().parents[2] / "config"


@dataclass
class PreDeployResult:
    """Outcome of pre-deployment validation."""

    ready_to_deploy: bool
    checks_passed: list[str] = field(default_factory=list)
    checks_failed: list[str] = field(default_factory=list)
    recommendation: str = ""


class PreDeployValidator:
    """Validate a strategy against pre-deploy gate thresholds.

    Loads thresholds from ``config/validation_gates.yaml`` at
    construction time.
    """

    def __init__(self, config_path: Path | None = None) -> None:
        path = config_path or (_CONFIG_ROOT / "validation_gates.yaml")
        with open(path) as fh:
            raw = yaml.safe_load(fh)
        self._gates: dict[str, Any] = raw.get("gates", {})
        self._pre_deploy: dict[str, Any] = self._gates.get("pre_deploy", {})

    def validate(
        self,
        strategy_id: str,
        gates_results: dict[str, bool],
        paper_days: int,
        paper_metrics: dict[str, float],
        backtest_metrics: BacktestMetrics,
    ) -> PreDeployResult:
        """Run all pre-deployment checks.

        Parameters
        ----------
        strategy_id : str
            Identifier for the strategy being validated.
        gates_results : dict[str, bool]
            Pass/fail results from earlier validation gates
            (in_sample, out_of_sample, cross_source, robustness).
        paper_days : int
            Number of paper trading days completed.
        paper_metrics : dict[str, float]
            Performance metrics from paper trading.
        backtest_metrics : BacktestMetrics
            Metrics from the backtest run.

        Returns
        -------
        PreDeployResult
            Aggregated validation result with recommendation.
        """
        passed: list[str] = []
        failed: list[str] = []

        # Check that all prior gates passed
        require_all = self._pre_deploy.get("require_all_gates_passed", True)
        if require_all:
            all_passed = all(gates_results.values())
            if all_passed:
                passed.append("all_gates_passed")
            else:
                failing = [g for g, ok in gates_results.items() if not ok]
                failed.append(f"gates_not_passed: {', '.join(failing)}")

        # Check paper trading duration
        min_paper_days = self._pre_deploy.get("require_paper_trading_days", 5)
        if paper_days >= min_paper_days:
            passed.append(f"paper_days>={min_paper_days}")
        else:
            failed.append(f"paper_days={paper_days}<{min_paper_days}")

        # Check paper vs backtest deviation
        max_dev = self._pre_deploy.get("max_paper_vs_backtest_deviation_pct", 30)
        paper_pf = paper_metrics.get("profit_factor", 0.0)
        bt_pf = backtest_metrics.profit_factor
        if bt_pf > 0:
            deviation_pct = abs(paper_pf - bt_pf) / bt_pf * 100
        else:
            deviation_pct = 100.0 if paper_pf != 0 else 0.0

        if deviation_pct <= max_dev:
            passed.append(f"pf_deviation={deviation_pct:.1f}%<={max_dev}%")
        else:
            failed.append(f"pf_deviation={deviation_pct:.1f}%>{max_dev}%")

        ready = len(failed) == 0
        if ready:
            recommendation = f"Strategy {strategy_id} is ready for deployment."
        else:
            recommendation = (
                f"Strategy {strategy_id} is NOT ready. "
                f"Fix: {'; '.join(failed)}"
            )

        logger.info(
            "PreDeploy %s: ready=%s passed=%d failed=%d",
            strategy_id,
            ready,
            len(passed),
            len(failed),
        )
        return PreDeployResult(
            ready_to_deploy=ready,
            checks_passed=passed,
            checks_failed=failed,
            recommendation=recommendation,
        )
