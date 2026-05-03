"""Mean-reversion scalping strategy using Bollinger Bands + RSI."""
from __future__ import annotations

from typing import Any

import pandas as pd

from src.features.indicators import atr, bollinger_bands, rsi
from src.strategies.base import BaseStrategy, Signal, StrategyParams


_DEFAULT_PARAMS: dict[str, Any] = {
    "bb_period": 20,
    "bb_std": 2.0,
    "rsi_period": 14,
    "rsi_oversold": 30,
    "rsi_overbought": 70,
    "atr_period": 14,
    "sl_atr_mult": 1.5,
    "tp_atr_mult": 1.0,
    "max_spread_pips": 2.0,
}


class MeanReversionScalper(BaseStrategy):
    """Bollinger Band + RSI mean-reversion scalper.

    Entry long:  close touches lower BB AND RSI < oversold AND spread OK.
    Entry short: close touches upper BB AND RSI > overbought AND spread OK.
    SL / TP are expressed as ATR multiples.
    """

    def __init__(self, params: StrategyParams | None = None):
        if params is None:
            params = StrategyParams(name="mean_reversion_scalper", params=_DEFAULT_PARAMS)
        super().__init__(params)

    # ------------------------------------------------------------------
    # Signal generation
    # ------------------------------------------------------------------

    def generate_signals(self, df: pd.DataFrame) -> list[Signal]:
        p = self.params

        bb_upper, _, bb_lower = bollinger_bands(
            df["close"], period=p.get("bb_period"), std_dev=p.get("bb_std"),
        )
        rsi_vals = rsi(df["close"], period=p.get("rsi_period"))
        atr_vals = atr(
            df["high"], df["low"], df["close"], period=p.get("atr_period"),
        )

        # Shift everything by 1 to use only completed bars
        close_prev = df["close"].shift(1)
        bb_upper_prev = bb_upper.shift(1)
        bb_lower_prev = bb_lower.shift(1)
        rsi_prev = rsi_vals.shift(1)
        atr_prev = atr_vals.shift(1)

        spread = df.get("spread", pd.Series(0.0, index=df.index))
        max_spread = p.get("max_spread_pips")
        sl_mult = p.get("sl_atr_mult")
        tp_mult = p.get("tp_atr_mult")

        signals: list[Signal] = []
        for i in range(1, len(df)):
            if pd.isna(atr_prev.iloc[i]) or pd.isna(rsi_prev.iloc[i]):
                continue
            if spread.iloc[i] > max_spread:
                continue

            cur_atr = atr_prev.iloc[i]
            ts = df["timestamp_utc"].iloc[i]
            price = close_prev.iloc[i]

            # Long entry
            if close_prev.iloc[i] <= bb_lower_prev.iloc[i] and rsi_prev.iloc[i] < p.get("rsi_oversold"):
                signals.append(Signal(
                    timestamp=ts,
                    direction="long",
                    entry_price=price,
                    stop_loss=price - sl_mult * cur_atr,
                    take_profit=price + tp_mult * cur_atr,
                    signal_strength=1.0 - rsi_prev.iloc[i] / 100.0,
                    metadata={"rsi": rsi_prev.iloc[i], "atr": cur_atr},
                ))

            # Short entry
            if close_prev.iloc[i] >= bb_upper_prev.iloc[i] and rsi_prev.iloc[i] > p.get("rsi_overbought"):
                signals.append(Signal(
                    timestamp=ts,
                    direction="short",
                    entry_price=price,
                    stop_loss=price + sl_mult * cur_atr,
                    take_profit=price - tp_mult * cur_atr,
                    signal_strength=rsi_prev.iloc[i] / 100.0,
                    metadata={"rsi": rsi_prev.iloc[i], "atr": cur_atr},
                ))

        return signals

    # ------------------------------------------------------------------
    # Parameter search space (Optuna-compatible)
    # ------------------------------------------------------------------

    def get_param_space(self) -> dict[str, Any]:
        return {
            "bb_period": {"type": "int", "low": 10, "high": 40, "step": 2},
            "bb_std": {"type": "float", "low": 1.5, "high": 3.0, "step": 0.1},
            "rsi_period": {"type": "int", "low": 7, "high": 21, "step": 1},
            "rsi_oversold": {"type": "int", "low": 20, "high": 35, "step": 1},
            "rsi_overbought": {"type": "int", "low": 65, "high": 80, "step": 1},
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
        return {
            "indicator": (
                f"bb_len = {p.get('bb_period')}\n"
                f"bb_std = {p.get('bb_std')}\n"
                f"rsi_len = {p.get('rsi_period')}\n"
                f"[bb_mid, bb_upper, bb_lower] = ta.bb(close, bb_len, bb_std)\n"
                f"rsi_val = ta.rsi(close, rsi_len)\n"
                f"atr_val = ta.atr({p.get('atr_period')})\n"
            ),
            "entry_long": (
                f"longCond = close[1] <= bb_lower[1] and "
                f"rsi_val[1] < {p.get('rsi_oversold')}"
            ),
            "entry_short": (
                f"shortCond = close[1] >= bb_upper[1] and "
                f"rsi_val[1] > {p.get('rsi_overbought')}"
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
                f"int bb_handle = iBands(_Symbol, PERIOD_CURRENT, "
                f"{p.get('bb_period')}, 0, {p.get('bb_std')}, PRICE_CLOSE);\n"
                f"int rsi_handle = iRSI(_Symbol, PERIOD_CURRENT, "
                f"{p.get('rsi_period')}, PRICE_CLOSE);\n"
                f"int atr_handle = iATR(_Symbol, PERIOD_CURRENT, "
                f"{p.get('atr_period')});"
            ),
            "entry_long": (
                f"bool longCond = (close_prev <= bb_lower_prev) && "
                f"(rsi_prev < {p.get('rsi_oversold')});"
            ),
            "entry_short": (
                f"bool shortCond = (close_prev >= bb_upper_prev) && "
                f"(rsi_prev > {p.get('rsi_overbought')});"
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
