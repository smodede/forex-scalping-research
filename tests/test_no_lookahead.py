"""Tests for no-lookahead guarantee in strategy signals."""

import numpy as np
import pandas as pd

from src.strategies.base import StrategyParams
from src.strategies.mean_reversion_scalper import MeanReversionScalper


def _make_candle_df(n: int = 200) -> pd.DataFrame:
    ts = pd.date_range("2024-01-01", periods=n, freq="1min", tz="UTC")
    rng = np.random.default_rng(42)
    close = 1.1000 + np.cumsum(rng.normal(0, 0.0003, n))
    high = close + rng.uniform(0, 0.0005, n)
    low = close - rng.uniform(0, 0.0005, n)
    opn = close + rng.normal(0, 0.0001, n)
    return pd.DataFrame(
        {
            "timestamp_utc": ts,
            "open": opn,
            "high": high,
            "low": low,
            "close": close,
            "spread": np.full(n, 0.0001),
        }
    )


def test_signals_do_not_use_future_data():
    df = _make_candle_df(500)
    params = StrategyParams(
        name="mean_reversion_scalper",
        params={
            "bb_period": 20, "bb_std": 2.0, "rsi_period": 14,
            "rsi_oversold": 30, "rsi_overbought": 70,
            "atr_period": 14, "sl_atr_mult": 1.5, "tp_atr_mult": 1.0,
            "max_spread_pips": 20.0,
        },
    )
    strategy = MeanReversionScalper(params)
    signals = strategy.generate_signals(df)
    assert strategy.validate_no_lookahead(df, signals)


def test_signal_timestamps_before_last_bar():
    df = _make_candle_df(500)
    strategy = MeanReversionScalper()
    signals = strategy.generate_signals(df)
    last_ts = df["timestamp_utc"].iloc[-1]
    for sig in signals:
        assert sig.timestamp <= last_ts
