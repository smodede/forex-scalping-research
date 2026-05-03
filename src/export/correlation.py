"""Correlation report between expected and actual trade results."""
from __future__ import annotations

import json
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd

from src.backtest.trade_log import TradeLog
from src.strategies.base import StrategyParams


@dataclass
class CorrelationReport:
    """Summary of how well actual trades match expected trades."""

    matched_count: int
    unmatched_expected: int
    unmatched_actual: int
    pnl_deviation: float
    correlation_pct: float


class CorrelationManifest:
    """Build and persist a correlation manifest for reconciliation."""

    def generate(
        self,
        trade_log: TradeLog,
        strategy_params: StrategyParams,
        tolerance_pips: float = 1.0,
        tolerance_bars: int = 1,
    ) -> dict[str, Any]:
        """Create a manifest dict describing the trade log and parameters."""
        df = trade_log.to_dataframe()
        manifest: dict[str, Any] = {
            "strategy_name": strategy_params.name,
            "params": strategy_params.params,
            "total_trades": trade_log.total_trades,
            "winning_trades": trade_log.winning_trades,
            "losing_trades": trade_log.losing_trades,
            "tolerance_pips": tolerance_pips,
            "tolerance_bars": tolerance_bars,
        }
        if not df.empty:
            manifest["first_trade_time"] = str(df["entry_time"].min())
            manifest["last_trade_time"] = str(df["exit_time"].max())
            manifest["total_pnl"] = float(df["pnl_net"].sum())
        return manifest

    def save_manifest(self, manifest: dict[str, Any], output_dir: str) -> Path:
        """Persist the manifest as JSON."""
        out = Path(output_dir)
        out.mkdir(parents=True, exist_ok=True)
        path = out / "correlation_manifest.json"
        path.write_text(json.dumps(manifest, indent=2, default=str), encoding="utf-8")
        return path


def compare_trades(
    expected_df: pd.DataFrame,
    actual_df: pd.DataFrame,
    tolerance_pips: float = 1.0,
    tolerance_bars: int = 1,
) -> CorrelationReport:
    """Compare expected vs actual trade DataFrames and produce a report.

    Matching criteria:
    - Same direction
    - Entry price within *tolerance_pips* pips (0.0001 per pip)
    - Entry time within *tolerance_bars* bars (each bar = 60 s by default)
    """
    pip = 0.0001
    bar_seconds = 60  # default bar duration for tolerance

    matched = 0
    used_actual: set[int] = set()

    for _, exp in expected_df.iterrows():
        for idx, act in actual_df.iterrows():
            if idx in used_actual:
                continue
            if exp["direction"] != act["direction"]:
                continue
            price_diff = abs(exp["entry_price"] - act["entry_price"])
            if price_diff > tolerance_pips * pip:
                continue
            time_diff = abs(
                (pd.Timestamp(exp["entry_time"]) - pd.Timestamp(act["entry_time"])).total_seconds()
            )
            if time_diff > tolerance_bars * bar_seconds:
                continue
            matched += 1
            used_actual.add(idx)
            break

    unmatched_expected = len(expected_df) - matched
    unmatched_actual = len(actual_df) - len(used_actual)

    # PnL deviation
    expected_pnl = expected_df["pnl_net"].sum() if "pnl_net" in expected_df.columns else 0.0
    actual_pnl = actual_df["pnl_net"].sum() if "pnl_net" in actual_df.columns else 0.0
    pnl_deviation = abs(expected_pnl - actual_pnl)

    total = max(len(expected_df), len(actual_df), 1)
    correlation_pct = (matched / total) * 100.0

    return CorrelationReport(
        matched_count=matched,
        unmatched_expected=unmatched_expected,
        unmatched_actual=unmatched_actual,
        pnl_deviation=pnl_deviation,
        correlation_pct=correlation_pct,
    )
