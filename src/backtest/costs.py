"""Transaction cost model for realistic trade simulation."""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any

import yaml


def _load_defaults() -> dict[str, Any]:
    """Load backtest defaults from config/default.yaml."""
    config_path = Path(__file__).resolve().parents[2] / "config" / "default.yaml"
    if config_path.exists():
        with open(config_path) as fh:
            cfg = yaml.safe_load(fh) or {}
        return cfg.get("backtest", {})
    return {}


_DEFAULTS = _load_defaults()


@dataclass
class CostModel:
    """Transaction cost model for backtesting.

    Parameters
    ----------
    commission_per_lot : float
        Commission charged per standard lot (round-trip).
    slippage_pips : float
        Expected slippage in pips (applied adversely).
    pip_value : float
        Monetary value of one pip per lot for the instrument.
    max_spread_pips : float
        Maximum acceptable spread; trades are rejected when exceeded.
    """

    commission_per_lot: float = _DEFAULTS.get("commission_per_lot", 3.5)
    slippage_pips: float = _DEFAULTS.get("default_slippage_pips", 0.3)
    pip_value: float = 10.0  # default for major pairs, 1 standard lot
    max_spread_pips: float = _DEFAULTS.get("max_spread_pips", 2.0)

    def calculate_commission(self, quantity: float) -> float:
        """Return commission for the given lot quantity.

        Parameters
        ----------
        quantity : float
            Position size in lots.

        Returns
        -------
        float
            Total commission cost.
        """
        return self.commission_per_lot * quantity

    @staticmethod
    def calculate_slippage(
        direction: str,
        price: float,
        slippage_pips: float,
        pip_value: float,
    ) -> float:
        """Return adverse slippage adjustment to the fill price.

        For a *long* entry, slippage moves the price **up** (worse fill).
        For a *short* entry, slippage moves the price **down** (worse fill).

        Parameters
        ----------
        direction : str
            ``"long"`` or ``"short"``.
        price : float
            The base price before slippage.
        slippage_pips : float
            Slippage magnitude in pips.
        pip_value : float
            Monetary value of one pip per lot.

        Returns
        -------
        float
            The absolute slippage cost per lot.
        """
        pip_size = pip_value / 10_000 if pip_value >= 1.0 else pip_value / 100
        # For standard forex pairs (pip_value ~10), pip_size = 0.0001
        slippage_price = slippage_pips * pip_size
        if direction == "long":
            return slippage_price  # worse fill for longs
        return slippage_price  # worse fill for shorts (symmetrical cost)

    @staticmethod
    def calculate_spread_cost(
        spread: float,
        quantity: float,
        pip_value: float,
    ) -> float:
        """Return the monetary spread cost.

        Parameters
        ----------
        spread : float
            Current spread in pips.
        quantity : float
            Position size in lots.
        pip_value : float
            Monetary value of one pip per lot.

        Returns
        -------
        float
            Total spread cost.
        """
        return spread * quantity * pip_value

    def total_cost(
        self,
        quantity: float,
        spread: float,
        direction: str,
        price: float,
    ) -> tuple[float, float, float, float]:
        """Compute all transaction costs for a trade.

        Parameters
        ----------
        quantity : float
            Position size in lots.
        spread : float
            Current spread in pips.
        direction : str
            ``"long"`` or ``"short"``.
        price : float
            Entry price before costs.

        Returns
        -------
        tuple[float, float, float, float]
            ``(commission, slippage_cost, spread_cost, total)``
        """
        commission = self.calculate_commission(quantity)
        slippage = self.calculate_slippage(
            direction, price, self.slippage_pips, self.pip_value
        )
        slippage_cost = self.slippage_pips * quantity * self.pip_value
        spread_cost = self.calculate_spread_cost(spread, quantity, self.pip_value)
        total = commission + slippage_cost + spread_cost
        return commission, slippage_cost, spread_cost, total
