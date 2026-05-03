"""Tests for tick and candle data schemas."""

from datetime import datetime, timezone

import pytest
from pydantic import ValidationError

from src.data.schema import CANDLE_COLUMNS, TICK_COLUMNS, CandleRecord, TickRecord


def test_tick_record_valid():
    t = TickRecord(
        timestamp_utc=datetime(2024, 1, 1, tzinfo=timezone.utc),
        symbol="EURUSD",
        bid=1.10000,
        ask=1.10010,
        mid=1.10005,
        spread=0.00010,
        source="dukascopy",
    )
    assert t.symbol == "EURUSD"
    assert t.mid == 1.10005


def test_tick_record_rejects_bid_gt_ask():
    with pytest.raises(ValidationError):
        TickRecord(
            timestamp_utc=datetime(2024, 1, 1, tzinfo=timezone.utc),
            symbol="EURUSD",
            bid=1.10020,
            ask=1.10010,
            mid=1.10015,
            spread=-0.00010,
            source="dukascopy",
        )


def test_tick_record_rejects_negative_price():
    with pytest.raises(ValidationError):
        TickRecord(
            timestamp_utc=datetime(2024, 1, 1, tzinfo=timezone.utc),
            symbol="EURUSD",
            bid=-1.0,
            ask=1.10010,
            mid=0.05,
            spread=2.1,
            source="test",
        )


def test_candle_record_valid():
    c = CandleRecord(
        timestamp_utc=datetime(2024, 1, 1, tzinfo=timezone.utc),
        symbol="EURUSD",
        timeframe="1m",
        bid_open=1.1000, bid_high=1.1005, bid_low=1.0998, bid_close=1.1003,
        ask_open=1.1001, ask_high=1.1006, ask_low=1.0999, ask_close=1.1004,
        mid_open=1.10005, mid_high=1.10055, mid_low=1.09985, mid_close=1.10035,
        spread_open=0.0001, spread_high=0.0001, spread_low=0.0001,
        spread_close=0.0001, spread_mean=0.0001, spread_median=0.0001,
        tick_count=120,
        source="dukascopy",
    )
    assert c.timeframe == "1m"


def test_tick_columns_contain_required():
    assert "timestamp_utc" in TICK_COLUMNS
    assert "bid" in TICK_COLUMNS
    assert "ask" in TICK_COLUMNS
    assert "spread" in TICK_COLUMNS


def test_candle_columns_contain_required():
    assert "tick_count" in CANDLE_COLUMNS
    assert "spread_median" in CANDLE_COLUMNS
    assert "timestamp_utc" in CANDLE_COLUMNS
