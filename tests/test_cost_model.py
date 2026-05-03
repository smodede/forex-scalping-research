"""Tests for transaction cost model."""

from src.backtest.costs import CostModel


def test_commission_scales_with_quantity():
    cm = CostModel(commission_per_lot=7.0, slippage_pips=0.0, pip_value=10.0)
    assert cm.calculate_commission(1.0) == 7.0
    assert cm.calculate_commission(2.0) == 14.0


def test_slippage_is_positive():
    slip = CostModel.calculate_slippage("long", 1.10000, 0.5, 10.0)
    assert slip > 0


def test_spread_cost():
    cost = CostModel.calculate_spread_cost(0.00010, 1.0, 10.0)
    assert cost > 0


def test_total_cost():
    cm = CostModel(commission_per_lot=7.0, slippage_pips=0.3, pip_value=10.0)
    comm, slip_cost, spread_cost, total = cm.total_cost(
        quantity=1.0, spread=0.00010, direction="long", price=1.10000
    )
    assert comm == 7.0
    assert total > 0
    assert total == comm + slip_cost + spread_cost
