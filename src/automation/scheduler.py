"""Lightweight task scheduler using threading timers."""
from __future__ import annotations

import logging
import threading
from typing import Any, Callable, Optional

from pydantic import BaseModel, Field

logger = logging.getLogger(__name__)


class SchedulerConfig(BaseModel):
    """Configuration for the task scheduler."""

    max_tasks: int = Field(default=50, ge=1, description="Maximum concurrent scheduled tasks")
    default_interval: int = Field(default=60, ge=1, description="Default interval in seconds")


class _RepeatingTimer:
    """Internal repeating timer that reschedules itself."""

    def __init__(self, interval: float, fn: Callable[[], Any], name: str) -> None:
        self.interval = interval
        self.fn = fn
        self.name = name
        self._timer: Optional[threading.Timer] = None
        self._stopped = threading.Event()

    def _run(self) -> None:
        if self._stopped.is_set():
            return
        try:
            self.fn()
        except Exception:
            logger.exception("Task %s failed", self.name)
        self._schedule()

    def _schedule(self) -> None:
        self._timer = threading.Timer(self.interval, self._run)
        self._timer.daemon = True
        self._timer.start()

    def start(self) -> None:
        self._stopped.clear()
        self._schedule()

    def stop(self) -> None:
        self._stopped.set()
        if self._timer is not None:
            self._timer.cancel()


class TaskScheduler:
    """Schedule periodic tasks using background threads.

    Parameters
    ----------
    config : SchedulerConfig | None
        Optional scheduler configuration.
    """

    def __init__(self, config: SchedulerConfig | None = None) -> None:
        self.config = config or SchedulerConfig()
        self._tasks: dict[str, _RepeatingTimer] = {}
        self._running = False

    def add_task(self, name: str, fn: Callable[[], Any], interval_seconds: int) -> None:
        """Register a periodic task.

        Parameters
        ----------
        name : str
            Unique task name.
        fn : Callable
            Function to invoke periodically.
        interval_seconds : int
            Seconds between invocations.

        Raises
        ------
        ValueError
            If the maximum number of tasks is exceeded or a duplicate
            name is used.
        """
        if name in self._tasks:
            raise ValueError(f"Task '{name}' already registered")
        if len(self._tasks) >= self.config.max_tasks:
            raise ValueError(f"Maximum task limit ({self.config.max_tasks}) reached")

        timer = _RepeatingTimer(interval_seconds, fn, name)
        self._tasks[name] = timer

        if self._running:
            timer.start()
            logger.info("Task '%s' started (interval=%ds)", name, interval_seconds)

    def start(self) -> None:
        """Start all registered tasks."""
        self._running = True
        for name, timer in self._tasks.items():
            timer.start()
            logger.info("Task '%s' started (interval=%0.fs)", name, timer.interval)

    def stop(self) -> None:
        """Stop all running tasks."""
        self._running = False
        for name, timer in self._tasks.items():
            timer.stop()
            logger.info("Task '%s' stopped", name)
