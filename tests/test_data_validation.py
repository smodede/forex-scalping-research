"""Tests for data validation utilities."""

import numpy as np
import pandas as pd

from src.data.validate import detect_gaps, validate_tick_dataframe


def _make_tick_df(n: int = 100) -> pd.DataFrame:
    ts = pd.date_range("2024-01-01", periods=n, freq="100ms", tz="UTC")
    rng = np.random.default_rng(42)
    bid = 1.1000 + rng.normal(0, 0.0001, n)
    spread = np.full(n, 0.0001)
    ask = bid + spread
    return pd.DataFrame(
        {
            "timestamp_utc": ts,
            "symbol": "EURUSD",
            "bid": bid,
            "ask": ask,
            "mid": (bid + ask) / 2,
            "spread": spread,
            "source": "test",
            "raw_file": "test.csv",
            "quality_flags": [[] for _ in range(n)],
        }
    )


def test_valid_tick_df_passes():
    df = _make_tick_df()
    errors = validate_tick_dataframe(df)
    assert errors == []


def test_missing_columns_detected():
    df = _make_tick_df().drop(columns=["bid"])
    errors = validate_tick_dataframe(df)
    assert any("missing" in e.lower() or "Missing" in e for e in errors)


def test_nan_values_detected():
    df = _make_tick_df()
    df.loc[5, "bid"] = np.nan
    errors = validate_tick_dataframe(df)
    assert any("nan" in e.lower() or "NaN" in e for e in errors)


def test_detect_gaps():
    df = _make_tick_df(50)
    df.loc[25:, "timestamp_utc"] = df.loc[25:, "timestamp_utc"] + pd.Timedelta(seconds=10)
    gaps = detect_gaps(df, max_gap_seconds=5)
    assert len(gaps) > 0
