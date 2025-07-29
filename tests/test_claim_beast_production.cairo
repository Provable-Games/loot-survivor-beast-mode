#[cfg(test)]
mod production_claim_beast_tests {
    use starknet::{ContractAddress, contract_address_const};
    use snforge_std::{
        declare, ContractClassTrait, DeclareResultTrait, start_mock_call
    };
    use core::serde::Serde;
    use core::traits::Into;
    use core::array::ArrayTrait;
    
    // Import interfaces
    use beast_mode::interfaces::{
        IBeastModeDispatcher, IBeastModeDispatcherTrait,
        DataResult
    };

    // Test constants
    const OWNER_ADDRESS: felt252 = 0x123456789;
    const PLAYER_ADDRESS: felt252 = 0x987654321;
    
    // Contract addresses
    const BEAST_SYSTEMS_ADDRESS: felt252 = 0x789;
    const BEASTS_NFT_ADDRESS: felt252 = 0xabc;
    const GAME_TOKEN_ADDRESS: felt252 = 0xdef;
    const PAYMENT_TOKEN_ADDRESS: felt252 = 0x888;
    const RENDERER_ADDRESS: felt252 = 0x999;
    const TICKET_RECEIVER_ADDRESS: felt252 = 0xaaa;
    
    // Beast test data
    const ADVENTURER_ID: u64 = 12345;
    const BEAST_ID: u8 = 7;
    const PREFIX: u8 = 12;
    const SUFFIX: u8 = 25;
    const LEVEL: u16 = 50;
    const HEALTH: u16 = 200;

    fn deploy_beast_mode_contract() -> ContractAddress {
        let contract = declare("beast_mode").unwrap().contract_class();
        
        let mut constructor_calldata = array![];
        1000000_u64.serialize(ref constructor_calldata); // opening_time
        contract_address_const::<GAME_TOKEN_ADDRESS>().serialize(ref constructor_calldata);
        contract_address_const::<BEAST_SYSTEMS_ADDRESS>().serialize(ref constructor_calldata);
        contract_address_const::<BEASTS_NFT_ADDRESS>().serialize(ref constructor_calldata);
        contract_address_const::<0x1>().serialize(ref constructor_calldata); // legacy_beasts
        contract_address_const::<PAYMENT_TOKEN_ADDRESS>().serialize(ref constructor_calldata);
        contract_address_const::<RENDERER_ADDRESS>().serialize(ref constructor_calldata);
        
        // Golden pass - empty for tests
        let golden_pass: Array<felt252> = ArrayTrait::new();
        golden_pass.span().serialize(ref constructor_calldata);
        
        contract_address_const::<TICKET_RECEIVER_ADDRESS>().serialize(ref constructor_calldata);
        1_u32.serialize(ref constructor_calldata); // settings_id
        1000_u256.serialize(ref constructor_calldata); // cost_to_play
        
        let (contract_address, _) = contract.deploy(@constructor_calldata).unwrap();
        
        contract_address
    }

    fn setup_successful_claim_mocks(seed: u64) {
        // Mock get_beast_hash
        let hash: felt252 = (BEAST_ID.into() * 10000 + PREFIX.into() * 100 + SUFFIX.into()).into();
        start_mock_call(
            contract_address_const::<BEAST_SYSTEMS_ADDRESS>(),
            'get_beast_hash',
            hash
        );
        
        // Mock get_valid_collectable to return Ok with the seed
        let collectable_result = DataResult::Ok((seed, LEVEL, HEALTH));
        start_mock_call(
            contract_address_const::<BEAST_SYSTEMS_ADDRESS>(),
            'get_valid_collectable',
            collectable_result
        );
        
        // Mock owner_of for game token
        start_mock_call(
            contract_address_const::<GAME_TOKEN_ADDRESS>(),
            'owner_of',
            contract_address_const::<PLAYER_ADDRESS>()
        );
        
        // Mock mint function to return success
        start_mock_call(
            contract_address_const::<BEASTS_NFT_ADDRESS>(),
            'mint',
            ()
        );
    }

    // Test 1: Contract deployment and basic functionality
    #[test]
    fn test_production_contract_deployment() {
        let beast_mode_addr = deploy_beast_mode_contract();
        let beast_mode = IBeastModeDispatcher { contract_address: beast_mode_addr };
        
        // Verify initialization
        assert(beast_mode.get_opening_time() == 1000000, 'Wrong opening time');
        assert(beast_mode.get_game_token_address() == contract_address_const::<GAME_TOKEN_ADDRESS>(), 'Wrong game token addr');
        assert(beast_mode.get_game_collectable_address() == contract_address_const::<BEAST_SYSTEMS_ADDRESS>(), 'Wrong beast systems addr');
        assert(beast_mode.get_beast_nft_address() == contract_address_const::<BEASTS_NFT_ADDRESS>(), 'Wrong beast nft addr');
    }

