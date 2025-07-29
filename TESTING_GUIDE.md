# Beast Mode Airdrop Testing Guide

This guide explains how to test the `airdrop_legacy_beasts` functionality, including mainnet fork testing.

## Current Test Coverage

The test suite includes **13 passing tests** covering:

### Basic Unit Tests (`tests/test_airdrop.cairo`)
- ✅ `test_deploy_beast_mode_contract` - Contract deployment with proper constructor
- ✅ `test_vrf_mocking` - VRF randomness mocking using hardcoded values  
- ✅ `test_block_number_manipulation` - Timing controls for airdrop functionality
- ✅ `test_mock_legacy_beast_calls` - Legacy beast contract interaction mocking
- ✅ `test_mock_beast_systems_calls` - Beast systems contract mocking
- ✅ `test_mock_beasts_nft_calls` - NFT minting functionality mocking
- ✅ `test_trait_probability_calculation` - 8% shiny/animated trait probability logic
- ✅ `test_address_constants` - Test constants and addresses validation

### Mainnet Integration Tests (`tests/test_airdrop_mainnet_fork.cairo`)
- ✅ `test_mainnet_fork_setup` - Basic mainnet fork setup verification
- ✅ `test_legacy_beasts_address_integration` - Real legacy beasts contract integration
- ✅ `test_vrf_mainnet_integration` - VRF integration with mainnet
- ✅ `test_contract_addresses_setup` - Address configuration validation  
- ✅ `test_mocking_works_on_mainnet_fork` - Mock setup on mainnet fork

## Running Tests

### All Tests
```bash
scarb test
```

### Specific Test
```bash 
scarb test test_name
```

## Real Contract Addresses

### Mainnet Contracts
- **Legacy Beasts**: `0x0158160018d590d93528995b340260e65aedd76d28a686e9daa5c4e8fad0c5dd`
- **Cartridge VRF**: `0x051fea4450da9d6aee758bdeba88b2f665bcbf549d2c61421aa724e9ac0ced8f`

### Missing Contracts (Need Deployment)
- **Beast NFT Contract**: Not yet deployed - placeholder `0x789` used in tests
- **Beast Systems Contract**: Address needed - placeholder `0x456` used in tests

## Mainnet Fork Testing

### ✅ Mainnet Fork Testing - ACTIVE!

**Status**: ✅ **WORKING** with `snforge` version `0.46.0`

### Configuration
Fork configuration is set up in `Scarb.toml`:

```toml
[tool.snforge]
fork = [
    { name = "mainnet", url = "https://starknet-mainnet.public.blastapi.io/rpc/v0_8", block_id = { tag = "latest" } }
]
```

### Fork Testing Features - NOW AVAILABLE! 

✅ **All 13 tests pass** including 5 mainnet fork tests
✅ **Real mainnet connection**: Block number `1646436` 
✅ **Legacy beasts contract integration**: Tests run against real mainnet contract
✅ **VRF contract integration**: Tests interact with real Cartridge VRF

### Running Fork Tests

**All Tests (including fork tests):**
```bash
scarb test
```

**Only Fork Tests:**
```bash
scarb test mainnet_fork
```

**Specific Fork Test:**
```bash
scarb test test_mainnet_fork_setup
```

### Real Mainnet Integration Testing:
- ✅ Tests deploy contracts with real legacy beasts address
- ✅ Tests verify real VRF contract integration  
- ✅ Tests validate address configuration against mainnet
- ✅ Tests mock setup works correctly on mainnet fork
- ✅ Ready for real legacy beast data retrieval when needed

## Test Architecture

### Mocking Strategy

**What We Mock:**
- **VRF Provider**: Uses hardcoded seed `12345` instead of random values
- **Beast NFT Contract**: Mocks `mint()` calls (contract not deployed yet)  
- **Beast Systems Contract**: Mocks `validate_collectable()` and `premint_collectable()`
- **Legacy Beast Data**: Mocks beast properties when not fork testing

**What We Test Against Real Mainnet:**
- **Legacy Beasts Contract**: Real contract at `0x0158160018d590d93528995b340260e65aedd76d28a686e9daa5c4e8fad0c5dd`
- **VRF Contract**: Real Cartridge VRF at `0x051fea4450da9d6aee758bdeba88b2f665bcbf549d2c61421aa724e9ac0ced8f`

### Test Flow

1. **Deploy beast_mode contract** with real legacy beasts address
2. **Mock non-deployed contracts** (beast NFT, beast systems)
3. **Test airdrop functionality**:
   - `initiate_airdrop()` - Sets up VRF seed and block timing
   - `airdrop_legacy_beasts()` - Processes legacy beasts in batches
4. **Verify behavior**:
   - Proper timing constraints (10+ block wait)
   - Beast data retrieval from legacy contract
   - Trait generation (8% shiny/animated probability)
   - NFT minting to original owners

## Key Testing Features

### VRF Determinism
```cairo
// Mock VRF to return predictable seed
let vrf_address = contract_address_const::<VRF_ADDRESS>();
mock_call(vrf_address, selector!("seed"), 12345_felt252, 1);
```

### Trait Probability Verification
```cairo
// Test 8% probability calculation
let shiny_seed = (beast_seed & 0xFFFFFFFF_u64) % 10000_u64;
let shiny = if shiny_seed < 800_u64 { 1_u8 } else { 0_u8 };
```

### Timing Controls
```cairo
// Test block number requirements
start_cheat_block_number_global(100);
beast_mode_contract.initiate_airdrop(); // Sets airdrop_block = 200
start_cheat_block_number_global(195);   // Wait required period
beast_mode_contract.airdrop_legacy_beasts(5);
```

## Future Enhancements

When real contracts are deployed:

1. **Update test addresses** with real deployed contracts
2. **Enable fork testing** for end-to-end integration tests  
3. **Add comprehensive edge case testing** against real data
4. **Performance testing** with large airdrop batches

## Dependencies

- **Cairo**: 2.10.1
- **Scarb**: Latest
- **snforge**: 0.45.0 (fork testing requires newer version)
- **Starknet Mainnet RPC**: `https://starknet-mainnet.public.blastapi.io`