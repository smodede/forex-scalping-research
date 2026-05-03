"""Scalping strategy implementations."""
from src.strategies.base import BaseStrategy, Signal, StrategyParams
from src.strategies.breakout_scalper import BreakoutScalper
from src.strategies.mean_reversion_scalper import MeanReversionScalper
from src.strategies.trend_pullback_scalper import TrendPullbackScalper

__all__ = [
    "BaseStrategy",
    "BreakoutScalper",
    "MeanReversionScalper",
    "Signal",
    "StrategyParams",
    "TrendPullbackScalper",
]
