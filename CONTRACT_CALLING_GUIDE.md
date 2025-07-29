# Contract Calling Methods in snforge 0.46.0

This guide provides comprehensive information on how to make contract calls in snforge 0.46.0 tests, since `call_contract_syscall` is not available for import.

## Key Finding: Modern Dispatcher Pattern

The modern approach in snforge 0.46.0 uses **auto-generated dispatchers** from interfaces, which is exactly what the beast_mode contract already implements correctly.

## 1. Interface-Based Dispatcher Pattern (Recommended)

### How It Works

When you define a Starknet interface using `#[starknet::interface]`, the Cairo compiler automatically generates:
- `IYourContractDispatcher` struct
- `IYourContractDispatcherTrait` trait

### Example: Creating and Using Dispatchers

```cairo
use snforge_std::{declare, ContractClassTrait, DeclareResultTrait};
use beast_mode::{IBeastModeDispatcher, IBeastModeDispatcherTrait};

#[test]
fn test_contract_calls_with_dispatcher() {
    // 1. Deploy the contract
    let contract = declare("beast_mode").unwrap().contract_class();
    let constructor_calldata = array![/* constructor args */];
    let (contract_address, _) = contract.deploy(@constructor_calldata).unwrap();
    
    // 2. Create dispatcher
    let dispatcher = IBeastModeDispatcher { contract_address };
    
    // 3. Call contract functions
    let airdrop_count = dispatcher.get_airdrop_count();
    let block_number = dispatcher.get_airdrop_block_number();
    
    // 4. Call state-changing functions
    dispatcher.initiate_airdrop();
    dispatcher.airdrop_legacy_beasts(10);
}
```

## 2. Required Imports for snforge 0.46.0

```cairo
use snforge_std::{
    declare, ContractClassTrait, DeclareResultTrait,
    start_cheat_block_number_global, stop_cheat_block_number_global,
    mock_call, spy_events, EventSpyAssertionsTrait
};
use starknet::{ContractAddress, contract_address_const};
```

## 3. Interface Definition for beast_mode Contract

First, you need to define an interface for your contract:

```cairo
#[starknet::interface]
pub trait IBeastMode<TContractState> {
    // View functions
    fn get_airdrop_count(self: @TContractState) -> u16;
    fn get_airdrop_block_number(self: @TContractState) -> u64;
    fn get_opening_time(self: @TContractState) -> u64;
    fn get_game_token_address(self: @TContractState) -> ContractAddress;
    fn get_game_collectable_address(self: @TContractState) -> ContractAddress;
    fn get_beast_nft_address(self: @TContractState) -> ContractAddress;
    fn get_legacy_beasts_address(self: @TContractState) -> ContractAddress;
    
    // State-changing functions
    fn initiate_airdrop(ref self: TContractState);
    fn airdrop_legacy_beasts(ref self: TContractState, limit: u16);
    fn claim_beast(ref self: TContractState, adventurer_id: u64, beast_id: u8, prefix: u8, suffix: u8);
    
    // Owner functions
    fn update_opening_time(ref self: TContractState, new_opening_time: u64);
    fn update_payment_token(ref self: TContractState, new_payment_token: ContractAddress);
}
```

## 4. Complete Test Example with Full Flow

