"""Tests for TradingView trade reconciliation."""

import pandas as pd

from src.reconciliation.tradingview_compare import reconcile


def _expected_df() -> pd.DataFrame:
    return pd.DataFrame({
        "entry_time": pd.to_datetime(["2024-01-01 10:00", "2024-01-01 11:00"]),
        "direction": ["long", "short"],
        "entry_price": [1.10000, 1.10100],
        "exit_price": [1.10050, 1.10050],
        "pnl_net": [42.0, 42.0],
    })


def _actual_df_matching() -> pd.DataFrame:
    return pd.DataFrame({
        "entry_time": pd.to_datetime(["2024-01-01 10:00", "2024-01-01 11:00"]),
        "direction": ["long", "short"],
        "entry_price": [1.10001, 1.10099],
        "exit_price": [1.10049, 1.10051],
        "pnl_net": [41.0, 43.0],
    })


def _actual_df_mismatched() -> pd.DataFrame:
    return pd.DataFrame({
        "entry_time": pd.to_datetime(["2024-01-01 14:00"]),
        "direction": ["long"],
        "entry_price": [1.12000],
        "exit_price": [1.12050],
        "pnl_net": [50.0],
    })


def test_reconcile_matching_trades():
    report = reconcile(_expected_df(), _actual_df_matching(), tolerance_pips=2.0, tolerance_bars=5)
    assert report.matched >= 1


def test_reconcile_mismatched_trades():
    report = reconcile(_expected_df(), _actual_df_mismatched(), tolerance_pips=1.0, tolerance_bars=2)
    assert report.unmatched_expected > 0 or report.matched < 2
