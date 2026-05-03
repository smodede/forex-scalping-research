"""Pine Script v6 strategy code generator."""
from __future__ import annotations

from pathlib import Path
from typing import Any

from src.strategies.base import BaseStrategy, StrategyParams
from src.backtest.metrics import BacktestMetrics


class PineScriptExporter:
    """Generate Pine Script v6 strategy source from a strategy instance."""

    def generate(
        self,
        strategy: BaseStrategy,
        params: StrategyParams,
        metrics: BacktestMetrics,
    ) -> str:
        """Produce a complete //@version=6 strategy script."""
        rules = strategy.get_pine_script_rules()
        sections = [
            self._build_header(params, metrics),
            self._build_inputs(params),
            "",
            "// ── Indicator Logic ──",
            rules.get("indicator", ""),
            "",
            "// ── Entry Conditions ──",
            rules.get("entry_long", ""),
            rules.get("entry_short", ""),
            "",
            "// ── Exit Rules (SL / TP) ──",
            rules.get("exit_long", ""),
            rules.get("exit_short", ""),
            "",
            self._build_execution(rules),
        ]
        return "\n".join(sections) + "\n"

    def save(self, code: str, output_dir: str) -> Path:
        """Write generated Pine Script to *output_dir*/strategy.pine."""
        out = Path(output_dir)
        out.mkdir(parents=True, exist_ok=True)
        path = out / "strategy.pine"
        path.write_text(code, encoding="utf-8")
        return path

    # ── private helpers ──────────────────────────────────────────────

    def _build_header(
        self, params: StrategyParams, metrics: BacktestMetrics
    ) -> str:
        """Version tag, strategy declaration, and metrics comment block."""
        lines = [
            "//@version=6",
            f'strategy("{params.name}", overlay=true, default_qty_type=strategy.percent_of_equity, default_qty_value=100)',
            "",
            "// ── Backtest Metrics ──",
            f"// Total Trades : {metrics.total_trades}",
            f"// Win Rate     : {metrics.win_rate:.2%}",
            f"// Profit Factor: {metrics.profit_factor:.2f}",
            f"// Sharpe Ratio : {metrics.sharpe_ratio:.2f}",
            f"// Sortino Ratio: {metrics.sortino_ratio:.2f}",
            f"// Max Drawdown : {metrics.max_drawdown_pct:.2%}",
            f"// Calmar Ratio : {metrics.calmar_ratio:.2f}",
            f"// Expectancy   : {metrics.expectancy:.4f}",
            f"// Total PnL    : {metrics.total_pnl:.2f}",
            f"// Return %     : {metrics.return_pct:.2%}",
        ]
        return "\n".join(lines)

    def _build_inputs(self, params: StrategyParams) -> str:
        """Generate input() declarations for each strategy parameter."""
        lines = ["\n// ── Inputs ──"]
        for key, value in params.params.items():
            pine_name = key
            if isinstance(value, bool):
                lines.append(
                    f'{pine_name} = input.bool({str(value).lower()}, title="{key}")'
                )
            elif isinstance(value, int):
                lines.append(
                    f'{pine_name} = input.int({value}, title="{key}")'
                )
            elif isinstance(value, float):
                lines.append(
                    f'{pine_name} = input.float({value}, title="{key}")'
                )
            else:
                lines.append(
                    f'{pine_name} = input.string("{value}", title="{key}")'
                )
        return "\n".join(lines)

    def _build_execution(self, rules: dict[str, str]) -> str:
        """Emit strategy.entry / strategy.exit and alertcondition() calls."""
        lines = [
            "// ── Execution ──",
            'if longCond',
            '    strategy.entry("Long", strategy.long)',
            '    strategy.exit("Exit Long", "Long", stop=sl_long, limit=tp_long)',
            "",
            'if shortCond',
            '    strategy.entry("Short", strategy.short)',
            '    strategy.exit("Exit Short", "Short", stop=sl_short, limit=tp_short)',
            "",
            "// ── Alerts ──",
            'alertcondition(longCond, title="Long Entry", message="Long entry triggered")',
            'alertcondition(shortCond, title="Short Entry", message="Short entry triggered")',
        ]
        return "\n".join(lines)
