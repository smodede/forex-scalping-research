"""Trend-pullback scalping strategy using EMA crossover + RSI pullback."""
from __future__ import annotations

from typing import Any

import pandas as pd

from src.features.indicators import atr, ema, rsi
from src.strategies.base import BaseStrategy, Signal, StrategyParams


_DEFAULT_PARAMS: dict[str, Any] = {
    "fast_ema": 8,
    "slow_ema": 21,
    "rsi_period": 14,
    "rsi_pullback_level": 40,
    "atr_period": 14,
    "sl_atr_mult": 1.5,
    "tp_atr_mult": 1.0,
    "max_spread_pips": 2.0,
}


class TrendPullbackScalper(BaseStrategy):
    """EMA-crossover trend + RSI pullback scalper.

    Trend direction determined by fast EMA vs slow EMA.
    Entry long:  uptrend AND RSI pulls back below ``rsi_pullback_level``
                 on the prior bar then bounces back above it.
    Entry short: downtrend AND RSI rises above ``100 - rsi_pullback_level``
                 on the prior bar then drops back below it.
    """

    def __init__(self, params: StrategyParams | None = None):
        if params is None:
            params = StrategyParams(name="trend_pullback_scalper", params=_DEFAULT_PARAMS)
        super().__init__(params)

    # ------------------------------------------------------------------
    # Signal generation
    # ------------------------------------------------------------------

    def generate_signals(self, df: pd.DataFrame) -> list[Signal]:
        p = self.params

        fast = ema(df["close"], period=p.get("fast_ema"))
        slow = ema(df["close"], period=p.get("slow_ema"))
        rsi_vals = rsi(df["close"], period=p.get("rsi_period"))
        atr_vals = atr(
            df["high"], df["low"], df["close"], period=p.get("atr_period"),
        )

        # Shift by 1 — only completed bars
        fast_prev = fast.shift(1)
        slow_prev = slow.shift(1)
        rsi_prev = rsi_vals.shift(1)
        rsi_prev2 = rsi_vals.shift(2)
        atr_prev = atr_vals.shift(1)
        close_prev = df["close"].shift(1)

        spread = df.get("spread", pd.Series(0.0, index=df.index))
        max_spread = p.get("max_spread_pips")
        pullback = p.get("rsi_pullback_level")
        overbought_pullback = 100 - pullback
        sl_mult = p.get("sl_atr_mult")
        tp_mult = p.get("tp_atr_mult")

        signals: list[Signal] = []
        for i in range(2, len(df)):
            if pd.isna(atr_prev.iloc[i]) or pd.isna(rsi_prev2.iloc[i]):
                continue
            if spread.iloc[i] > max_spread:
                continue

            cur_atr = atr_prev.iloc[i]
            ts = df["timestamp_utc"].iloc[i]
            price = close_prev.iloc[i]

            uptrend = fast_prev.iloc[i] > slow_prev.iloc[i]
            downtrend = fast_prev.iloc[i] < slow_prev.iloc[i]

            # Long: RSI dipped below pullback level then bounced back above
            if (
                uptrend
                and rsi_prev2.iloc[i] < pullback
                and rsi_prev.iloc[i] >= pullback
            ):
                signals.append(Signal(
                    timestamp=ts,
                    direction="long",
                    entry_price=price,
                    stop_loss=price - sl_mult * cur_atr,
                    take_profit=price + tp_mult * cur_atr,
                    signal_strength=(fast_prev.iloc[i] - slow_prev.iloc[i]) / cur_atr
                    if cur_atr else 1.0,
                    metadata={
                        "rsi": rsi_prev.iloc[i],
                        "atr": cur_atr,
                        "ema_diff": fast_prev.iloc[i] - slow_prev.iloc[i],
                    },
                ))

            # Short: RSI rose above overbought pullback then dropped back
            if (
                downtrend
                and rsi_prev2.iloc[i] > overbought_pullback
                and rsi_prev.iloc[i] <= overbought_pullback
            ):
                signals.append(Signal(
                    timestamp=ts,
                    direction="short",
                    entry_price=price,
                    stop_loss=price + sl_mult * cur_atr,
                    take_profit=price - tp_mult * cur_atr,
                    signal_strength=(slow_prev.iloc[i] - fast_prev.iloc[i]) / cur_atr
                    if cur_atr else 1.0,
                    metadata={
                        "rsi": rsi_prev.iloc[i],
                        "atr": cur_atr,
                        "ema_diff": fast_prev.iloc[i] - slow_prev.iloc[i],
                    },
                ))

        return signals

    # ------------------------------------------------------------------
    # Parameter search space (Optuna-compatible)
    # ------------------------------------------------------------------

    def get_param_space(self) -> dict[str, Any]:
        return {
            "fast_ema": {"type": "int", "low": 5, "high": 15, "step": 1},
            "slow_ema": {"type": "int", "low": 15, "high": 50, "step": 1},
            "rsi_period": {"type": "int", "low": 7, "high": 21, "step": 1},
            "rsi_pullback_level": {"type": "int", "low": 30, "high": 50, "step": 1},
            "atr_period": {"type": "int", "low": 7, "high": 21, "step": 1},
            "sl_atr_mult": {"type": "float", "low": 1.0, "high": 3.0, "step": 0.1},
            "tp_atr_mult": {"type": "float", "low": 0.5, "high": 2.5, "step": 0.1},
            "max_spread_pips": {"type": "float", "low": 1.0, "high": 3.0, "step": 0.5},
        }

    # ------------------------------------------------------------------
    # Pine Script v6 fragments
    # ------------------------------------------------------------------

    def get_pine_script_rules(self) -> dict[str, str]:
        p = self.params
        pullback = p.get("rsi_pullback_level")
        ob_pullback = 100 - pullback
        return {
            "indicator": (
                f"fast_ema = ta.ema(close, {p.get('fast_ema')})\n"
                f"slow_ema = ta.ema(close, {p.get('slow_ema')})\n"
                f"rsi_val = ta.rsi(close, {p.get('rsi_period')})\n"
                f"atr_val = ta.atr({p.get('atr_period')})\n"
            ),
            "entry_long": (
                f"uptrend = fast_ema[1] > slow_ema[1]\n"
                f"longCond = uptrend and rsi_val[2] < {pullback} and "
                f"rsi_val[1] >= {pullback}"
            ),
            "entry_short": (
                f"downtrend = fast_ema[1] < slow_ema[1]\n"
                f"shortCond = downtrend and rsi_val[2] > {ob_pullback} and "
                f"rsi_val[1] <= {ob_pullback}"
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
        pullback = p.get("rsi_pullback_level")
        ob_pullback = 100 - pullback
        return {
            "indicator": (
                f"int fast_handle = iMA(_Symbol, PERIOD_CURRENT, "
                f"{p.get('fast_ema')}, 0, MODE_EMA, PRICE_CLOSE);\n"
                f"int slow_handle = iMA(_Symbol, PERIOD_CURRENT, "
                f"{p.get('slow_ema')}, 0, MODE_EMA, PRICE_CLOSE);\n"
                f"int rsi_handle = iRSI(_Symbol, PERIOD_CURRENT, "
                f"{p.get('rsi_period')}, PRICE_CLOSE);\n"
                f"int atr_handle = iATR(_Symbol, PERIOD_CURRENT, "
                f"{p.get('atr_period')});"
            ),
            "entry_long": (
                f"bool uptrend = (fast_ema_prev > slow_ema_prev);\n"
                f"bool longCond = uptrend && (rsi_prev2 < {pullback}) && "
                f"(rsi_prev >= {pullback});"
            ),
            "entry_short": (
                f"bool downtrend = (fast_ema_prev < slow_ema_prev);\n"
                f"bool shortCond = downtrend && (rsi_prev2 > {ob_pullback}) && "
                f"(rsi_prev <= {ob_pullback});"
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
