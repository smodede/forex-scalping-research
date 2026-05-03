"""Parameter search space definitions for strategy optimization."""
from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Optional, Sequence, Type

import optuna


class ParamType(str, Enum):
    """Supported parameter types."""

    INT = "int"
    FLOAT = "float"
    CATEGORICAL = "categorical"


@dataclass
class ParamDef:
    """Definition of a single optimizable parameter.

    Parameters
    ----------
    name : str
        Parameter name matching the strategy's ``StrategyParams`` key.
    type : ParamType
        Data type of the parameter.
    low : float | None
        Lower bound for numeric types.
    high : float | None
        Upper bound for numeric types.
    step : float | None
        Step size for numeric types.  ``None`` means continuous.
    choices : list[Any] | None
        Allowed values for categorical parameters.
    """

    name: str
    type: ParamType
    low: Optional[float] = None
    high: Optional[float] = None
    step: Optional[float] = None
    choices: Optional[list[Any]] = None

    def __post_init__(self) -> None:
        if self.type in (ParamType.INT, ParamType.FLOAT):
            if self.low is None or self.high is None:
                raise ValueError(
                    f"Numeric param '{self.name}' requires low and high bounds"
                )
        if self.type == ParamType.CATEGORICAL:
            if not self.choices:
                raise ValueError(
                    f"Categorical param '{self.name}' requires choices"
                )


class SearchSpace:
    """Collection of parameter definitions forming a search space.

    Example
    -------
    >>> space = SearchSpace()
    >>> space.add_param(ParamDef("period", ParamType.INT, low=5, high=50, step=1))
    >>> space.add_param(ParamDef("threshold", ParamType.FLOAT, low=0.1, high=2.0))
    """

    def __init__(self) -> None:
        self._params: dict[str, ParamDef] = {}

    @property
    def params(self) -> list[ParamDef]:
        """Return all parameter definitions."""
        return list(self._params.values())

    def add_param(self, param: ParamDef) -> None:
        """Register a parameter definition.

        Parameters
        ----------
        param : ParamDef
            Parameter to add to the search space.

        Raises
        ------
        ValueError
            If a parameter with the same name already exists.
        """
        if param.name in self._params:
            raise ValueError(f"Duplicate parameter name: {param.name}")
        self._params[param.name] = param

    def to_optuna_suggest(self, trial: optuna.Trial) -> dict[str, Any]:
        """Sample a full parameter set from an Optuna trial.

        Parameters
        ----------
        trial : optuna.Trial
            Active Optuna trial for parameter suggestion.

        Returns
        -------
        dict[str, Any]
            Dictionary mapping parameter names to sampled values.
        """
        suggested: dict[str, Any] = {}
        for p in self._params.values():
            if p.type == ParamType.INT:
                suggested[p.name] = trial.suggest_int(
                    p.name,
                    int(p.low),  # type: ignore[arg-type]
                    int(p.high),  # type: ignore[arg-type]
                    step=int(p.step) if p.step is not None else 1,
                )
            elif p.type == ParamType.FLOAT:
                kwargs: dict[str, Any] = {
                    "name": p.name,
                    "low": p.low,
                    "high": p.high,
                }
                if p.step is not None:
                    kwargs["step"] = p.step
                suggested[p.name] = trial.suggest_float(**kwargs)
            elif p.type == ParamType.CATEGORICAL:
                suggested[p.name] = trial.suggest_categorical(
                    p.name, p.choices  # type: ignore[arg-type]
                )
        return suggested

    def __len__(self) -> int:
        return len(self._params)

    def __repr__(self) -> str:
        return f"SearchSpace(params={list(self._params.keys())})"


def _dict_to_param_def(name: str, spec: dict[str, Any]) -> ParamDef:
    """Convert a strategy param-space dict entry to a ``ParamDef``.

    Expected dict formats::

        {"type": "int",   "low": 5, "high": 50, "step": 1}
        {"type": "float", "low": 0.1, "high": 2.0}
        {"type": "categorical", "choices": ["ema", "sma"]}
    """
    ptype = ParamType(spec["type"])
    return ParamDef(
        name=name,
        type=ptype,
        low=spec.get("low"),
        high=spec.get("high"),
        step=spec.get("step"),
        choices=spec.get("choices"),
    )


def build_search_space(strategy_class: Type) -> SearchSpace:
    """Build a ``SearchSpace`` from a strategy class's ``get_param_space()``.

    The strategy must implement ``get_param_space()`` returning a dict
    keyed by parameter name with value dicts describing type, bounds,
    and choices.

    Parameters
    ----------
    strategy_class : Type
        A ``BaseStrategy`` subclass.  An instance is created with dummy
        params to call ``get_param_space()``.

    Returns
    -------
    SearchSpace
        Populated search space ready for Optuna.
    """
    from src.strategies.base import StrategyParams

    dummy = strategy_class(StrategyParams(name=strategy_class.__name__, params={}))
    raw_space: dict[str, Any] = dummy.get_param_space()

    space = SearchSpace()
    for name, spec in raw_space.items():
        space.add_param(_dict_to_param_def(name, spec))
    return space
