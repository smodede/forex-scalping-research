"""TradingView vs backtest trade reconciliation."""
from __future__ import annotations

import json
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Optional

import numpy as np
import pandas as pd


@dataclass
class ReconciliationReport:
    """Summary of a reconciliation run."""

    total_expected: int
    total_actual: int
    matched: int
    unmatched_expected: int
    unmatched_actual: int
    pnl_correlation: float
    max_pnl_deviation: float
    avg_pnl_deviation: float
    pass_fail: str


def load_pine_trades(csv_path: Path) -> pd.DataFrame:
    """Load TradingView Pine Script trade export.

    Parameters
    ----------
    csv_path : Path
        Path to the CSV file exported from TradingView.

    Returns
    -------
    pd.DataFrame
        DataFrame with columns normalised to ``symbol``, ``direction``,
        ``entry_price``, ``exit_price``, ``pnl``, ``entry_bar``,
        ``exit_bar``.
    """
    df = pd.read_csv(csv_path)

    column_map = {
        "Symbol": "symbol",
        "Direction": "direction",
        "Entry Price": "entry_price",
        "Exit Price": "exit_price",
        "Profit": "pnl",
        "Entry Bar": "entry_bar",
        "Exit Bar": "exit_bar",
    }
    rename = {k: v for k, v in column_map.items() if k in df.columns}
    df = df.rename(columns=rename)

    # Ensure lowercase column names for any remaining columns
    df.columns = [c.lower().replace(" ", "_") for c in df.columns]
    return df


def load_expected_trades(manifest_path: Path) -> pd.DataFrame:
    """Load expected trades from a reconciliation manifest.

    Parameters
    ----------
    manifest_path : Path
        Path to a JSON manifest file produced by the backtest pipeline.

    Returns
    -------
    pd.DataFrame
        DataFrame with at least ``symbol``, ``direction``,
        ``entry_price``, ``exit_price``, ``pnl``, ``entry_bar``,
        ``exit_bar``.
    """
    with open(manifest_path) as fh:
        data = json.load(fh)

    trades = data.get("trades", data) if isinstance(data, dict) else data
    df = pd.DataFrame(trades)
    df.columns = [c.lower().replace(" ", "_") for c in df.columns]
    return df


def reconcile(
    expected_df: pd.DataFrame,
    actual_df: pd.DataFrame,
    tolerance_pips: float = 2.0,
    tolerance_bars: int = 1,
) -> ReconciliationReport:
    """Compare expected and actual trades to find matches and deviations.

    Parameters
    ----------
    expected_df : pd.DataFrame
        Trades from the backtest manifest.
    actual_df : pd.DataFrame
        Trades from TradingView export.
    tolerance_pips : float
        Maximum price difference (in pips) to consider a match.
    tolerance_bars : int
        Maximum bar index difference to consider a match.

    Returns
    -------
    ReconciliationReport
        Reconciliation summary.
    """
    matched_idx_expected: set[int] = set()
    matched_idx_actual: set[int] = set()
    pnl_deviations: list[float] = []

    for i, exp in expected_df.iterrows():
        for j, act in actual_df.iterrows():
            if j in matched_idx_actual:
                continue
            if exp.get("symbol") != act.get("symbol"):
                continue
            if exp.get("direction") != act.get("direction"):
                continue

            entry_diff = abs(float(exp.get("entry_price", 0)) - float(act.get("entry_price", 0)))
            bar_diff = abs(int(exp.get("entry_bar", 0)) - int(act.get("entry_bar", 0)))

            if entry_diff <= tolerance_pips * 0.0001 and bar_diff <= tolerance_bars:
                matched_idx_expected.add(int(i))
                matched_idx_actual.add(int(j))
                dev = abs(float(exp.get("pnl", 0)) - float(act.get("pnl", 0)))
                pnl_deviations.append(dev)
                break

    matched = len(matched_idx_expected)
    unmatched_expected = len(expected_df) - matched
    unmatched_actual = len(actual_df) - matched

    if pnl_deviations:
        max_dev = float(np.max(pnl_deviations))
        avg_dev = float(np.mean(pnl_deviations))
    else:
        max_dev = 0.0
        avg_dev = 0.0

    # Compute PnL correlation if sufficient data
    if matched >= 2 and "pnl" in expected_df.columns and "pnl" in actual_df.columns:
        exp_pnl = expected_df.loc[list(matched_idx_expected), "pnl"].astype(float).values
        act_pnl = actual_df.loc[list(matched_idx_actual), "pnl"].astype(float).values
        if np.std(exp_pnl) > 0 and np.std(act_pnl) > 0:
            corr = float(np.corrcoef(exp_pnl, act_pnl)[0, 1])
        else:
            corr = 0.0
    else:
        corr = 0.0

    total_expected = len(expected_df)
    total_actual = len(actual_df)
    match_rate = matched / max(total_expected, 1)
    pass_fail = "PASS" if match_rate >= 0.8 and avg_dev < 5.0 else "FAIL"

    return ReconciliationReport(
        total_expected=total_expected,
        total_actual=total_actual,
        matched=matched,
        unmatched_expected=unmatched_expected,
        unmatched_actual=unmatched_actual,
        pnl_correlation=corr,
        max_pnl_deviation=max_dev,
        avg_pnl_deviation=avg_dev,
        pass_fail=pass_fail,
    )


def generate_report(recon: ReconciliationReport, output_path: Path) -> Path:
    """Write a reconciliation report to disk.

    Parameters
    ----------
    recon : ReconciliationReport
        The reconciliation results.
    output_path : Path
        Destination file path (JSON).

    Returns
    -------
    Path
        The path the report was written to.
    """
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "w") as fh:
        json.dump(asdict(recon), fh, indent=2)
    return output_path
