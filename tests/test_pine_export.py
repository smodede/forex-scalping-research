"""Tests for Pine Script v6 export."""

from src.backtest.metrics import BacktestMetrics
from src.export.pine_v6 import PineScriptExporter
from src.strategies.mean_reversion_scalper import MeanReversionScalper


def _make_metrics() -> BacktestMetrics:
    return BacktestMetrics(
        total_trades=100, win_rate=0.55, profit_factor=1.5,
        sharpe_ratio=1.2, sortino_ratio=1.8, max_drawdown_pct=5.0,
        max_drawdown_duration=3600, avg_trade_pnl=2.5, avg_winner=8.0,
        avg_loser=-5.0, expectancy=2.5, total_pnl=250.0, return_pct=2.5,
        avg_trade_duration=300.0, calmar_ratio=0.5,
    )


def _generate_pine() -> str:
    strategy = MeanReversionScalper()
    return PineScriptExporter().generate(strategy, strategy.params, _make_metrics())


def test_pine_contains_version():
    assert "//@version=6" in _generate_pine()


def test_pine_contains_strategy_declaration():
    assert "strategy(" in _generate_pine()


def test_pine_contains_inputs():
    assert "input" in _generate_pine().lower()


def test_contains_strategy_entry():
    assert "strategy.entry" in _generate_pine()


def test_contains_strategy_exit():
    code = _generate_pine()
    assert "strategy.close" in code or "strategy.exit" in code


def test_contains_alert_conditions():
    assert "alert" in _generate_pine().lower()
