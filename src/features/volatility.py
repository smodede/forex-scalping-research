"""Volatility features for forex scalping analysis."""

from __future__ import annotations

import numpy as np
import pandas as pd

from src.features.indicators import atr as _atr


def rolling_atr(df: pd.DataFrame, period: int = 14) -> pd.Series:
    """Average True Range over a rolling window.

    Parameters
    ----------
    df : pd.DataFrame
        Must contain ``high``, ``low``, ``close`` columns.
    period : int, optional
        ATR look-back window, by default 14.

    Returns
    -------
    pd.Series
        ATR values.
    """
    return _atr(df["high"], df["low"], df["close"], period)


def atr_percentile(
    df: pd.DataFrame, period: int = 14, lookback: int = 100
) -> pd.Series:
    """Current ATR expressed as a percentile of recent ATR values.

    Parameters
    ----------
    df : pd.DataFrame
        Must contain ``high``, ``low``, ``close`` columns.
    period : int, optional
        ATR calculation period, by default 14.
    lookback : int, optional
        Number of past ATR values to rank against, by default 100.

    Returns
    -------
    pd.Series
        Percentile values in [0, 100].
    """
    atr_vals = rolling_atr(df, period)

    def _pct(window: np.ndarray) -> float:
        current = window[-1]
        return float(np.sum(window <= current) / len(window) * 100.0)

    return atr_vals.rolling(window=lookback, min_periods=lookback).apply(
        _pct, raw=True
    )


def volatility_regime(
    df: pd.DataFrame,
    period: int = 14,
    lookback: int = 100,
) -> pd.Series:
    """Classify volatility as ``low``, ``normal``, or ``high``.

    Classification thresholds (percentile of recent ATR):
    * **low**: < 25th percentile
    * **normal**: 25th – 75th percentile
    * **high**: > 75th percentile

    Parameters
    ----------
    df : pd.DataFrame
        Must contain ``high``, ``low``, ``close`` columns.
    period : int, optional
        ATR calculation period, by default 14.
    lookback : int, optional
        Ranking window, by default 100.

    Returns
    -------
    pd.Series
        Categorical series with values ``"low"``, ``"normal"``, or ``"high"``.
    """
    pct = atr_percentile(df, period, lookback)
    regime = pd.Series(np.nan, index=df.index, dtype=object)
    regime[pct < 25] = "low"
    regime[(pct >= 25) & (pct <= 75)] = "normal"
    regime[pct > 75] = "high"
    return regime


def parkinson_volatility(
    high: pd.Series, low: pd.Series, period: int = 20
) -> pd.Series:
    """Parkinson's volatility estimator (high-low based).

    .. math::
        \\sigma_P = \\sqrt{\\frac{1}{4 n \\ln 2} \\sum (\\ln H_i / L_i)^2}

    Parameters
    ----------
    high : pd.Series
        High prices.
    low : pd.Series
        Low prices.
    period : int, optional
        Rolling window, by default 20.

    Returns
    -------
    pd.Series
        Annualisation is *not* applied; values are per-bar volatility.
    """
    log_hl_sq = np.log(high / low) ** 2
    factor = 1.0 / (4.0 * period * np.log(2.0))
    return np.sqrt(factor * log_hl_sq.rolling(window=period).sum())


def garman_klass_volatility(
    open_: pd.Series,
    high: pd.Series,
    low: pd.Series,
    close: pd.Series,
    period: int = 20,
) -> pd.Series:
    """Garman-Klass volatility estimator.

    .. math::
        \\sigma_{GK}^2 = \\frac{1}{n} \\sum \\left[
            \\frac{1}{2}(\\ln H/L)^2 - (2\\ln 2 - 1)(\\ln C/O)^2
        \\right]

    Parameters
    ----------
    open_ : pd.Series
        Open prices.
    high : pd.Series
        High prices.
    low : pd.Series
        Low prices.
    close : pd.Series
        Close prices.
    period : int, optional
        Rolling window, by default 20.

    Returns
    -------
    pd.Series
        Per-bar Garman-Klass volatility.
    """
    log_hl = np.log(high / low)
    log_co = np.log(close / open_)

    term1 = 0.5 * log_hl**2
    term2 = (2.0 * np.log(2.0) - 1.0) * log_co**2
    gk_var = (term1 - term2).rolling(window=period).mean()

    return np.sqrt(gk_var.clip(lower=0.0))