```cairo
#[cfg(test)]
mod beast_mode_tests {
    use super::*;
    use snforge_std::{
        declare, ContractClassTrait, DeclareResultTrait, 
        start_cheat_block_number_global, stop_cheat_block_number_global,
        mock_call, start_cheat_caller_address, stop_cheat_caller_address
    };
    use starknet::{ContractAddress, contract_address_const};
    use core::serde::Serde;

    // Test constants
    const LEGACY_BEASTS_ADDRESS: felt252 = 0x0158160018d590d93528995b340260e65aedd76d28a686e9daa5c4e8fad0c5dd;
    const OWNER_ADDRESS: felt252 = 0x123;
    const BEAST_SYSTEMS_ADDRESS: felt252 = 0x456;
    const BEASTS_NFT_ADDRESS: felt252 = 0x789;

    fn deploy_beast_mode_contract() -> IBeastModeDispatcher {
        let contract = declare("beast_mode").unwrap().contract_class();
        
        let mut constructor_calldata = array![];
        1000_u64.serialize(ref constructor_calldata); // opening_time
        contract_address_const::<0x1>().serialize(ref constructor_calldata); // game_token_address
        contract_address_const::<BEAST_SYSTEMS_ADDRESS>().serialize(ref constructor_calldata); // game_collectable_address
        contract_address_const::<BEASTS_NFT_ADDRESS>().serialize(ref constructor_calldata); // beast_nft_address
        contract_address_const::<LEGACY_BEASTS_ADDRESS>().serialize(ref constructor_calldata); // legacy_beasts_address
        contract_address_const::<0x2>().serialize(ref constructor_calldata); // payment_token
        contract_address_const::<0x3>().serialize(ref constructor_calldata); // renderer_address
        let golden_pass: Array<felt252> = array![];
        golden_pass.span().serialize(ref constructor_calldata); // golden_pass
        contract_address_const::<0x4>().serialize(ref constructor_calldata); // ticket_receiver_address
        1_u32.serialize(ref constructor_calldata); // settings_id
        1000_u256.serialize(ref constructor_calldata); // cost_to_play
        
        let (contract_address, _) = contract.deploy(@constructor_calldata).unwrap();
        IBeastModeDispatcher { contract_address }
    }

    #[test]
    fn test_full_airdrop_flow() {
        // Setup mocks
        let vrf_address = contract_address_const::<0x051fea4450da9d6aee758bdeba88b2f665bcbf549d2c61421aa724e9ac0ced8f>();
        mock_call(vrf_address, selector!("seed"), 12345_felt252, 1);
        
        let beast_systems_address = contract_address_const::<BEAST_SYSTEMS_ADDRESS>();
        mock_call(beast_systems_address, selector!("premint_collectable"), 0_felt252, 100);
        
        let beasts_nft_address = contract_address_const::<BEASTS_NFT_ADDRESS>();
        mock_call(beasts_nft_address, selector!("mint"), 0_felt252, 100);
        
        let legacy_beasts_address = contract_address_const::<LEGACY_BEASTS_ADDRESS>();
        let mock_beast_data = array![1_felt252, 2_felt252, 3_felt252, 10_felt252, 100_felt252];
        mock_call(legacy_beasts_address, selector!("getBeast"), mock_beast_data.span(), 100);
        mock_call(legacy_beasts_address, selector!("ownerOf"), contract_address_const::<0x999>(), 100);
        mock_call(legacy_beasts_address, selector!("totalSupply"), 75_u256, 1);

        // Deploy contract and get dispatcher
        let dispatcher = deploy_beast_mode_contract();
        
        // Test initial state
        assert(dispatcher.get_airdrop_count() == 0, 'Initial count should be 0');
        assert(dispatcher.get_airdrop_block_number() == 0, 'Initial block should be 0');
        
        // Initiate airdrop
        dispatcher.initiate_airdrop();
        
        // Verify airdrop initiated
        assert(dispatcher.get_airdrop_count() == 75, 'Airdrop count should be 75');
        assert(dispatcher.get_airdrop_block_number() > 0, 'Block number should be set');
        
        // Fast forward time to enable airdrop
        let airdrop_block = dispatcher.get_airdrop_block_number();
        start_cheat_block_number_global(airdrop_block + 1);
        
        // Execute airdrop
        dispatcher.airdrop_legacy_beasts(5);
        
        stop_cheat_block_number_global();
    }

    #[test]
    fn test_getter_functions() {
        let dispatcher = deploy_beast_mode_contract();
        
        // Test all getter functions
        let opening_time = dispatcher.get_opening_time();
        let game_token_addr = dispatcher.get_game_token_address();
        let collectable_addr = dispatcher.get_game_collectable_address();
        let beast_nft_addr = dispatcher.get_beast_nft_address();
        let legacy_addr = dispatcher.get_legacy_beasts_address();
        
        assert(opening_time == 1000, 'Opening time mismatch');
        assert(game_token_addr == contract_address_const::<0x1>(), 'Game token mismatch');
        assert(collectable_addr == contract_address_const::<BEAST_SYSTEMS_ADDRESS>(), 'Collectable mismatch');
        assert(beast_nft_addr == contract_address_const::<BEASTS_NFT_ADDRESS>(), 'Beast NFT mismatch');
        assert(legacy_addr == contract_address_const::<LEGACY_BEASTS_ADDRESS>(), 'Legacy addr mismatch');
    }
}
```

