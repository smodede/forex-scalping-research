"""Tests for correlation manifest generation and trade comparison."""

import pandas as pd

from src.backtest.trade_log import Trade, TradeLog
from src.export.correlation import CorrelationManifest, compare_trades
from src.strategies.base import StrategyParams


def _make_trade_log() -> TradeLog:
    log = TradeLog()
    log.add(Trade(
        trade_id="T001", symbol="EURUSD", direction="long",
        entry_time=pd.Timestamp("2024-01-01 10:00", tz="UTC"),
        exit_time=pd.Timestamp("2024-01-01 10:15", tz="UTC"),
        entry_price=1.10000, exit_price=1.10050,
        stop_loss=1.09950, take_profit=1.10100,
        quantity=1.0, pnl_gross=50.0, pnl_net=42.0,
        commission=5.0, slippage_cost=2.0, spread_cost=1.0,
        duration_seconds=900, exit_reason="tp",
    ))
    log.add(Trade(
        trade_id="T002", symbol="EURUSD", direction="short",
        entry_time=pd.Timestamp("2024-01-01 11:00", tz="UTC"),
        exit_time=pd.Timestamp("2024-01-01 11:10", tz="UTC"),
        entry_price=1.10100, exit_price=1.10050,
        stop_loss=1.10150, take_profit=1.10000,
        quantity=1.0, pnl_gross=50.0, pnl_net=42.0,
        commission=5.0, slippage_cost=2.0, spread_cost=1.0,
        duration_seconds=600, exit_reason="tp",
    ))
    return log


def test_manifest_generation():
    log = _make_trade_log()
    params = StrategyParams(name="test", params={"bb_period": 20})
    result = CorrelationManifest().generate(log, params)
    assert "total_trades" in result
    assert result["total_trades"] == 2
    assert result["strategy_name"] == "test"


def test_manifest_has_expected_fields():
    log = _make_trade_log()
    params = StrategyParams(name="test", params={})
    result = CorrelationManifest().generate(log, params)
    assert "tolerance_pips" in result
    assert "tolerance_bars" in result
    assert "total_pnl" in result


def test_compare_trades_matching():
    expected = pd.DataFrame({
        "entry_time": pd.to_datetime(["2024-01-01 10:00"]),
        "direction": ["long"],
        "entry_price": [1.10000],
        "exit_price": [1.10050],
        "pnl_net": [42.0],
    })
    actual = pd.DataFrame({
        "entry_time": pd.to_datetime(["2024-01-01 10:00"]),
        "direction": ["long"],
        "entry_price": [1.10001],
        "exit_price": [1.10049],
        "pnl_net": [41.5],
    })
    report = compare_trades(expected, actual, tolerance_pips=1.0, tolerance_bars=2)
    assert report.matched_count >= 1
