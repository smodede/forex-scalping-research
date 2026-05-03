"""Tick-to-candle resampling utilities."""

from __future__ import annotations

import numpy as np
import pandas as pd

from src.data.schema import CANDLE_COLUMNS

# Map user-friendly timeframe labels to pandas offset aliases.
TIMEFRAME_MAP: dict[str, str] = {
    "1m": "1min",
    "3m": "3min",
    "5m": "5min",
    "15m": "15min",
}


def resample_ticks_to_candles(
    tick_df: pd.DataFrame,
    timeframe: str,
) -> pd.DataFrame:
    """Aggregate a tick DataFrame into OHLC candles.

    Parameters
    ----------
    tick_df:
        Must contain columns: timestamp_utc, symbol, bid, ask, mid, spread.
    timeframe:
        One of ``1m``, ``3m``, ``5m``, ``15m``.

    Returns
    -------
    pd.DataFrame with :data:`CANDLE_COLUMNS` ordering.
    """
    if timeframe not in TIMEFRAME_MAP:
        raise ValueError(
            f"Unsupported timeframe '{timeframe}'. Choose from {list(TIMEFRAME_MAP)}"
        )

    freq = TIMEFRAME_MAP[timeframe]
    df = tick_df.copy()
    df["timestamp_utc"] = pd.to_datetime(df["timestamp_utc"], utc=True)
    df = df.set_index("timestamp_utc")

    ohlc_agg = {
        "bid": "ohlc",
        "ask": "ohlc",
        "mid": "ohlc",
    }

    resampled = df.resample(freq)

    # OHLC for each price series
    bid_ohlc = resampled["bid"].ohlc()
    ask_ohlc = resampled["ask"].ohlc()
    mid_ohlc = resampled["mid"].ohlc()

    # Spread statistics
    spread_ohlc = resampled["spread"].ohlc()
    spread_mean = resampled["spread"].mean()
    spread_median = resampled["spread"].median()

    tick_count = resampled["bid"].count()

    # Build result
    result = pd.DataFrame(
        {
            "bid_open": bid_ohlc["open"],
            "bid_high": bid_ohlc["high"],
            "bid_low": bid_ohlc["low"],
            "bid_close": bid_ohlc["close"],
            "ask_open": ask_ohlc["open"],
            "ask_high": ask_ohlc["high"],
            "ask_low": ask_ohlc["low"],
            "ask_close": ask_ohlc["close"],
            "mid_open": mid_ohlc["open"],
            "mid_high": mid_ohlc["high"],
            "mid_low": mid_ohlc["low"],
            "mid_close": mid_ohlc["close"],
            "spread_open": spread_ohlc["open"],
            "spread_high": spread_ohlc["high"],
            "spread_low": spread_ohlc["low"],
            "spread_close": spread_ohlc["close"],
            "spread_mean": spread_mean,
            "spread_median": spread_median,
            "tick_count": tick_count,
        }
    )

    # Drop empty candles (no ticks in the window)
    result = result.dropna(subset=["bid_open"]).copy()
    result["tick_count"] = result["tick_count"].astype(int)

    result = result.reset_index()
    # Carry forward the symbol from the input
    symbols = df.reset_index()["symbol"].unique()
    result["symbol"] = symbols[0] if len(symbols) == 1 else ""
    result["timeframe"] = timeframe
    result["source"] = ""  # caller should fill this

    # Ensure canonical column order (only columns that exist)
    ordered = [c for c in CANDLE_COLUMNS if c in result.columns]
    return result[ordered].reset_index(drop=True)
