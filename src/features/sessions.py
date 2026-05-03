"""Forex trading-session identification and filtering."""

from __future__ import annotations

import datetime as dt
from pathlib import Path
from collections.abc import Sequence

import pandas as pd
import yaml

# ---------------------------------------------------------------------------
# Session schedule loaded once from config/pairs.yaml
# ---------------------------------------------------------------------------

_CONFIG_PATH = Path(__file__).resolve().parents[2] / "config" / "pairs.yaml"

_SESSION_TIMES: dict[str, dict[str, str]] | None = None


def _load_session_times() -> dict[str, dict[str, str]]:
    """Load and cache session open/close times from *config/pairs.yaml*."""
    global _SESSION_TIMES  # noqa: PLW0603
    if _SESSION_TIMES is None:
        with open(_CONFIG_PATH) as fh:
            cfg = yaml.safe_load(fh)
        _SESSION_TIMES = cfg["sessions"]
    return _SESSION_TIMES


def _parse_time(t: str) -> dt.time:
    parts = t.split(":")
    return dt.time(int(parts[0]), int(parts[1]))


def _in_session(t: dt.time, open_t: dt.time, close_t: dt.time) -> bool:
    """Check if *t* falls inside [open_t, close_t), handling midnight wrap."""
    if open_t <= close_t:
        return open_t <= t < close_t
    # Wraps midnight (e.g. Sydney 21:00–06:00)
    return t >= open_t or t < close_t


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def get_session(timestamp_utc: dt.datetime | pd.Timestamp) -> list[str]:
    """Return the list of active sessions for a UTC timestamp.

    Overlap sessions (e.g. ``overlap_london_ny``) are appended when more
    than one major session is active simultaneously.

    Parameters
    ----------
    timestamp_utc : datetime.datetime | pd.Timestamp
        A single UTC timestamp.

    Returns
    -------
    list[str]
        Active session names, e.g. ``["london", "new_york", "overlap_london_ny"]``.
    """
    sessions = _load_session_times()
    t = timestamp_utc.time() if hasattr(timestamp_utc, "time") else timestamp_utc

    active: list[str] = []
    for name, window in sessions.items():
        open_t = _parse_time(window["open_utc"])
        close_t = _parse_time(window["close_utc"])
        if _in_session(t, open_t, close_t):
            active.append(name)

    # Detect well-known overlaps
    overlap_pairs = [
        ({"london", "new_york"}, "overlap_london_ny"),
        ({"tokyo", "london"}, "overlap_tokyo_london"),
        ({"sydney", "tokyo"}, "overlap_sydney_tokyo"),
    ]
    active_set = set(active)
    for pair, label in overlap_pairs:
        if pair.issubset(active_set):
            active.append(label)

    return active


def is_session_overlap(timestamp_utc: dt.datetime | pd.Timestamp) -> bool:
    """Return ``True`` if *timestamp_utc* falls in any session-overlap period.

    Parameters
    ----------
    timestamp_utc : datetime.datetime | pd.Timestamp
        A single UTC timestamp.

    Returns
    -------
    bool
    """
    return any(s.startswith("overlap_") for s in get_session(timestamp_utc))


def add_session_columns(df: pd.DataFrame) -> pd.DataFrame:
    """Add boolean session columns to a candle DataFrame **in-place**.

    Expects the DataFrame index (or a ``timestamp`` column) to contain
    UTC-aware or UTC-naïve ``datetime`` values.

    Columns added: ``session_sydney``, ``session_tokyo``, ``session_london``,
    ``session_new_york``, ``session_overlap_london_ny``, ``session_overlap``.

    Parameters
    ----------
    df : pd.DataFrame
        Candle DataFrame.

    Returns
    -------
    pd.DataFrame
        The same DataFrame with session columns appended.
    """
    sessions = _load_session_times()

    timestamps: pd.Series
    if isinstance(df.index, pd.DatetimeIndex):
        timestamps = df.index.to_series()
    elif "timestamp" in df.columns:
        timestamps = pd.to_datetime(df["timestamp"])
    else:
        raise ValueError(
            "DataFrame must have a DatetimeIndex or a 'timestamp' column."
        )

    times = timestamps.dt.time

    for name, window in sessions.items():
        open_t = _parse_time(window["open_utc"])
        close_t = _parse_time(window["close_utc"])

        if open_t <= close_t:
            mask = (times >= open_t) & (times < close_t)
        else:
            mask = (times >= open_t) | (times < close_t)

        df[f"session_{name}"] = mask.values

    # Overlap flags
    df["session_overlap_london_ny"] = df["session_london"] & df["session_new_york"]
    df["session_overlap"] = df["session_overlap_london_ny"].copy()

    if "session_tokyo" in df.columns and "session_london" in df.columns:
        overlap_tl = df["session_tokyo"] & df["session_london"]
        df["session_overlap_tokyo_london"] = overlap_tl
        df["session_overlap"] = df["session_overlap"] | overlap_tl

    if "session_sydney" in df.columns and "session_tokyo" in df.columns:
        overlap_st = df["session_sydney"] & df["session_tokyo"]
        df["session_overlap_sydney_tokyo"] = overlap_st
        df["session_overlap"] = df["session_overlap"] | overlap_st

    return df


def filter_by_session(
    df: pd.DataFrame,
    sessions: str | Sequence[str],
) -> pd.DataFrame:
    """Filter a candle DataFrame to rows active in *any* of the given sessions.

    If the session columns are missing they are added automatically via
    :func:`add_session_columns`.

    Parameters
    ----------
    df : pd.DataFrame
        Candle DataFrame.
    sessions : str | Sequence[str]
        One or more session names (e.g. ``"london"`` or ``["london", "new_york"]``).

    Returns
    -------
    pd.DataFrame
        Filtered copy of the DataFrame.
    """
    if isinstance(sessions, str):
        sessions = [sessions]

    # Ensure session columns exist
    col_check = f"session_{sessions[0]}"
    if col_check not in df.columns:
        add_session_columns(df)

    mask = pd.Series(False, index=df.index)
    for s in sessions:
        col = f"session_{s}"
        if col in df.columns:
            mask = mask | df[col]

    return df.loc[mask].copy()