## 5. SafeDispatcher for Error Handling

For testing functions that might panic, use the SafeDispatcher:

```cairo
use snforge_std::{declare, ContractClassTrait, DeclareResultTrait};

#[test]
#[feature("safe_dispatcher")]
fn test_error_handling() {
    let dispatcher = deploy_beast_mode_contract();
    let safe_dispatcher = IBeastModeSafeDispatcher { contract_address: dispatcher.contract_address };
    
    // Test calling initiate_airdrop twice (should panic)
    dispatcher.initiate_airdrop(); // First call succeeds
    
    match safe_dispatcher.initiate_airdrop() { // Second call should fail
        Result::Ok(_) => panic!("Should have panicked"),
        Result::Err(panic_data) => {
            // Verify panic message
            assert(*panic_data.at(0) == 'Airdrop already initiated', 'Wrong panic message');
        },
    };
}
```

## 6. Testing with Different Contract Instances

```cairo
#[test]
fn test_multiple_contracts() {
    let dispatcher1 = deploy_beast_mode_contract();
    let dispatcher2 = deploy_beast_mode_contract();
    
    // Each dispatcher operates on a different contract instance
    dispatcher1.initiate_airdrop();
    dispatcher2.initiate_airdrop();
    
    assert(dispatcher1.get_airdrop_count() == 75, 'Contract 1 airdrop count');
    assert(dispatcher2.get_airdrop_count() == 75, 'Contract 2 airdrop count');
}
```

## 7. External Contract Interactions

The beast_mode contract already demonstrates the correct pattern for calling external contracts:

```cairo
// In the contract code (src/lib.cairo)
let beast_systems = IBeastSystemsDispatcher { contract_address: game_collectable_address };
let beasts_nft = IBeastsDispatcher { contract_address: beast_nft_address };
let game_token = IERC721Dispatcher { contract_address: game_token_address };

// Call external functions
let entity_hash = beast_systems.get_beast_hash(beast_id, prefix, suffix);
beasts_nft.mint(owner, beast_id, prefix, suffix, level, health, shiny, animated);
let owner = game_token.owner_of(adventurer_id.into());
```

## 8. Key Advantages of This Approach

1. **Type Safety**: Dispatchers are generated from interfaces, ensuring type safety
2. **IDE Support**: Full autocomplete and type checking
3. **Error Handling**: SafeDispatcher pattern for testing error conditions
4. **Maintainability**: Changes to interface automatically update dispatchers
5. **Standard Pattern**: This is the recommended approach in Cairo/Starknet

## 9. Migration from call_contract_syscall

If you were previously using `call_contract_syscall`, migrate like this:

```cairo
// OLD WAY (doesn't work in snforge 0.46.0)
// call_contract_syscall(contract_address, selector, calldata)

// NEW WAY (recommended)
let dispatcher = IYourContractDispatcher { contract_address };
dispatcher.your_function(args);
```

## Conclusion

The dispatcher pattern is the modern, recommended approach for contract calls in snforge 0.46.0. It provides type safety, better error handling, and integrates seamlessly with the Cairo development experience. The beast_mode contract already implements this pattern correctly.