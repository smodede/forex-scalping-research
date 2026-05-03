"""Tests for tick-to-candle resampling."""

import numpy as np
import pandas as pd
import pytest

from src.data.resample import resample_ticks_to_candles


def _make_ticks(minutes: int = 5) -> pd.DataFrame:
    n = minutes * 60 * 10  # ~10 ticks per second
    ts = pd.date_range("2024-01-01", periods=n, freq="100ms", tz="UTC")
    rng = np.random.default_rng(0)
    bid = 1.1000 + np.cumsum(rng.normal(0, 0.00001, n))
    spread = np.full(n, 0.00010)
    ask = bid + spread
    mid = (bid + ask) / 2
    return pd.DataFrame(
        {
            "timestamp_utc": ts,
            "symbol": "EURUSD",
            "bid": bid,
            "ask": ask,
            "mid": mid,
            "spread": spread,
            "source": "test",
        }
    )


def test_resample_1m_shape():
    df = _make_ticks(5)
    candles = resample_ticks_to_candles(df, "1m")
    assert len(candles) == 5


def test_resample_ohlc_correct():
    df = _make_ticks(2)
    candles = resample_ticks_to_candles(df, "1m")
    first_min = df[df["timestamp_utc"] < "2024-01-01 00:01:00+00:00"]
    assert abs(candles.iloc[0]["bid_open"] - first_min["bid"].iloc[0]) < 1e-10
    assert abs(candles.iloc[0]["bid_high"] - first_min["bid"].max()) < 1e-10
    assert abs(candles.iloc[0]["bid_low"] - first_min["bid"].min()) < 1e-10


def test_resample_tick_count():
    df = _make_ticks(2)
    candles = resample_ticks_to_candles(df, "1m")
    assert candles["tick_count"].iloc[0] > 0


def test_resample_spread_stats():
    df = _make_ticks(2)
    candles = resample_ticks_to_candles(df, "1m")
    assert "spread_mean" in candles.columns
    assert "spread_median" in candles.columns
    assert candles["spread_mean"].iloc[0] > 0


def test_unsupported_timeframe():
    df = _make_ticks(2)
    with pytest.raises(ValueError):
        resample_ticks_to_candles(df, "2m")