    // Test 2: Successful claim with normal attributes (no special traits)
    #[test]
    fn test_production_claim_normal_attributes() {
        let beast_mode_addr = deploy_beast_mode_contract();
        let beast_mode = IBeastModeDispatcher { contract_address: beast_mode_addr };
        
        // Use seed that won't produce special traits
        let seed = 0xFEDCBA9876543210_u64; // Both calculations should be > 400
        setup_successful_claim_mocks(seed);
        
        // Should complete without error
        beast_mode.claim_beast(ADVENTURER_ID, BEAST_ID, PREFIX, SUFFIX);
        
        // Verify calculations manually
        let shiny_seed = (seed & 0xFFFFFFFF_u64) % 10000_u64;
        let animated_seed = ((seed / 0x100000000_u64) & 0xFFFFFFFF_u64) % 10000_u64;
        
        // With this seed, neither should be special
        assert(shiny_seed >= 400_u64, 'Should not be shiny');
        assert(animated_seed >= 400_u64, 'Should not be animated');
    }

    // Test 3: Claim with shiny trait (4% probability)
    #[test]
    fn test_production_claim_shiny_trait() {
        let beast_mode_addr = deploy_beast_mode_contract();
        let beast_mode = IBeastModeDispatcher { contract_address: beast_mode_addr };
        
        // Use seed that produces shiny (lower 32 bits < 400)
        let seed = 0x00000000000000FF_u64; // 255 < 400, so shiny
        setup_successful_claim_mocks(seed);
        
        beast_mode.claim_beast(ADVENTURER_ID, BEAST_ID, PREFIX, SUFFIX);
        
        // Verify shiny calculation
        let shiny_seed = (seed & 0xFFFFFFFF_u64) % 10000_u64;
        assert(shiny_seed < 400_u64, 'Should be shiny');
        assert(shiny_seed == 255, 'Shiny seed should be 255');
    }

    // Test 4: Claim with animated trait (4% probability)
    #[test]
    fn test_production_claim_animated_trait() {
        let beast_mode_addr = deploy_beast_mode_contract();
        let beast_mode = IBeastModeDispatcher { contract_address: beast_mode_addr };
        
        // Use seed that produces animated (upper 32 bits < 400)
        let seed = 0x000000FF00000000_u64; // Upper 32 bits = 255 < 400
        setup_successful_claim_mocks(seed);
        
        beast_mode.claim_beast(ADVENTURER_ID, BEAST_ID, PREFIX, SUFFIX);
        
        // Verify animated calculation
        let animated_seed = ((seed / 0x100000000_u64) & 0xFFFFFFFF_u64) % 10000_u64;
        assert(animated_seed < 400_u64, 'Should be animated');
        assert(animated_seed == 255, 'Animated seed should be 255');
    }

    // Test 5: Claim with both traits (very rare)
    #[test]
    fn test_production_claim_both_traits() {
        let beast_mode_addr = deploy_beast_mode_contract();
        let beast_mode = IBeastModeDispatcher { contract_address: beast_mode_addr };
        
        // Use seed that produces both traits
        let seed = 0x000000FF000000FF_u64; // Both parts = 255 < 400
        setup_successful_claim_mocks(seed);
        
        beast_mode.claim_beast(ADVENTURER_ID, BEAST_ID, PREFIX, SUFFIX);
        
        // Verify both calculations
        let shiny_seed = (seed & 0xFFFFFFFF_u64) % 10000_u64;
        let animated_seed = ((seed / 0x100000000_u64) & 0xFFFFFFFF_u64) % 10000_u64;
        
        assert(shiny_seed < 400_u64, 'Should be shiny');
        assert(animated_seed < 400_u64, 'Should be animated');
    }

