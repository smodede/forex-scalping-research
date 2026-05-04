# Forex Scalping Research Pipeline

A systematic, data-driven research pipeline for developing, optimizing, and validating forex scalping strategies — from raw tick data to production-ready trading signals.

## Overview

This project implements a complete quantitative research workflow:

```
Raw Tick Data → Feature Engineering → Strategy Optimization → Walk-Forward Validation
    → Robustness Testing → Export (Pine Script / MQL5) → Paper Trading → Live Deployment
```

### Key Principles

- **No lookahead bias** — strict temporal separation enforced at every stage
- **Multi-source validation** — strategies must pass on independent data sources
- **Monte Carlo robustness** — parameter sensitivity and equity curve randomization
- **5-level gating** — strategies must clear all gates before deployment

---

## Quick Start

### Requirements

- Python 3.11+
- pip (or uv)

### Installation

```bash
# Clone the repository
git clone https://github.com/YOUR_USERNAME/forex-scalping-research.git
cd forex-scalping-research

# Install in development mode
pip install -e .

# Verify
python -m src --help
```

### Run the Full Pipeline

```bash
# 1. Import and validate data
python -m src data import --source dukascopy --pair EURUSD --timeframe tick

# 2. Optimize strategy parameters
python -m src optimize --strategy breakout-scalper --trials 500

# 3. Run walk-forward analysis
python -m src validate walk-forward --splits 5 --train-ratio 0.7

# 4. Export to TradingView
python -m src export pine --strategy breakout-scalper --version v6

# 5. Start paper trading
python -m src paper-trade --webhook-port 8080
```

---

## Project Structure

```
├── src/
│   ├── __main__.py          # CLI entry point
│   ├── pipeline.py          # Typer CLI app
│   ├── data/                # Data ingestion & validation
│   │   ├── dukascopy.py     # Dukascopy tick data import
│   │   ├── truefx.py        # TrueFX tick data import
│   │   ├── mt5_import.py    # MetaTrader 5 data import
│   │   ├── resample.py      # Tick → OHLCV resampling
│   │   ├── validate.py      # Schema & quality checks
│   │   └── schema.py        # Pydantic data models
│   ├── features/            # Feature engineering
│   │   ├── indicators.py    # Technical indicators
│   │   ├── sessions.py      # Trading session detection
│   │   ├── spread.py        # Spread analysis
│   │   └── volatility.py    # Volatility features
│   ├── strategies/          # Strategy implementations
│   │   ├── base.py          # Abstract strategy interface
│   │   ├── breakout_scalper.py
│   │   ├── mean_reversion_scalper.py
│   │   └── trend_pullback_scalper.py
│   ├── backtest/            # Backtesting engine
│   │   ├── engine.py        # Event-driven backtest
│   │   ├── costs.py         # Spread + commission model
│   │   ├── execution.py     # Order execution simulation
│   │   ├── metrics.py       # Performance metrics
│   │   └── walk_forward.py  # Walk-forward analysis
│   ├── optimization/        # Parameter optimization
│   │   ├── optuna_runner.py # Optuna-based search
│   │   ├── objective.py     # Optimization objective
│   │   ├── search_space.py  # Parameter bounds
│   │   ├── robustness.py    # Monte Carlo & sensitivity
│   │   └── selection.py     # Strategy selection criteria
│   ├── export/              # Strategy export
│   │   ├── pine_v6.py       # TradingView Pine Script v6
│   │   ├── mql5.py          # MetaTrader 5 Expert Advisor
│   │   ├── correlation.py   # Cross-export correlation
│   │   └── payloads.py      # Webhook payload formats
│   ├── reconciliation/      # Live vs backtest comparison
│   │   └── tradingview_compare.py
│   └── automation/          # Deployment & paper trading
│       ├── webhook_app.py   # FastAPI webhook server
│       ├── paper_broker.py  # Paper trading broker
│       ├── scheduler.py     # Automated scheduling
│       └── validation_before_deploy.py
├── config/
│   ├── default.yaml         # Default pipeline settings
│   ├── pairs.yaml           # Currency pair configurations
│   ├── data_sources.yaml    # Data source credentials & paths
│   ├── strategy_search.yaml # Optimization search spaces
│   └── validation_gates.yaml # Gating criteria thresholds
├── tests/                   # Test suite
│   ├── test_data_schema.py
│   ├── test_data_validation.py
│   ├── test_resampling.py
│   ├── test_no_lookahead.py
│   ├── test_cost_model.py
│   ├── test_strategy_rules.py
│   ├── test_walk_forward.py
│   ├── test_pine_export.py
│   ├── test_correlation_manifest.py
│   ├── test_tradingview_reconciliation.py
│   └── test_webhook_validation.py
├── data/                    # Data directory (gitignored contents)
│   ├── raw/                 # Raw tick data files
│   ├── processed/           # Cleaned OHLCV parquet files
│   └── cache/               # Intermediate cache
├── reports/                 # Generated reports (gitignored)
│   ├── backtests/
│   ├── walk_forward/
│   ├── robustness/
│   ├── reconciliation/
│   └── paper_trading/
├── exports/                 # Exported strategies
│   ├── tradingview/         # Pine Script files
│   └── metatrader/          # MQL5 EA files
├── pyproject.toml           # Project metadata & dependencies
└── .github/
    └── workflows/
        └── ci.yml           # Continuous integration
```

