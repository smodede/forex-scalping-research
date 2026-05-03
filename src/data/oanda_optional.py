"""Placeholder adapter for future OANDA REST-API integration."""

from __future__ import annotations

from pathlib import Path

import pandas as pd

from src.data.base import DataAdapter, SourceConfig


class OandaAdapter(DataAdapter):
    """Stub – will wrap the OANDA v20 REST API when implemented."""

    def __init__(self, config: SourceConfig, symbol: str) -> None:
        super().__init__(config, symbol)

    def list_symbols(self, data_dir: str | Path) -> list[str]:
        raise NotImplementedError("OANDA integration is not yet implemented")

    def fetch_raw(self, path: str | Path) -> pd.DataFrame:
        raise NotImplementedError("OANDA integration is not yet implemented")

    def normalize_timestamps(self, df: pd.DataFrame) -> pd.DataFrame:
        raise NotImplementedError("OANDA integration is not yet implemented")

    def normalize_symbols(self, df: pd.DataFrame) -> pd.DataFrame:
        raise NotImplementedError("OANDA integration is not yet implemented")

    def save_raw(self, df: pd.DataFrame, dest: str | Path) -> Path:
        raise NotImplementedError("OANDA integration is not yet implemented")

    def produce_ticks(self, raw_path: str | Path, dest: str | Path) -> Path:
        raise NotImplementedError("OANDA integration is not yet implemented")

    def produce_candles(
        self,
        tick_path: str | Path,
        dest: str | Path,
        timeframe: str,
    ) -> Path:
        raise NotImplementedError("OANDA integration is not yet implemented")
