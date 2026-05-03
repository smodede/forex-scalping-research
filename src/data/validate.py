"""Data-quality validation utilities for tick and candle DataFrames."""

from __future__ import annotations

from typing import Any

import numpy as np
import pandas as pd

from src.data.schema import CANDLE_COLUMNS, TICK_COLUMNS


# ---------------------------------------------------------------------------
# Tick validation
# ---------------------------------------------------------------------------

def validate_tick_dataframe(df: pd.DataFrame) -> list[str]:
    """Return a list of validation errors (empty = passes)."""
    errors: list[str] = []

    # Schema columns present
    missing = [c for c in TICK_COLUMNS if c not in df.columns]
    if missing:
        errors.append(f"Missing columns: {missing}")

    # No NaN in critical numeric columns
    for col in ("bid", "ask", "mid", "spread"):
        if col in df.columns and df[col].isna().any():
            n = int(df[col].isna().sum())
            errors.append(f"{n} NaN values in '{col}'")

    # Timestamps not null and monotonically non-decreasing
    if "timestamp_utc" in df.columns:
        if df["timestamp_utc"].isna().any():
            errors.append("NaN values in 'timestamp_utc'")
        elif not df["timestamp_utc"].is_monotonic_increasing:
            errors.append("timestamp_utc is not monotonically increasing")

    # bid <= ask
    if {"bid", "ask"}.issubset(df.columns):
        bad = (df["bid"] > df["ask"]).sum()
        if bad:
            errors.append(f"{bad} rows where bid > ask")

    return errors


# ---------------------------------------------------------------------------
# Candle validation
# ---------------------------------------------------------------------------

def validate_candle_dataframe(df: pd.DataFrame) -> list[str]:
    """Return a list of validation errors for candle data."""
    errors: list[str] = []

    missing = [c for c in CANDLE_COLUMNS if c not in df.columns]
    if missing:
        errors.append(f"Missing columns: {missing}")

    # OHLC relationships for each price series
    for prefix in ("bid", "mid", "ask"):
        o, h, l, c = (  # noqa: E741
            f"{prefix}_open",
            f"{prefix}_high",
            f"{prefix}_low",
            f"{prefix}_close",
        )
        if not {o, h, l, c}.issubset(df.columns):
            continue
        high_violation = (df[h] < df[[o, c]].max(axis=1)).sum()
        if high_violation:
            errors.append(f"{high_violation} rows where {h} < max(open, close)")
        low_violation = (df[l] > df[[o, c]].min(axis=1)).sum()
        if low_violation:
            errors.append(f"{low_violation} rows where {l} > min(open, close)")

    # tick_count
    if "tick_count" in df.columns and (df["tick_count"] < 1).any():
        errors.append("tick_count < 1 found")

    return errors


# ---------------------------------------------------------------------------
# Gap detection
# ---------------------------------------------------------------------------

def detect_gaps(
    df: pd.DataFrame,
    max_gap_seconds: float = 60.0,
    ts_col: str = "timestamp_utc",
) -> pd.DataFrame:
    """Return a DataFrame of gaps wider than *max_gap_seconds*.

    Columns: gap_start, gap_end, gap_seconds.
    """
    if ts_col not in df.columns or len(df) < 2:
        return pd.DataFrame(columns=["gap_start", "gap_end", "gap_seconds"])

    ts = pd.to_datetime(df[ts_col])
    deltas = ts.diff().dt.total_seconds()
    mask = deltas > max_gap_seconds

    return pd.DataFrame(
        {
            "gap_start": ts.shift(1)[mask].values,
            "gap_end": ts[mask].values,
            "gap_seconds": deltas[mask].values,
        }
    ).reset_index(drop=True)


# ---------------------------------------------------------------------------
# Quality summary
# ---------------------------------------------------------------------------

def report_quality(df: pd.DataFrame) -> dict[str, Any]:
    """Return a summary dict of data quality metrics for a tick DataFrame."""
    total = len(df)
    summary: dict[str, Any] = {"total_rows": total}

    if total == 0:
        return summary

    if "timestamp_utc" in df.columns:
        ts = pd.to_datetime(df["timestamp_utc"])
        summary["start"] = str(ts.min())
        summary["end"] = str(ts.max())
        duration = (ts.max() - ts.min()).total_seconds()
        summary["duration_hours"] = round(duration / 3600, 2)

    for col in ("bid", "ask", "spread"):
        if col in df.columns:
            summary[f"{col}_nan_count"] = int(df[col].isna().sum())

    if {"bid", "ask"}.issubset(df.columns):
        summary["bid_gt_ask_count"] = int((df["bid"] > df["ask"]).sum())

    if "spread" in df.columns:
        s = df["spread"].dropna()
        summary["spread_mean"] = float(np.round(s.mean(), 8))
        summary["spread_median"] = float(np.round(s.median(), 8))
        summary["spread_max"] = float(s.max())
        summary["zero_spread_count"] = int((s == 0).sum())
        summary["negative_spread_count"] = int((s < 0).sum())

    if "quality_flags" in df.columns:
        from collections import Counter

        counter: Counter[str] = Counter()
        for flags in df["quality_flags"]:
            if isinstance(flags, list):
                counter.update(flags)
        summary["quality_flag_counts"] = dict(counter)

    return summary
