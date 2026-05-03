"""MQL5 Expert Advisor code generator."""
from __future__ import annotations

from pathlib import Path
from typing import Any

from src.strategies.base import BaseStrategy, StrategyParams
from src.backtest.metrics import BacktestMetrics


class MQL5Exporter:
    """Generate an MQL5 Expert Advisor from a strategy instance."""

    def generate(
        self,
        strategy: BaseStrategy,
        params: StrategyParams,
        metrics: BacktestMetrics,
    ) -> str:
        """Produce a complete MQL5 EA source file."""
        rules = strategy.get_mql5_rules()
        sections = [
            self._build_header(params, metrics),
            self._build_inputs(params),
            self._build_globals(),
            self._build_on_init(rules),
            self._build_on_deinit(),
            self._build_on_tick(rules),
        ]
        return "\n".join(sections) + "\n"

    def save(self, code: str, output_dir: str) -> Path:
        """Write generated EA to *output_dir*/expert.mq5."""
        out = Path(output_dir)
        out.mkdir(parents=True, exist_ok=True)
        path = out / "expert.mq5"
        path.write_text(code, encoding="utf-8")
        return path

    # ── private helpers ──────────────────────────────────────────────

    def _build_header(
        self, params: StrategyParams, metrics: BacktestMetrics
    ) -> str:
        lines = [
            "//+------------------------------------------------------------------+",
            f"//| Expert Advisor: {params.name}",
            "//+------------------------------------------------------------------+",
            f"// Total Trades : {metrics.total_trades}",
            f"// Win Rate     : {metrics.win_rate:.2%}",
            f"// Profit Factor: {metrics.profit_factor:.2f}",
            f"// Sharpe Ratio : {metrics.sharpe_ratio:.2f}",
            f"// Max Drawdown : {metrics.max_drawdown_pct:.2%}",
            f"// Expectancy   : {metrics.expectancy:.4f}",
            f"// Total PnL    : {metrics.total_pnl:.2f}",
            f"// Return %     : {metrics.return_pct:.2%}",
            "",
            '#property strict',
            '#include <Trade\\Trade.mqh>',
        ]
        return "\n".join(lines)

    def _build_inputs(self, params: StrategyParams) -> str:
        lines = ["\n// ── Input Parameters ──"]
        for key, value in params.params.items():
            if isinstance(value, bool):
                lines.append(f"input bool {key} = {'true' if value else 'false'};")
            elif isinstance(value, int):
                lines.append(f"input int {key} = {value};")
            elif isinstance(value, float):
                lines.append(f"input double {key} = {value};")
            else:
                lines.append(f'input string {key} = "{value}";')
        return "\n".join(lines)

    def _build_globals(self) -> str:
        return "\n".join([
            "",
            "// ── Globals ──",
            "CTrade trade;",
            "int magicNumber = 123456;",
        ])

    def _build_on_init(self, rules: dict[str, str]) -> str:
        indicator = rules.get("indicator", "")
        indicator_lines = _indent(indicator, 4)
        return "\n".join([
            "",
            "//+------------------------------------------------------------------+",
            "//| Expert initialization function                                     |",
            "//+------------------------------------------------------------------+",
            "int OnInit()",
            "{",
            "    trade.SetExpertMagicNumber(magicNumber);",
            indicator_lines,
            "    return(INIT_SUCCEEDED);",
            "}",
        ])

    def _build_on_deinit(self) -> str:
        return "\n".join([
            "",
            "//+------------------------------------------------------------------+",
            "//| Expert deinitialization function                                   |",
            "//+------------------------------------------------------------------+",
            "void OnDeinit(const int reason)",
            "{",
            "}",
        ])

    def _build_on_tick(self, rules: dict[str, str]) -> str:
        entry_long = _indent(rules.get("entry_long", ""), 4)
        entry_short = _indent(rules.get("entry_short", ""), 4)
        exit_long = _indent(rules.get("exit_long", ""), 4)
        exit_short = _indent(rules.get("exit_short", ""), 4)
        return "\n".join([
            "",
            "//+------------------------------------------------------------------+",
            "//| Expert tick function                                               |",
            "//+------------------------------------------------------------------+",
            "void OnTick()",
            "{",
            "    // ── Entry Conditions ──",
            entry_long,
            entry_short,
            "",
            "    // ── Exit Rules (SL / TP) ──",
            exit_long,
            exit_short,
            "",
            "    // ── Execution ──",
            "    if(longCond)",
            "    {",
            "        trade.Buy(0.1, _Symbol, 0, sl_long, tp_long);",
            "    }",
            "    if(shortCond)",
            "    {",
            "        trade.Sell(0.1, _Symbol, 0, sl_short, tp_short);",
            "    }",
            "}",
        ])


def _indent(text: str, spaces: int) -> str:
    """Indent each line of *text* by *spaces*."""
    prefix = " " * spaces
    return "\n".join(f"{prefix}{line}" for line in text.splitlines()) if text else ""
