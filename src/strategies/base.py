"""Base strategy interface for scalping strategies."""
from __future__ import annotations
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Any
import pandas as pd

@dataclass
class Signal:
    """Trading signal from a strategy."""
    timestamp: pd.Timestamp
    direction: str  # "long" or "short"
    entry_price: float
    stop_loss: float
    take_profit: float
    signal_strength: float = 1.0
    metadata: dict[str, Any] = field(default_factory=dict)

@dataclass  
class StrategyParams:
    """Parameter set for a strategy."""
    name: str
    params: dict[str, Any]
    
    def get(self, key: str, default: Any = None) -> Any:
        return self.params.get(key, default)

class BaseStrategy(ABC):
    """Abstract base class for all scalping strategies."""
    
    def __init__(self, params: StrategyParams):
        self.params = params
        self.name = params.name
    
    @abstractmethod
    def generate_signals(self, df: pd.DataFrame) -> list[Signal]:
        """Generate trading signals from candle data. No lookahead allowed."""
        ...
    
    @abstractmethod
    def get_param_space(self) -> dict[str, Any]:
        """Return the parameter search space for optimization."""
        ...
    
    @abstractmethod
    def get_pine_script_rules(self) -> dict[str, str]:
        """Return Pine Script v6 code fragments for entry/exit rules."""
        ...
    
    @abstractmethod
    def get_mql5_rules(self) -> dict[str, str]:
        """Return MQL5 code fragments for entry/exit rules."""
        ...
    
    def validate_no_lookahead(self, df: pd.DataFrame, signals: list[Signal]) -> bool:
        """Verify no signal uses future data."""
        for sig in signals:
            future = df[df["timestamp_utc"] > sig.timestamp]
            if len(future) == len(df):
                continue
            # Signal timestamp must be <= last available bar
            available = df[df["timestamp_utc"] <= sig.timestamp]
            if available.empty:
                return False
        return True
