"""Tests for strategy rule generation and param spaces."""

import numpy as np
import pandas as pd

from src.strategies.breakout_scalper import BreakoutScalper
from src.strategies.mean_reversion_scalper import MeanReversionScalper
from src.strategies.trend_pullback_scalper import TrendPullbackScalper


def _make_candle_df(n: int = 300) -> pd.DataFrame:
    rng = np.random.default_rng(42)
    close = 1.1 + np.cumsum(rng.normal(0, 0.0003, n))
    high = close + rng.uniform(0, 0.0005, n)
    low = close - rng.uniform(0, 0.0005, n)
    return pd.DataFrame(
        {
            "timestamp_utc": pd.date_range("2024-01-01", periods=n, freq="1min", tz="UTC"),
            "open": close + rng.normal(0, 0.0001, n),
            "high": high,
            "low": low,
            "close": close,
            "spread": np.full(n, 0.0001),
        }
    )


STRATEGIES = [MeanReversionScalper, BreakoutScalper, TrendPullbackScalper]


def test_param_space_is_dict():
    for cls in STRATEGIES:
        s = cls()
        space = s.get_param_space()
        assert isinstance(space, dict)
        assert len(space) > 0


def test_pine_script_rules_returned():
    for cls in STRATEGIES:
        s = cls()
        rules = s.get_pine_script_rules()
        assert isinstance(rules, dict)


def test_mql5_rules_returned():
    for cls in STRATEGIES:
        s = cls()
        rules = s.get_mql5_rules()
        assert isinstance(rules, dict)


def test_signal_generation():
    df = _make_candle_df(500)
    for cls in STRATEGIES:
        s = cls()
        signals = s.generate_signals(df)
        assert isinstance(signals, list)
