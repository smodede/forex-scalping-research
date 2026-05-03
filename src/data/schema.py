"""Pydantic models for tick and candle data schemas."""

from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, model_validator


class TickRecord(BaseModel):
    """Single tick (quote) record from any data source."""

    timestamp_utc: datetime
    symbol: str
    bid: float
    ask: float
    mid: float
    spread: float
    source: str
    raw_file: str = ""
    quality_flags: list[str] = []

    @model_validator(mode="after")
    def _check_prices(self) -> "TickRecord":
        if self.bid <= 0 or self.ask <= 0:
            raise ValueError(f"Prices must be positive: bid={self.bid}, ask={self.ask}")
        if self.bid > self.ask:
            raise ValueError(f"bid ({self.bid}) must be <= ask ({self.ask})")
        if self.spread < 0:
            raise ValueError(f"spread must be >= 0, got {self.spread}")
        return self


class CandleRecord(BaseModel):
    """Single OHLC candle aggregated from ticks."""

    timestamp_utc: datetime
    symbol: str
    timeframe: str

    bid_open: float
    bid_high: float
    bid_low: float
    bid_close: float

    ask_open: float
    ask_high: float
    ask_low: float
    ask_close: float

    mid_open: float
    mid_high: float
    mid_low: float
    mid_close: float

    spread_open: float
    spread_high: float
    spread_low: float
    spread_close: float
    spread_mean: float
    spread_median: float

    tick_count: int
    source: str

    @model_validator(mode="after")
    def _check_ohlc(self) -> "CandleRecord":
        for prefix in ("bid", "mid", "ask"):
            o = getattr(self, f"{prefix}_open")
            h = getattr(self, f"{prefix}_high")
            l = getattr(self, f"{prefix}_low")  # noqa: E741
            c = getattr(self, f"{prefix}_close")
            if h < max(o, c):
                raise ValueError(f"{prefix}_high ({h}) must be >= open ({o}) and close ({c})")
            if l > min(o, c):
                raise ValueError(f"{prefix}_low ({l}) must be <= open ({o}) and close ({c})")
        if self.tick_count < 1:
            raise ValueError(f"tick_count must be >= 1, got {self.tick_count}")
        return self


TICK_COLUMNS: list[str] = [
    "timestamp_utc",
    "symbol",
    "bid",
    "ask",
    "mid",
    "spread",
    "source",
    "raw_file",
    "quality_flags",
]

CANDLE_COLUMNS: list[str] = [
    "timestamp_utc",
    "symbol",
    "timeframe",
    "bid_open",
    "bid_high",
    "bid_low",
    "bid_close",
    "ask_open",
    "ask_high",
    "ask_low",
    "ask_close",
    "mid_open",
    "mid_high",
    "mid_low",
    "mid_close",
    "spread_open",
    "spread_high",
    "spread_low",
    "spread_close",
    "spread_mean",
    "spread_median",
    "tick_count",
    "source",
]
