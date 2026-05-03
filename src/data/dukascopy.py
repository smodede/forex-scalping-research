"""Dukascopy CSV tick-data importer."""

from __future__ import annotations

from pathlib import Path

import pandas as pd

from src.data.base import DataAdapter, SourceConfig
from src.data.resample import resample_ticks_to_candles
from src.data.schema import TICK_COLUMNS
from src.data.storage import save_candles, save_ticks


class DukascopyAdapter(DataAdapter):
    """Import tick CSVs exported from Dukascopy / JForex."""

    def __init__(self, config: SourceConfig, symbol: str) -> None:
        super().__init__(config, symbol)

    # -- discovery -----------------------------------------------------------

    def list_symbols(self, data_dir: str | Path) -> list[str]:
        """Scan *data_dir* for sub-directories that look like symbol names."""
        base = Path(data_dir)
        return sorted(
            p.name for p in base.iterdir() if p.is_dir() and p.name.isalpha()
        )

    # -- ingest --------------------------------------------------------------

    def fetch_raw(self, path: str | Path) -> pd.DataFrame:
        """Read a single Dukascopy CSV file."""
        return pd.read_csv(
            path,
            sep=self.config.default_separator,
            engine="python",
        )

    # -- normalisation -------------------------------------------------------

    def normalize_timestamps(self, df: pd.DataFrame) -> pd.DataFrame:
        ts_col = self.config.column_mapping["timestamp"]
        df = df.copy()
        df["timestamp_utc"] = pd.to_datetime(
            df[ts_col], format=self.config.timestamp_format, utc=True,
        )
        return df

    def normalize_symbols(self, df: pd.DataFrame) -> pd.DataFrame:
        df = df.copy()
        df["symbol"] = self.symbol.replace("/", "").upper()
        return df

    # -- quality flags -------------------------------------------------------

    @staticmethod
    def _add_quality_flags(df: pd.DataFrame) -> pd.DataFrame:
        """Detect common data-quality issues and append flags."""
        df = df.copy()
        if "quality_flags" not in df.columns:
            df["quality_flags"] = [[] for _ in range(len(df))]

        zero = df["spread"] == 0
        negative = df["spread"] < 0
        # Stale: same bid for 10+ consecutive rows
        stale = df["bid"].diff().eq(0) & df["bid"].diff(-1).eq(0)
        weekend = df["timestamp_utc"].dt.dayofweek.isin([5, 6])

        for label, mask in [
            ("zero_spread", zero),
            ("negative_spread", negative),
            ("stale_tick", stale),
            ("weekend_data", weekend),
        ]:
            for pos in df.index[mask]:
                df.at[pos, "quality_flags"] = df.at[pos, "quality_flags"] + [label]

        return df

    # -- persistence ---------------------------------------------------------

    def save_raw(self, df: pd.DataFrame, dest: str | Path) -> Path:
        dest = Path(dest)
        dest.parent.mkdir(parents=True, exist_ok=True)
        return save_ticks(df, dest)

    # -- pipelines -----------------------------------------------------------

    def produce_ticks(self, raw_path: str | Path, dest: str | Path) -> Path:
        """Raw CSV → normalised, validated tick Parquet."""
        df = self.fetch_raw(raw_path)
        df = self.normalize_timestamps(df)
        df = self.normalize_symbols(df)
        df = self.normalize_bid_ask(df)
        df["mid"] = (df["bid"] + df["ask"]) / 2
        df["spread"] = df["ask"] - df["bid"]
        df["source"] = "dukascopy"
        df["raw_file"] = str(raw_path)
        df = self.validate_bid_ask(df)
        df = self._add_quality_flags(df)
        df = df.sort_values("timestamp_utc").reset_index(drop=True)
        # Keep only canonical columns
        df = df[[c for c in TICK_COLUMNS if c in df.columns]]
        return self.save_raw(df, dest)

    def produce_candles(
        self,
        tick_path: str | Path,
        dest: str | Path,
        timeframe: str,
    ) -> Path:
        """Tick Parquet → candle Parquet for a given timeframe."""
        tick_df = pd.read_parquet(tick_path)
        candle_df = resample_ticks_to_candles(tick_df, timeframe)
        candle_df["source"] = "dukascopy"
        dest = Path(dest)
        dest.parent.mkdir(parents=True, exist_ok=True)
        return save_candles(candle_df, dest)
