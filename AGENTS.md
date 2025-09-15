# Repository Guidelines

## Project Structure & Module Organization
- `src/`: Cairo contracts (`lib.cairo` main entry, plus `interfaces.cairo`, `data.cairo`, `structs.cairo`).
- `tests/`: Starknet Foundry tests (e.g., `test_beast_mode.cairo`).
- `scripts/`: Helper scripts (deployment/ops).
- `Scarb.toml`: Build, deps, targets. `snfoundry.toml`: Foundry test config. `.tool-versions`: required toolchain.

## Build, Test, and Development Commands
- Build: `scarb build` — compile contracts (expect current size warning).
- Format: `scarb fmt -w` — apply canonical Cairo formatting.
- Test (Foundry): `snforge test` or `scarb test` — run all tests.
- Test verbose/specific: `snforge test -v` or `snforge test <name>`.
- Coverage: `snforge test --coverage && lcov --summary coverage/coverage.lcov`.

## Coding Style & Naming Conventions
- Language: Cairo 2.10.1. Use 4‑space indentation, no tabs.
- Names: modules/files `snake_case`; functions `snake_case`; types `CamelCase`; constants `SCREAMING_SNAKE_CASE`.
- Visibility: prefix intentionally unused vars with `_`.
- Imports: remove unused; group std/external/internal in that order.
- Always run `scarb fmt -w` before committing.

## Testing Guidelines
- Framework: Starknet Foundry (`snforge`), with Cairo contracts under `src/` and tests in `tests/`.
- Naming: test files `test_*.cairo`; test funcs start with `test_`.
- Coverage: maintain ≥ 80% on changed code and keep overall ≥ current baseline (≈84.3%).
- Forked tests: ensure `snfoundry.toml` fork endpoints are valid when running mainnet‑dependent tests.

## Commit & Pull Request Guidelines
- Commits: concise, imperative, lowercase summaries (e.g., `add jackpot`, `update tests`). Aim ≤ 72 chars; group related changes.
- PRs must include:
  - Clear description, rationale, and linked issues.
  - Test plan with commands and results; screenshots/logs if relevant.
  - Assurance that `scarb build`, `scarb fmt -w`, and `snforge test` pass; coverage summary meets thresholds.

## Security & Configuration Tips
- Do not hardcode secrets or private RPC URLs; use env/config files not committed to VCS.
- Network forks: validate endpoints in `snfoundry.toml` before running forked tests.
- Known issue: contract size warning is expected; do not suppress other warnings.