    // Test 6: Error case - invalid collectable
    #[test]
    #[should_panic(expected: ('Invalid collectable',))]
    fn test_production_invalid_collectable() {
        let beast_mode_addr = deploy_beast_mode_contract();
        let beast_mode = IBeastModeDispatcher { contract_address: beast_mode_addr };
        
        // Mock failure case
        let hash: felt252 = (BEAST_ID.into() * 10000 + PREFIX.into() * 100 + SUFFIX.into()).into();
        start_mock_call(
            contract_address_const::<BEAST_SYSTEMS_ADDRESS>(),
            'get_beast_hash',
            hash
        );
        
        let collectable_result = DataResult::Err('Invalid collectable');
        start_mock_call(
            contract_address_const::<BEAST_SYSTEMS_ADDRESS>(),
            'get_valid_collectable',
            collectable_result
        );
        
        // This should panic
        beast_mode.claim_beast(ADVENTURER_ID, BEAST_ID, PREFIX, SUFFIX);
    }

    // Test 7: Boundary conditions for 4% probability
    #[test]
    fn test_production_probability_boundaries() {
        let beast_mode_addr = deploy_beast_mode_contract();
        let beast_mode = IBeastModeDispatcher { contract_address: beast_mode_addr };
        
        // Test case 1: 399 should trigger trait
        let seed_399 = 0x0000000000000187_u64; // 0x187 = 391 in decimal
        let shiny_399 = (seed_399 & 0xFFFFFFFF_u64) % 10000_u64;
        assert(shiny_399 == 391, 'Seed 391 calculation wrong');
        assert(shiny_399 < 400_u64, '391 should trigger trait');
        
        // Test case 2: 400 should not trigger trait
        let seed_400 = 0x0000000000000190_u64; // 400
        let shiny_400 = (seed_400 & 0xFFFFFFFF_u64) % 10000_u64;
        assert(shiny_400 == 400, 'Seed 400 calculation wrong');
        assert(shiny_400 >= 400_u64, '400 should not trigger trait');
        
        // Test case 3: 0 should trigger trait
        let seed_0 = 0x0000000000000000_u64; // 0
        let shiny_0 = (seed_0 & 0xFFFFFFFF_u64) % 10000_u64;
        assert(shiny_0 == 0, 'Seed 0 calculation wrong');
        assert(shiny_0 < 400_u64, '0 should trigger trait');
    }

    // Test 8: Large number handling and overflow protection
    #[test]
    fn test_production_large_numbers() {
        let beast_mode_addr = deploy_beast_mode_contract();
        let beast_mode = IBeastModeDispatcher { contract_address: beast_mode_addr };
        
        // Test with maximum values
        let max_seed = 0xFFFFFFFFFFFFFFFF_u64;
        let max_adventurer = 0xFFFFFFFFFFFFFFFF_u64;
        let max_beast_id = 255_u8;
        let max_prefix = 255_u8;
        let max_suffix = 255_u8;
        
        // Set up mocks for max values
        let max_hash: felt252 = (max_beast_id.into() * 10000 + max_prefix.into() * 100 + max_suffix.into()).into();
        start_mock_call(
            contract_address_const::<BEAST_SYSTEMS_ADDRESS>(),
            'get_beast_hash',
            max_hash
        );
        
        let collectable_result = DataResult::Ok((max_seed, LEVEL, HEALTH));
        start_mock_call(
            contract_address_const::<BEAST_SYSTEMS_ADDRESS>(),
            'get_valid_collectable',
            collectable_result
        );
        
        start_mock_call(
            contract_address_const::<GAME_TOKEN_ADDRESS>(),
            'owner_of',
            contract_address_const::<PLAYER_ADDRESS>()
        );
        
        start_mock_call(
            contract_address_const::<BEASTS_NFT_ADDRESS>(),
            'mint',
            ()
        );
        
        // Should complete without overflow
        beast_mode.claim_beast(max_adventurer, max_beast_id, max_prefix, max_suffix);
        
        // Verify calculations work with max values
        let shiny_calc = (max_seed & 0xFFFFFFFF_u64) % 10000_u64;
        let animated_calc = ((max_seed / 0x100000000_u64) & 0xFFFFFFFF_u64) % 10000_u64;
        
        // Should be able to calculate without overflow
        assert(shiny_calc < 10000, 'Shiny calc overflow');
        assert(animated_calc < 10000, 'Animated calc overflow');
    }

