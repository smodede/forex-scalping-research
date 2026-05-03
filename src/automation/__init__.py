"""Automation layer: webhook server, paper broker, scheduler, deploy validation."""

from src.automation.paper_broker import PaperBroker, PaperTrade
from src.automation.scheduler import SchedulerConfig, TaskScheduler
from src.automation.validation_before_deploy import PreDeployResult, PreDeployValidator
from src.automation.webhook_app import app as webhook_app
from src.automation.webhook_app import get_paper_broker, get_signal_log

__all__ = [
    "PaperBroker",
    "PaperTrade",
    "PreDeployResult",
    "PreDeployValidator",
    "SchedulerConfig",
    "TaskScheduler",
    "get_paper_broker",
    "get_signal_log",
    "webhook_app",
]
