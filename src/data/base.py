"""Abstract base class for data-source adapters and shared config."""

from __future__ import annotations

from abc import ABC, abstractmethod
from pathlib import Path
from typing import Any

import pandas as pd
import yaml
from pydantic import BaseModel


# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

class SourceConfig(BaseModel):
    """Column mapping and settings for a single data source."""

    type: str
    role: str
    description: str = ""
    column_mapping: dict[str, str]
    timestamp_format: str
    default_separator: str = ","


def load_source_config(
    config_path: str | Path,
    source_name: str,
) -> SourceConfig:
    """Load a single source's config from *data_sources.yaml*."""
    with open(config_path) as fh:
        raw: dict[str, Any] = yaml.safe_load(fh)
    section = raw["sources"][source_name]
    return SourceConfig(**section)


# ---------------------------------------------------------------------------
# Abstract adapter
# ---------------------------------------------------------------------------

class DataAdapter(ABC):
    """Base contract every data-source importer must satisfy."""

    def __init__(self, config: SourceConfig, symbol: str) -> None:
        self.config = config
        self.symbol = symbol

    # -- discovery -----------------------------------------------------------

    @abstractmethod
    def list_symbols(self, data_dir: str | Path) -> list[str]:
        """Return symbols available under *data_dir*."""

    # -- ingest --------------------------------------------------------------

    @abstractmethod
    def fetch_raw(self, path: str | Path) -> pd.DataFrame:
        """Read a raw file into a DataFrame with original column names."""

    # -- normalisation -------------------------------------------------------

    @abstractmethod
    def normalize_timestamps(self, df: pd.DataFrame) -> pd.DataFrame:
        """Parse and convert timestamps to UTC datetime64[ns, UTC]."""

    @abstractmethod
    def normalize_symbols(self, df: pd.DataFrame) -> pd.DataFrame:
        """Standardise the symbol column (e.g. EUR/USD → EURUSD)."""

    def normalize_bid_ask(self, df: pd.DataFrame) -> pd.DataFrame:
        """Rename bid/ask columns to canonical names using the config mapping."""
        mapping = self.config.column_mapping
        rename = {}
        if mapping.get("bid") and mapping["bid"] != "bid":
            rename[mapping["bid"]] = "bid"
        if mapping.get("ask") and mapping["ask"] != "ask":
            rename[mapping["ask"]] = "ask"
        if rename:
            df = df.rename(columns=rename)
        return df

    # -- validation ----------------------------------------------------------

    def validate_bid_ask(self, df: pd.DataFrame) -> pd.DataFrame:
        """Flag rows where bid >= ask or prices are non-positive."""
        flags: list[list[str]] = [[] for _ in range(len(df))]
        neg_mask = (df["bid"] <= 0) | (df["ask"] <= 0)
        cross_mask = df["bid"] > df["ask"]
        zero_spread = df["bid"] == df["ask"]
        for idx in df.index[neg_mask]:
            flags[df.index.get_loc(idx)].append("non_positive_price")
        for idx in df.index[cross_mask]:
            flags[df.index.get_loc(idx)].append("negative_spread")
        for idx in df.index[zero_spread]:
            flags[df.index.get_loc(idx)].append("zero_spread")
        df = df.copy()
        df["quality_flags"] = flags
        return df

    # -- persistence ---------------------------------------------------------

    @abstractmethod
    def save_raw(self, df: pd.DataFrame, dest: str | Path) -> Path:
        """Persist normalised tick data (typically as Parquet)."""

    # -- high-level pipelines ------------------------------------------------

    @abstractmethod
    def produce_ticks(self, raw_path: str | Path, dest: str | Path) -> Path:
        """End-to-end: raw file → validated tick Parquet."""

    @abstractmethod
    def produce_candles(
        self,
        tick_path: str | Path,
        dest: str | Path,
        timeframe: str,
    ) -> Path:
        """End-to-end: tick Parquet → candle Parquet for *timeframe*."""
