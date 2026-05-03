"""Optimization layer: search, objective, runner, robustness, selection."""

from src.optimization.objective import (
    MultiObjective,
    Objective,
    ObjectiveWeights,
    composite_objective,
)
from src.optimization.optuna_runner import OptimizationResult, OptunaRunner
from src.optimization.robustness import (
    MonteCarloResult,
    PerturbationResult,
    StressResult,
    monte_carlo_equity,
    param_perturbation,
    stress_test_costs,
)
from src.optimization.search_space import (
    ParamDef,
    ParamType,
    SearchSpace,
    build_search_space,
)
from src.optimization.selection import (
    GateResult,
    SelectedStrategy,
    ValidationGates,
    select_best_strategy,
)

__all__ = [
    "ParamDef",
    "ParamType",
    "SearchSpace",
    "build_search_space",
    "Objective",
    "MultiObjective",
    "ObjectiveWeights",
    "composite_objective",
    "OptunaRunner",
    "OptimizationResult",
    "MonteCarloResult",
    "PerturbationResult",
    "StressResult",
    "monte_carlo_equity",
    "param_perturbation",
    "stress_test_costs",
    "GateResult",
    "SelectedStrategy",
    "ValidationGates",
    "select_best_strategy",
]