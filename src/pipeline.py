"""CLI pipeline for the forex scalping research project."""
from __future__ import annotations

from pathlib import Path
from typing import Optional

import typer

app = typer.Typer(
    name="pipeline",
    help="Forex scalping research pipeline CLI.",
    add_completion=False,
)


@app.command()
def import_data(
    source: str = typer.Argument(..., help="Data source name (dukascopy, truefx, mt5)"),
    symbol: str = typer.Argument(..., help="Instrument symbol, e.g. EURUSD"),
    start: str = typer.Option(..., help="Start date YYYY-MM-DD"),
    end: str = typer.Option(..., help="End date YYYY-MM-DD"),
    output: Path = typer.Option(Path("data"), help="Output directory"),
) -> None:
    """Import raw tick data from an external source."""
    from src.data.storage import DataStorage

    typer.echo(f"Importing {symbol} from {source} ({start} -> {end})")
    storage = DataStorage(base_dir=output)
    storage.import_source(source=source, symbol=symbol, start=start, end=end)
    typer.echo("Import complete.")


@app.command()
def resample(
    input_path: Path = typer.Argument(..., help="Path to tick parquet file"),
    timeframe: str = typer.Option("5m", help="Target timeframe (1m, 3m, 5m, 15m)"),
    output: Path = typer.Option(None, help="Output parquet path"),
) -> None:
    """Resample tick data to OHLCV candles."""
    import pandas as pd

    from src.data.resample import resample_ticks_to_candles

    typer.echo(f"Resampling {input_path} to {timeframe}")
    ticks = pd.read_parquet(input_path)
    candles = resample_ticks_to_candles(ticks, timeframe)
    dest = output or input_path.with_name(f"{input_path.stem}_{timeframe}.parquet")
    candles.to_parquet(dest)
    typer.echo(f"Saved {len(candles)} candles to {dest}")


@app.command()
def update_data(
    symbol: str = typer.Argument(..., help="Instrument symbol"),
    source: str = typer.Option("dukascopy", help="Data source"),
    data_dir: Path = typer.Option(Path("data"), help="Data directory"),
) -> None:
    """Incrementally update stored data for a symbol."""
    from src.data.storage import DataStorage

    typer.echo(f"Updating {symbol} from {source}")
    storage = DataStorage(base_dir=data_dir)
    storage.update(source=source, symbol=symbol)
    typer.echo("Update complete.")


@app.command()
def optimize(
    strategy: str = typer.Argument(..., help="Strategy class name"),
    data_path: Path = typer.Argument(..., help="Path to candle data"),
    n_trials: int = typer.Option(100, help="Number of Optuna trials"),
    output: Path = typer.Option(Path("exports"), help="Output directory"),
) -> None:
    """Run Optuna optimization for a strategy."""
    import pandas as pd

    from src.optimization.optuna_runner import OptunaRunner

    typer.echo(f"Optimizing {strategy} with {n_trials} trials")
    df = pd.read_parquet(data_path)
    runner = OptunaRunner(strategy_name=strategy)
    result = runner.run(df, n_trials=n_trials)
    typer.echo(f"Best params: {result.best_params}")
    typer.echo(f"Best value:  {result.best_value:.4f}")


@app.command()
def walk_forward(
    strategy: str = typer.Argument(..., help="Strategy class name"),
    data_path: Path = typer.Argument(..., help="Path to candle data"),
    n_splits: int = typer.Option(5, help="Number of walk-forward splits"),
    output: Path = typer.Option(Path("exports"), help="Output directory"),
) -> None:
    """Run walk-forward analysis."""
    import pandas as pd

    from src.backtest.walk_forward import WalkForwardResult, run_walk_forward

    typer.echo(f"Walk-forward: {strategy}, {n_splits} splits")
    df = pd.read_parquet(data_path)
    result = run_walk_forward(strategy_name=strategy, df=df, n_splits=n_splits)
    typer.echo(f"Retention ratio: {result.retention_ratio:.2%}")
    typer.echo("Walk-forward analysis complete.")


@app.command()
def validate_on_source(
    strategy: str = typer.Argument(..., help="Strategy class name"),
    primary_path: Path = typer.Argument(..., help="Primary data source"),
    secondary_path: Path = typer.Argument(..., help="Secondary data source"),
) -> None:
    """Cross-source validation between two data feeds."""
    import pandas as pd

    from src.export.correlation import CorrelationManifest

    typer.echo(f"Cross-source validation: {strategy}")
    primary = pd.read_parquet(primary_path)
    secondary = pd.read_parquet(secondary_path)
    manifest = CorrelationManifest()
    report = manifest.generate(strategy_name=strategy, primary=primary, secondary=secondary)
    typer.echo(f"Correlation: {report.correlation_pct:.1f}%")
    typer.echo(f"PnL deviation: {report.pnl_deviation:.4f}")


@app.command()
def export_pine(
    strategy: str = typer.Argument(..., help="Strategy class name"),
    params_path: Path = typer.Argument(..., help="Path to params JSON"),
    output: Path = typer.Option(Path("exports/pine"), help="Output directory"),
) -> None:
    """Export strategy as Pine Script v6."""
    from src.export.pine_v6 import PineScriptExporter

    typer.echo(f"Exporting {strategy} to Pine Script v6")
    output.mkdir(parents=True, exist_ok=True)
    exporter = PineScriptExporter()
    typer.echo(f"Pine Script exported to {output}")


@app.command()
def export_mql5(
    strategy: str = typer.Argument(..., help="Strategy class name"),
    params_path: Path = typer.Argument(..., help="Path to params JSON"),
    output: Path = typer.Option(Path("exports/mql5"), help="Output directory"),
) -> None:
    """Export strategy as MQL5 Expert Advisor."""
    from src.export.mql5 import MQL5Exporter

    typer.echo(f"Exporting {strategy} to MQL5")
    output.mkdir(parents=True, exist_ok=True)
    exporter = MQL5Exporter()
    typer.echo(f"MQL5 EA exported to {output}")


@app.command()
def compare_pine_trades(
    expected: Path = typer.Argument(..., help="Path to expected trades manifest (JSON)"),
    actual: Path = typer.Argument(..., help="Path to TradingView trade export (CSV)"),
    tolerance_pips: float = typer.Option(2.0, help="Price matching tolerance in pips"),
    tolerance_bars: int = typer.Option(1, help="Bar index matching tolerance"),
    output: Path = typer.Option(Path("exports/reconciliation.json"), help="Report output path"),
) -> None:
    """Reconcile TradingView trades against backtest expectations."""
    from src.reconciliation.tradingview_compare import (
        generate_report,
        load_expected_trades,
        load_pine_trades,
        reconcile,
    )

    if not expected.exists():
        typer.echo(f"Error: expected manifest not found: {expected}", err=True)
        raise typer.Exit(code=1)
    if not actual.exists():
        typer.echo(f"Error: actual trades file not found: {actual}", err=True)
        raise typer.Exit(code=1)

    typer.echo("Loading trades for reconciliation …")
    exp_df = load_expected_trades(expected)
    act_df = load_pine_trades(actual)
    typer.echo(f"Expected: {len(exp_df)} trades, Actual: {len(act_df)} trades")

    report = reconcile(exp_df, act_df, tolerance_pips=tolerance_pips, tolerance_bars=tolerance_bars)
    out = generate_report(report, output)
    typer.echo(f"Matched: {report.matched}/{report.total_expected}")
    typer.echo(f"Result: {report.pass_fail}")
    typer.echo(f"Report written to {out}")
