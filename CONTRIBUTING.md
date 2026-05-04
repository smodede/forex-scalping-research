# Contributing

## Development Setup

```bash
# Clone and install
git clone https://github.com/YOUR_USERNAME/forex-scalping-research.git
cd forex-scalping-research
pip install -e .

# Run tests
pytest tests/ -v
```

## Code Style

- Use type hints for all function signatures
- Follow PEP 8 (enforced by ruff)
- Use Pydantic models for data validation at boundaries
- Write tests for all new features

## Pull Request Process

1. Create a feature branch from `main`
2. Make your changes with tests
3. Ensure all tests pass: `pytest tests/ -v`
4. Ensure no lookahead bias: `pytest tests/test_no_lookahead.py -v`
5. Open a PR with a clear description

## Architecture Guidelines

- **No lookahead bias** — Never use future data in signal generation
- **Temporal ordering** — Always respect time ordering in data operations
- **Cost-aware** — Include spread and commission in all backtests
- **Reproducible** — Use seeds for random operations, log all parameters
