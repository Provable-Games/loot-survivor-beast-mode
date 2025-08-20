# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Cairo/Starknet smart contract implementing Beast Mode dungeon for Loot Survivor game. Uses Cairo 2.10.1 with Scarb build system and Starknet Foundry for testing.

## Commands

### Build

```bash
scarb build
```

Note: Contract currently exceeds Starknet size limit (7.5MB vs 4MB allowed) - this warning is expected.

### Test

```bash
# Run all tests
snforge test
# or
scarb test

# Run specific test
snforge test test_name

# Run tests with verbose output
snforge test -v

# Run tests with coverage
snforge test --coverage

# Check coverage percentage
lcov --summary coverage/coverage.lcov
```

### Check Code Coverage

To verify code coverage percentage:

```bash
# Generate coverage data
snforge test --coverage

# View coverage summary
lcov --summary coverage/coverage.lcov

# Enforce minimum coverage (will exit with error if below 80%)
lcov --summary coverage/coverage.lcov --fail-under-lines 80
```

**IMPORTANT**: Before submitting a PR, ensure your code coverage is at least equal to or higher than the main branch coverage. Current baseline: 84.3% line coverage.

### Format

```bash
scarb fmt
# or format and write changes
scarb fmt -w
```

## Architecture

### Contract Structure

The main contract (`src/lib.cairo`) implements:
- **TicketBooth Component**: Access control and payment processing for dungeon entry
- **Beast Claiming**: NFT minting with 4% rare trait generation (shiny/animated)
- **Legacy Airdrop**: Migration from mainnet legacy beasts using VRF randomization
- **Reward Tokens**: Level-based token rewards with 24-hour time delay

### Key Interfaces

- `IBeastSystems`: Beast validation and NFT minting
- `IAdventurerSystems`: Adventurer data retrieval from game contract
- `ILegacyBeasts`: Legacy beast contract interaction (mainnet fork)
- `IBeastMode`: Main contract interface

### External Dependencies

- `game_components_metagame`: TicketBooth for access control
- `beasts_nft`: Beast NFT minting interface
- `openzeppelin`: ERC721/ERC20 standards and Ownable pattern
- VRF integration via Cartridge provider for randomization

### Test Structure

Tests in `tests/test_beast_mode.cairo` cover:
- Beast claiming with mint parameter validation
- Rare trait generation (4% for new, 8% for airdrops)
- Airdrop system with VRF and block delay validation
- Reward token claiming with time delays and ownership checks
- Security: access control, overflow protection, edge cases

## Testing Requirements

**CRITICAL: This project enforces a minimum 80% test coverage using cairo-coverage. Any code changes without adequate tests will fail CI validation.**

When implementing features:

1. Write comprehensive unit tests for all new functions
2. Include edge cases, boundary conditions, and failure scenarios
3. Add integration tests for cross-contract interactions
4. Test with mainnet fork for legacy beast interactions
5. Run coverage check locally before pushing

## Completion Criteria

**Definition of complete**: A task is ONLY complete when `scarb build && scarb test` runs with zero warnings and zero errors.

When encountering issues:

1. Fix warnings/errors sequentially
2. Verify each fix with `scarb build && scarb test`
3. Ensure 80%+ test coverage for modified files
4. Only consider work complete when all criteria are met

### Workflow checklist:

- [ ] Code changes implemented
- [ ] `scarb build` passes with zero warnings (except known contract size warning)
- [ ] `scarb fmt -w` to format the codebase
- [ ] `scarb test` passes with zero warnings and all tests green
- [ ] All unused imports removed
- [ ] All unused variables prefixed with `_` or removed
- [ ] `lcov --summary coverage/coverage.lcov` shows 80%+ coverage for project
- [ ] New tests added for any new functionality

**Do not consider any task complete until ALL criteria are met.**

## Pull Request Checklist

**NEVER create a pull request without completing ALL items:**

1. **Run all tests**: `scarb test`
   - Verify test count matches or exceeds baseline (34 tests)
   - Fix any test failures before proceeding
   
2. **Check build**: `scarb build`
   - Fix ALL warnings (except known contract size warning)
   - Zero tolerance for new warnings
   
3. **Format code**: `scarb fmt -w`
   - Must be run before final commit

4. **Verify coverage**:
   ```bash
   snforge test --coverage && lcov --summary coverage/coverage.lcov
   ```
   - Modified files must maintain 80%+ coverage
   - Overall coverage must be ≥ 84.3% (current main branch baseline)
   - If coverage drops below baseline, add more tests before creating PR

5. **Final verification**: Run `scarb build && scarb test` one last time
   - This MUST complete with zero errors and zero new warnings

**If ANY step fails, DO NOT create the PR. Fix the issues first.**

After submitting a pull request, sleep for 5 minutes then review github actions to ensure the build and test pass. Also review and respond to all comments. If changes are warranted, push the changes, sleep for 5 minutes, then re-review. Repeat this process until all checks are passing and there are no unresolved comments.

### Honesty About Results

**ALWAYS provide honest assessment of your work:**

- If you break tests, say so clearly
- If you reduce passing test count, that's a FAILURE, not a success
- Success means: MORE passing tests, not fewer
- Better to admit failure than mislead about results

## Known Issues

- Contract size exceeds Starknet limit (7.5MB vs 4MB) - this warning is expected
- Tests currently use mainnet fork for legacy beast integration - ensure `snfoundry.toml` fork configuration is correct