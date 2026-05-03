"""Technical indicators optimised for forex scalping."""

from __future__ import annotations

from typing import Tuple

import numpy as np
import pandas as pd


def ema(series: pd.Series, period: int) -> pd.Series:
    """Exponential Moving Average.

    Parameters
    ----------
    series : pd.Series
        Price series (typically close).
    period : int
        Look-back window.

    Returns
    -------
    pd.Series
        EMA values (first ``period - 1`` entries are NaN).
    """
    return series.ewm(span=period, adjust=False).mean()


def sma(series: pd.Series, period: int) -> pd.Series:
    """Simple Moving Average.

    Parameters
    ----------
    series : pd.Series
        Price series.
    period : int
        Look-back window.

    Returns
    -------
    pd.Series
        SMA values.
    """
    return series.rolling(window=period).mean()


def rsi(series: pd.Series, period: int = 14) -> pd.Series:
    """Relative Strength Index using Wilder's smoothing method.

    Parameters
    ----------
    series : pd.Series
        Price series (typically close).
    period : int, optional
        Look-back window, by default 14.

    Returns
    -------
    pd.Series
        RSI values in the range [0, 100].
    """
    delta = series.diff()
    gain = delta.clip(lower=0.0)
    loss = -delta.clip(upper=0.0)

    # Wilder's smoothing (equivalent to EMA with alpha = 1/period)
    avg_gain = gain.ewm(alpha=1.0 / period, min_periods=period, adjust=False).mean()
    avg_loss = loss.ewm(alpha=1.0 / period, min_periods=period, adjust=False).mean()

    rs = avg_gain / avg_loss
    return 100.0 - (100.0 / (1.0 + rs))


def bollinger_bands(
    series: pd.Series, period: int = 20, std_dev: float = 2.0
) -> Tuple[pd.Series, pd.Series, pd.Series]:
    """Bollinger Bands.

    Parameters
    ----------
    series : pd.Series
        Price series.
    period : int, optional
        SMA look-back window, by default 20.
    std_dev : float, optional
        Number of standard deviations, by default 2.0.

    Returns
    -------
    tuple[pd.Series, pd.Series, pd.Series]
        (upper_band, middle_band, lower_band).
    """
    middle = sma(series, period)
    rolling_std = series.rolling(window=period).std(ddof=0)
    upper = middle + std_dev * rolling_std
    lower = middle - std_dev * rolling_std
    return upper, middle, lower


def atr(
    high: pd.Series, low: pd.Series, close: pd.Series, period: int = 14
) -> pd.Series:
    """Average True Range.

    Parameters
    ----------
    high : pd.Series
        High prices.
    low : pd.Series
        Low prices.
    close : pd.Series
        Close prices.
    period : int, optional
        Look-back window, by default 14.

    Returns
    -------
    pd.Series
        ATR values.
    """
    prev_close = close.shift(1)
    tr = pd.concat(
        [
            high - low,
            (high - prev_close).abs(),
            (low - prev_close).abs(),
        ],
        axis=1,
    ).max(axis=1)
    # Wilder's smoothing for ATR
    return tr.ewm(alpha=1.0 / period, min_periods=period, adjust=False).mean()


def macd(
    series: pd.Series,
    fast: int = 12,
    slow: int = 26,
    signal: int = 9,
) -> Tuple[pd.Series, pd.Series, pd.Series]:
    """Moving Average Convergence Divergence.

    Parameters
    ----------
    series : pd.Series
        Price series (typically close).
    fast : int, optional
        Fast EMA period, by default 12.
    slow : int, optional
        Slow EMA period, by default 26.
    signal : int, optional
        Signal line EMA period, by default 9.

    Returns
    -------
    tuple[pd.Series, pd.Series, pd.Series]
        (macd_line, signal_line, histogram).
    """
    macd_line = ema(series, fast) - ema(series, slow)
    signal_line = ema(macd_line, signal)
    histogram = macd_line - signal_line
    return macd_line, signal_line, histogram


def stochastic(
    high: pd.Series,
    low: pd.Series,
    close: pd.Series,
    k_period: int = 14,
    d_period: int = 3,
) -> Tuple[pd.Series, pd.Series]:
    """Stochastic Oscillator (%K and %D).

    Parameters
    ----------
    high : pd.Series
        High prices.
    low : pd.Series
        Low prices.
    close : pd.Series
        Close prices.
    k_period : int, optional
        %K look-back window, by default 14.
    d_period : int, optional
        %D smoothing window, by default 3.

    Returns
    -------
    tuple[pd.Series, pd.Series]
        (%K, %D) both in range [0, 100].
    """
    lowest_low = low.rolling(window=k_period).min()
    highest_high = high.rolling(window=k_period).max()

    k = 100.0 * (close - lowest_low) / (highest_high - lowest_low)
    d = k.rolling(window=d_period).mean()
    return k, d


def vwap_proxy(
    high: pd.Series,
    low: pd.Series,
    close: pd.Series,
    tick_count: pd.Series,
) -> pd.Series:
    """VWAP-like indicator using tick count as a volume proxy.

    Computes cumulative (typical-price × tick_count) / cumulative tick_count
    within each trading day.  If the index is not a ``DatetimeIndex`` the
    calculation is performed over the entire series.

    Parameters
    ----------
    high : pd.Series
        High prices.
    low : pd.Series
        Low prices.
    close : pd.Series
        Close prices.
    tick_count : pd.Series
        Tick count per candle (used as volume proxy).

    Returns
    -------
    pd.Series
        VWAP-proxy values.
    """
    typical_price = (high + low + close) / 3.0
    tp_vol = typical_price * tick_count

    if isinstance(high.index, pd.DatetimeIndex):
        # Reset cumulative sums at the start of each trading day
        date_groups = high.index.date
        cum_tp_vol = tp_vol.groupby(date_groups).cumsum()
        cum_vol = tick_count.groupby(date_groups).cumsum()
    else:
        cum_tp_vol = tp_vol.cumsum()
        cum_vol = tick_count.cumsum()

    return cum_tp_vol / cum_vol
