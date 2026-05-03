"""Breakout scalping strategy using Donchian channel + ATR filter."""
from __future__ import annotations

from typing import Any

import pandas as pd

from src.features.indicators import atr, sma
from src.strategies.base import BaseStrategy, Signal, StrategyParams


_DEFAULT_PARAMS: dict[str, Any] = {
    "channel_period": 20,
    "atr_period": 14,
    "atr_min_threshold": 0.0005,
    "volume_confirm_period": 10,
    "sl_atr_mult": 1.5,
    "tp_atr_mult": 2.0,
    "max_spread_pips": 2.0,
}


def _donchian(
    high: pd.Series, low: pd.Series, period: int
) -> tuple[pd.Series, pd.Series]:
    """Return (upper, lower) Donchian channel."""
    upper = high.rolling(window=period).max()
    lower = low.rolling(window=period).min()
    return upper, lower


class BreakoutScalper(BaseStrategy):
    """Donchian channel breakout scalper with ATR volatility filter.

    Entry long:  close breaks above upper channel, ATR > threshold, spread OK.
    Entry short: close breaks below lower channel, ATR > threshold, spread OK.
    """

    def __init__(self, params: StrategyParams | None = None):
        if params is None:
            params = StrategyParams(name="breakout_scalper", params=_DEFAULT_PARAMS)
        super().__init__(params)

    # ------------------------------------------------------------------
    # Signal generation
    # ------------------------------------------------------------------

    def generate_signals(self, df: pd.DataFrame) -> list[Signal]:
        p = self.params

        dc_upper, dc_lower = _donchian(
            df["high"], df["low"], period=p.get("channel_period"),
        )
        atr_vals = atr(
            df["high"], df["low"], df["close"], period=p.get("atr_period"),
        )

        vol_period = p.get("volume_confirm_period")
        tick_col = "tick_count" if "tick_count" in df.columns else None
        if tick_col:
            avg_vol = sma(df[tick_col], period=vol_period)
        else:
            avg_vol = None

        # Shift to use only completed bars (no lookahead)
        close_prev = df["close"].shift(1)
        dc_upper_prev = dc_upper.shift(1)
        dc_lower_prev = dc_lower.shift(1)
        atr_prev = atr_vals.shift(1)

        spread = df.get("spread", pd.Series(0.0, index=df.index))
        max_spread = p.get("max_spread_pips")
        atr_thresh = p.get("atr_min_threshold")
        sl_mult = p.get("sl_atr_mult")
        tp_mult = p.get("tp_atr_mult")

        signals: list[Signal] = []
        for i in range(1, len(df)):
            if pd.isna(atr_prev.iloc[i]) or pd.isna(dc_upper_prev.iloc[i]):
                continue
            if spread.iloc[i] > max_spread:
                continue
            if atr_prev.iloc[i] < atr_thresh:
                continue

            # Optional volume confirmation
            if avg_vol is not None and not pd.isna(avg_vol.iloc[i]):
                if tick_col and df[tick_col].iloc[i] < avg_vol.iloc[i]:
                    continue

            cur_atr = atr_prev.iloc[i]
            ts = df["timestamp_utc"].iloc[i]
            price = close_prev.iloc[i]

            # Long breakout
            if close_prev.iloc[i] > dc_upper_prev.iloc[i]:
                signals.append(Signal(
                    timestamp=ts,
                    direction="long",
                    entry_price=price,
                    stop_loss=price - sl_mult * cur_atr,
                    take_profit=price + tp_mult * cur_atr,
                    signal_strength=cur_atr / atr_thresh if atr_thresh else 1.0,
                    metadata={"atr": cur_atr, "dc_upper": dc_upper_prev.iloc[i]},
                ))

            # Short breakout
            if close_prev.iloc[i] < dc_lower_prev.iloc[i]:
                signals.append(Signal(
                    timestamp=ts,
                    direction="short",
                    entry_price=price,
                    stop_loss=price + sl_mult * cur_atr,
                    take_profit=price - tp_mult * cur_atr,
                    signal_strength=cur_atr / atr_thresh if atr_thresh else 1.0,
                    metadata={"atr": cur_atr, "dc_lower": dc_lower_prev.iloc[i]},
                ))

        return signals

    # ------------------------------------------------------------------
    # Parameter search space (Optuna-compatible)
    # ------------------------------------------------------------------

    def get_param_space(self) -> dict[str, Any]:
        return {
            "channel_period": {"type": "int", "low": 10, "high": 50, "step": 2},
            "atr_period": {"type": "int", "low": 7, "high": 21, "step": 1},
            "atr_min_threshold": {"type": "float", "low": 0.0002, "high": 0.0020, "step": 0.0001},
            "volume_confirm_period": {"type": "int", "low": 5, "high": 20, "step": 1},
            "sl_atr_mult": {"type": "float", "low": 1.0, "high": 3.0, "step": 0.1},
            "tp_atr_mult": {"type": "float", "low": 1.0, "high": 4.0, "step": 0.1},
            "max_spread_pips": {"type": "float", "low": 1.0, "high": 3.0, "step": 0.5},
        }

    # ------------------------------------------------------------------
    # Pine Script v6 fragments
    # ------------------------------------------------------------------

    def get_pine_script_rules(self) -> dict[str, str]:
        p = self.params
        return {
            "indicator": (
                f"dc_len = {p.get('channel_period')}\n"
                f"dc_upper = ta.highest(high, dc_len)\n"
                f"dc_lower = ta.lowest(low, dc_len)\n"
                f"atr_val = ta.atr({p.get('atr_period')})\n"
            ),
            "entry_long": (
                f"longCond = close[1] > dc_upper[1] and "
                f"atr_val[1] > {p.get('atr_min_threshold')}"
            ),
            "entry_short": (
                f"shortCond = close[1] < dc_lower[1] and "
                f"atr_val[1] > {p.get('atr_min_threshold')}"
            ),
            "exit_long": (
                f"sl_long = close - atr_val * {p.get('sl_atr_mult')}\n"
                f"tp_long = close + atr_val * {p.get('tp_atr_mult')}"
            ),
            "exit_short": (
                f"sl_short = close + atr_val * {p.get('sl_atr_mult')}\n"
                f"tp_short = close - atr_val * {p.get('tp_atr_mult')}"
            ),
        }

    # ------------------------------------------------------------------
    # MQL5 fragments
    # ------------------------------------------------------------------

    def get_mql5_rules(self) -> dict[str, str]:
        p = self.params
        return {
            "indicator": (
                f"int atr_handle = iATR(_Symbol, PERIOD_CURRENT, "
                f"{p.get('atr_period')});\n"
                f"double dc_upper = iHigh(_Symbol, PERIOD_CURRENT, "
                f"iHighest(_Symbol, PERIOD_CURRENT, MODE_HIGH, "
                f"{p.get('channel_period')}, 1));\n"
                f"double dc_lower = iLow(_Symbol, PERIOD_CURRENT, "
                f"iLowest(_Symbol, PERIOD_CURRENT, MODE_LOW, "
                f"{p.get('channel_period')}, 1));"
            ),
            "entry_long": (
                f"bool longCond = (close_prev > dc_upper) && "
                f"(atr_prev > {p.get('atr_min_threshold')});"
            ),
            "entry_short": (
                f"bool shortCond = (close_prev < dc_lower) && "
                f"(atr_prev > {p.get('atr_min_threshold')});"
            ),
            "exit_long": (
                f"double sl = entry - atr_val * {p.get('sl_atr_mult')};\n"
                f"double tp = entry + atr_val * {p.get('tp_atr_mult')};"
            ),
            "exit_short": (
                f"double sl = entry + atr_val * {p.get('sl_atr_mult')};\n"
                f"double tp = entry - atr_val * {p.get('tp_atr_mult')};"
            ),
        }
