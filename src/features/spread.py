"""Spread analysis features for forex scalping."""

from __future__ import annotations

import numpy as np
import pandas as pd

from src.features.indicators import atr as _atr


def spread_percentile(df: pd.DataFrame, lookback: int = 100) -> pd.Series:
    """Current spread as a percentile of recent spread values.

    Parameters
    ----------
    df : pd.DataFrame
        Must contain a ``spread`` column.
    lookback : int, optional
        Rolling window for percentile calculation, by default 100.

    Returns
    -------
    pd.Series
        Percentile values in [0, 100].
    """
    spread = df["spread"]

    def _pct(window: np.ndarray) -> float:
        current = window[-1]
        return float(np.sum(window <= current) / len(window) * 100.0)

    return spread.rolling(window=lookback, min_periods=lookback).apply(
        _pct, raw=True
    )


def spread_regime(df: pd.DataFrame, lookback: int = 100) -> pd.Series:
    """Classify spread as ``tight``, ``normal``, or ``wide``.

    Thresholds (percentile of recent spreads):
    * **tight**: < 25th percentile
    * **normal**: 25th – 75th percentile
    * **wide**: > 75th percentile

    Parameters
    ----------
    df : pd.DataFrame
        Must contain a ``spread`` column.
    lookback : int, optional
        Rolling window, by default 100.

    Returns
    -------
    pd.Series
        Categorical values ``"tight"``, ``"normal"``, or ``"wide"``.
    """
    pct = spread_percentile(df, lookback)
    regime = pd.Series(np.nan, index=df.index, dtype=object)
    regime[pct < 25] = "tight"
    regime[(pct >= 25) & (pct <= 75)] = "normal"
    regime[pct > 75] = "wide"
    return regime


def is_tradeable_spread(
    spread: pd.Series | float,
    max_spread: float,
    pip_value: float,
) -> pd.Series | bool:
    """Check whether the spread is below the maximum allowed threshold.

    Parameters
    ----------
    spread : pd.Series | float
        Raw spread value(s) in price units.
    max_spread : float
        Maximum acceptable spread **in pips**.
    pip_value : float
        Value of one pip in price units (e.g. 0.0001 for EUR/USD).

    Returns
    -------
    pd.Series | bool
        Boolean mask (or scalar) — ``True`` when the spread is tradeable.
    """
    spread_pips = spread / pip_value
    return spread_pips <= max_spread


def spread_cost_ratio(
    spread: pd.Series,
    atr_values: pd.Series,
    pip_value: float,
) -> pd.Series:
    """Spread as a fraction of ATR (both converted to pips).

    A lower ratio means the cost of the spread is small relative to
    expected price movement — more favourable for scalping.

    Parameters
    ----------
    spread : pd.Series
        Raw spread in price units.
    atr_values : pd.Series
        ATR values in price units.
    pip_value : float
        Value of one pip in price units.

    Returns
    -------
    pd.Series
        Ratio (spread_pips / atr_pips).  Values > 1 indicate the spread
        exceeds recent average range — typically untradeable.
    """
    spread_pips = spread / pip_value
    atr_pips = atr_values / pip_value
    return spread_pips / atr_pips


def add_spread_features(df: pd.DataFrame, pip_value: float) -> pd.DataFrame:
    """Add all spread-derived features to a candle DataFrame **in-place**.

    Requires ``spread``, ``high``, ``low``, and ``close`` columns.

    Columns added:
    * ``spread_pct`` – spread percentile (lookback=100)
    * ``spread_regime`` – tight / normal / wide
    * ``spread_cost_ratio`` – spread / ATR ratio
    * ``tradeable_spread`` – boolean (max 3-pip default threshold)

    Parameters
    ----------
    df : pd.DataFrame
        Candle DataFrame with a ``spread`` column.
    pip_value : float
        Value of one pip in price units.

    Returns
    -------
    pd.DataFrame
        The same DataFrame with spread feature columns appended.
    """
    df["spread_pct"] = spread_percentile(df, lookback=100)
    df["spread_regime"] = spread_regime(df, lookback=100)

    atr_values = _atr(df["high"], df["low"], df["close"], period=14)
    df["spread_cost_ratio"] = spread_cost_ratio(df["spread"], atr_values, pip_value)
    df["tradeable_spread"] = is_tradeable_spread(df["spread"], max_spread=3.0, pip_value=pip_value)

    return df