---

## Pipeline Stages

### 1. Data Acquisition

Import tick-level data from multiple sources for cross-validation:

| Source     | Format     | Notes                          |
|-----------|-----------|--------------------------------|
| Dukascopy | CSV/Binary | Free historical tick data      |
| TrueFX    | CSV        | Independent validation source  |
| MT5       | Export     | Broker-specific spread data    |

### 2. Strategy Optimization

- **Sampler:** Optuna TPE (Tree-structured Parzen Estimator)
- **Trials:** 500 default, configurable
- **Objective:** Risk-adjusted return (Sortino / Calmar weighted)

### 3. Walk-Forward Validation

- 5 sequential splits with 70/30 train/test ratio
- 100-bar gap between train and test to prevent leakage
- Strategy must be profitable in ≥4/5 out-of-sample windows

### 4. Validation Gates

| Gate | Requirement |
|------|------------|
| In-Sample | Positive expectancy, Sharpe > 1.0 |
| Out-of-Sample | Profitable in ≥80% of windows |
| Cross-Source | Consistent on Dukascopy AND TrueFX |
| Monte Carlo | 95th percentile drawdown < 2× baseline |
| Pre-Deploy | Paper trade ≥5 days, within tolerance |

### 5. Export & Reconciliation

Strategies are exported to Pine Script v6 and/or MQL5, then reconciled against the Python backtest to ensure consistency within acceptable tolerance (±2 pips, ±1 bar).

---

## Configuration

All settings are in `config/`. Copy and customize:

```bash
cp config/default.yaml config/local.yaml
# Edit config/local.yaml with your settings
```

Key configuration files:
- `default.yaml` — Pipeline defaults (timeframes, risk params)
- `pairs.yaml` — Which pairs to research
- `strategy_search.yaml` — Optuna search space bounds
- `validation_gates.yaml` — Pass/fail thresholds for each gate

---

## Testing

```bash
# Run all tests
pytest tests/ -v

# Run specific test categories
pytest tests/test_no_lookahead.py -v    # Verify no lookahead bias
pytest tests/test_walk_forward.py -v     # Walk-forward logic
pytest tests/test_pine_export.py -v      # Export correctness
```

---

## Development

```bash
# Install with dev dependencies
pip install -e ".[dev]"

# Type checking
mypy src/

# Linting
ruff check src/ tests/
```

---

## Architecture Decisions

1. **Pydantic models everywhere** — Schema validation at data boundaries
2. **Parquet for storage** — Columnar, compressed, fast reads
3. **Optuna for optimization** — Bayesian search with pruning
4. **FastAPI for webhooks** — Async, typed, auto-documented
5. **Walk-forward over simple backtest** — Realistic out-of-sample evaluation

---

## License

MIT License — see [LICENSE](LICENSE) for details.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development guidelines.
