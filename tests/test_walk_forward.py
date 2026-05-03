"""Tests for walk-forward analysis splits."""

import numpy as np
import pandas as pd

from src.backtest.walk_forward import generate_splits


def _make_df(n: int = 1000) -> pd.DataFrame:
    return pd.DataFrame(
        {
            "timestamp_utc": pd.date_range("2024-01-01", periods=n, freq="1min"),
            "mid_close": 1.1 + np.cumsum(np.random.default_rng(0).normal(0, 0.0001, n)),
        }
    )


def test_generates_correct_number_of_splits():
    df = _make_df()
    splits = generate_splits(df, n_splits=5, train_ratio=0.7, gap_bars=10)
    assert len(splits) == 5


def test_splits_dont_overlap():
    df = _make_df()
    splits = generate_splits(df, n_splits=3, train_ratio=0.7, gap_bars=10)
    for s in splits:
        assert s.train_end < s.test_start


def test_gap_between_train_test():
    df = _make_df(2000)
    splits = generate_splits(df, n_splits=3, train_ratio=0.7, gap_bars=50)
    for s in splits:
        gap = s.test_start - s.train_end
        assert gap >= 50