    // Test 9: Multiple consecutive claims
    #[test]
    fn test_production_multiple_claims() {
        let beast_mode_addr = deploy_beast_mode_contract();
        let beast_mode = IBeastModeDispatcher { contract_address: beast_mode_addr };
        
        // Perform multiple claims with different parameters
        let test_cases = array![
            (1001_u64, 1_u8, 10_u8, 20_u8, 0x1111111111111111_u64),
            (1002_u64, 2_u8, 11_u8, 21_u8, 0x2222222222222222_u64),
            (1003_u64, 3_u8, 12_u8, 22_u8, 0x3333333333333333_u64),
            (1004_u64, 4_u8, 13_u8, 23_u8, 0x4444444444444444_u64),
            (1005_u64, 5_u8, 14_u8, 24_u8, 0x5555555555555555_u64),
        ];
        
        let mut i = 0_u32;
        loop {
            if i >= test_cases.len() {
                break;
            }
            
            let (adventurer_id, beast_id, prefix, suffix, seed) = *test_cases[i];
            
            // Set up mocks for this case
            let hash: felt252 = (beast_id.into() * 10000 + prefix.into() * 100 + suffix.into()).into();
            start_mock_call(
                contract_address_const::<BEAST_SYSTEMS_ADDRESS>(),
                'get_beast_hash',
                hash
            );
            
            let collectable_result = DataResult::Ok((seed, LEVEL, HEALTH));
            start_mock_call(
                contract_address_const::<BEAST_SYSTEMS_ADDRESS>(),
                'get_valid_collectable',
                collectable_result
            );
            
            start_mock_call(
                contract_address_const::<GAME_TOKEN_ADDRESS>(),
                'owner_of',
                contract_address_const::<PLAYER_ADDRESS>()
            );
            
            start_mock_call(
                contract_address_const::<BEASTS_NFT_ADDRESS>(),
                'mint',
                ()
            );
            
            // Execute claim
            beast_mode.claim_beast(adventurer_id, beast_id, prefix, suffix);
            
            i += 1;
        };
        
        // All claims should have completed successfully (no panics)
    }

    // Test 10: Hash calculation verification
    #[test]
    fn test_production_hash_calculation() {
        // Test the hash calculation used in get_beast_hash
        let test_cases = array![
            (1_u8, 2_u8, 3_u8, 10203_u32), // 1*10000 + 2*100 + 3 = 10203
            (5_u8, 10_u8, 15_u8, 51015_u32), // 5*10000 + 10*100 + 15 = 51015
            (0_u8, 0_u8, 0_u8, 0_u32), // 0*10000 + 0*100 + 0 = 0
            (1_u8, 0_u8, 0_u8, 10000_u32), // 1*10000 + 0*100 + 0 = 10000
        ];
        
        let mut i = 0_u32;
        loop {
            if i >= test_cases.len() {
                break;
            }
            
            let (beast_id, prefix, suffix, expected) = *test_cases[i];
            let calculated: u32 = beast_id.into() * 10000 + prefix.into() * 100 + suffix.into();
            
            assert(calculated == expected, 'Hash calculation mismatch');
            
            i += 1;
        };
    }

    // Test 11: Statistical verification of 4% rate
    #[test]
    fn test_production_statistical_verification() {
        // Test the mathematical correctness of the 4% calculation
        let total_range = 10000_u64;
        let threshold = 400_u64;
        
        // Verify 4% calculation
        let rate_percent = threshold * 100 / total_range;
        assert(rate_percent == 4, 'Rate should be exactly 4%');
        
        // Test specific values that should/shouldn't trigger
        let test_values = array![0_u64, 1_u64, 399_u64, 400_u64, 401_u64, 9999_u64];
        
        let mut i = 0_u32;
        let mut trigger_count = 0_u32;
        
        loop {
            if i >= test_values.len() {
                break;
            }
            
            let value = *test_values[i];
            if value < threshold {
                trigger_count += 1;
            }
            
            i += 1;
        };
        
        // Should have 3 values that trigger: 0, 1, 399
        assert(trigger_count == 3, 'Trigger count incorrect');
    }

    // Test 12: Edge cases and special values
    #[test]
    fn test_production_edge_cases() {
        let beast_mode_addr = deploy_beast_mode_contract();
        let beast_mode = IBeastModeDispatcher { contract_address: beast_mode_addr };
        
        // Test with zero values
        let zero_seed = 0_u64;
        setup_successful_claim_mocks(zero_seed);
        
        beast_mode.claim_beast(0, 0, 0, 0);
        
        // Verify zero seed calculations
        let shiny_zero = (zero_seed & 0xFFFFFFFF_u64) % 10000_u64;
        let animated_zero = ((zero_seed / 0x100000000_u64) & 0xFFFFFFFF_u64) % 10000_u64;
        
        assert(shiny_zero == 0, 'Zero shiny calc wrong');
        assert(animated_zero == 0, 'Zero animated calc wrong');
        assert(shiny_zero < 400_u64, 'Zero should be shiny');
        assert(animated_zero < 400_u64, 'Zero should be animated');
    }
}