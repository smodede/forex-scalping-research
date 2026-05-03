"""Parquet read/write helpers for tick and candle data."""

from __future__ import annotations

from pathlib import Path

import pandas as pd


# ---------------------------------------------------------------------------
# Low-level I/O
# ---------------------------------------------------------------------------

def save_ticks(df: pd.DataFrame, path: str | Path) -> Path:
    """Write a tick DataFrame to Parquet using pyarrow."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    df.to_parquet(path, engine="pyarrow", index=False)
    return path


def load_ticks(path: str | Path) -> pd.DataFrame:
    """Read a tick Parquet file."""
    return pd.read_parquet(Path(path), engine="pyarrow")


def save_candles(df: pd.DataFrame, path: str | Path) -> Path:
    """Write a candle DataFrame to Parquet using pyarrow."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    df.to_parquet(path, engine="pyarrow", index=False)
    return path


def load_candles(path: str | Path) -> pd.DataFrame:
    """Read a candle Parquet file."""
    return pd.read_parquet(Path(path), engine="pyarrow")


# ---------------------------------------------------------------------------
# Path conventions
# ---------------------------------------------------------------------------

_DATA_ROOT = Path("data")


def get_tick_path(source: str, symbol: str) -> Path:
    """Canonical path for tick Parquet: ``data/ticks/<source>/<symbol>.parquet``."""
    return _DATA_ROOT / "ticks" / source / f"{symbol}.parquet"


def get_candle_path(source: str, symbol: str, timeframe: str) -> Path:
    """Canonical path: ``data/candles/<source>/<timeframe>/<symbol>.parquet``."""
    return _DATA_ROOT / "candles" / source / timeframe / f"{symbol}.parquet"
