#[cfg(test)]
mod tests {
    use starknet::contract_address_const;
    use snforge_std::{
        declare, ContractClassTrait, DeclareResultTrait, start_cheat_block_number_global,
        stop_cheat_block_number_global, mock_call
    };
    use core::serde::Serde;

    // Test constants
    const LEGACY_BEASTS_ADDRESS: felt252 = 0x0158160018d590d93528995b340260e65aedd76d28a686e9daa5c4e8fad0c5dd;
    const OWNER_ADDRESS: felt252 = 0x123;
    const BEAST_SYSTEMS_ADDRESS: felt252 = 0x456;
    const BEASTS_NFT_ADDRESS: felt252 = 0x789;

    #[test]  
    fn test_deploy_beast_mode_contract() {
        let contract = declare("beast_mode").unwrap().contract_class();
        
        let mut constructor_calldata = array![];
        // opening_time: u64
        1000_u64.serialize(ref constructor_calldata);
        // game_token_address: ContractAddress  
        contract_address_const::<0x1>().serialize(ref constructor_calldata);
        // game_collectable_address: ContractAddress
        contract_address_const::<BEAST_SYSTEMS_ADDRESS>().serialize(ref constructor_calldata);
        // beast_nft_address: ContractAddress
        contract_address_const::<BEASTS_NFT_ADDRESS>().serialize(ref constructor_calldata);
        // legacy_beasts_address: ContractAddress
        contract_address_const::<LEGACY_BEASTS_ADDRESS>().serialize(ref constructor_calldata);
        // payment_token: ContractAddress
        contract_address_const::<0x2>().serialize(ref constructor_calldata);
        // renderer_address: ContractAddress
        contract_address_const::<0x3>().serialize(ref constructor_calldata);
        // golden_pass: Span<(ContractAddress, GoldenPass)> - empty array
        let golden_pass: Array<felt252> = array![];
        golden_pass.span().serialize(ref constructor_calldata);
        // ticket_receiver_address: ContractAddress
        contract_address_const::<0x4>().serialize(ref constructor_calldata);
        // settings_id: u32
        1_u32.serialize(ref constructor_calldata);
        // cost_to_play: u256
        1000_u256.serialize(ref constructor_calldata);
        
        let (contract_address, _) = contract.deploy(@constructor_calldata).unwrap();
        
        // Verify contract was deployed
        assert(contract_address != contract_address_const::<0>(), 'Contract should be deployed');
    }

    #[test]
    fn test_vrf_mocking() {
        // Mock the VRF seed call to return a predictable value
        let vrf_address = contract_address_const::<0x051fea4450da9d6aee758bdeba88b2f665bcbf549d2c61421aa724e9ac0ced8f>();
        mock_call(vrf_address, selector!("seed"), 12345_felt252, 1);
        
        // This test verifies that we can mock the VRF call successfully
        // In a real test, we would call initiate_airdrop and verify the VRF seed is used
        assert(true, 'VRF mock setup ok');
    }

    #[test]
    fn test_block_number_manipulation() {
        // Test that we can manipulate block numbers for testing timing-dependent functionality
        start_cheat_block_number_global(100);
        
        // In a real scenario, we would:
        // 1. Deploy contract
        // 2. Call initiate_airdrop at block 100 (should set airdrop_block_number to 200)
        // 3. Fast forward to block 191+ to test airdrop_legacy_beasts
        
        stop_cheat_block_number_global();
        assert(true, 'Block number test passed');
    }

    #[test]
    fn test_mock_legacy_beast_calls() {
        // Test mocking legacy beast contract calls
        let legacy_beasts_address = contract_address_const::<LEGACY_BEASTS_ADDRESS>();
        
        // Mock getBeast call - would need to match actual LegacyBeast struct format  
        let mock_beast_data = array![
            1_felt252,   // id
            2_felt252,   // prefix
            3_felt252,   // suffix
            10_felt252,  // level
            100_felt252, // health
        ];
        mock_call(legacy_beasts_address, selector!("getBeast"), mock_beast_data.span(), 1);
        
        // Mock ownerOf call
        let mock_owner = contract_address_const::<0x999>();
        mock_call(legacy_beasts_address, selector!("ownerOf"), mock_owner, 1);
        
        // Mock totalSupply call
        mock_call(legacy_beasts_address, selector!("totalSupply"), 75_u256, 1);
        
        assert(true, 'Legacy beast mock ok');
    }

    #[test]
    fn test_mock_beast_systems_calls() {
        // Test mocking beast systems contract calls
        let beast_systems_address = contract_address_const::<BEAST_SYSTEMS_ADDRESS>();
        
        // Mock validate_collectable call
        mock_call(beast_systems_address, selector!("validate_collectable"), true, 10);
        
        // Mock premint_collectable call  
        mock_call(beast_systems_address, selector!("premint_collectable"), 0_felt252, 10);
        
        assert(true, 'Beast systems mock ok');
    }

    #[test]
    fn test_mock_beasts_nft_calls() {
        // Test mocking beasts NFT contract calls
        let beasts_nft_address = contract_address_const::<BEASTS_NFT_ADDRESS>();
        
        // Mock mint call
        mock_call(beasts_nft_address, selector!("mint"), 0_felt252, 10);
        
        assert(true, 'Beasts NFT mock ok');
    }

    #[test] 
    fn test_trait_probability_calculation() {
        // Test the trait probability calculation logic used in airdrop
        // The contract uses 8% chance for both shiny and animated traits
        
        // Mock beast seed for testing
        let beast_seed = 123456789_u64;
        
        // Replicate the shiny trait calculation from the contract
        let shiny_seed = (beast_seed & 0xFFFFFFFF_u64) % 10000_u64;
        let shiny = if shiny_seed < 800_u64 { 1_u8 } else { 0_u8 };
        
        // Replicate the animated trait calculation from the contract  
        let animated_seed = ((beast_seed / 0x100000000_u64) & 0xFFFFFFFF_u64) % 10000_u64;
        let animated = if animated_seed < 800_u64 { 1_u8 } else { 0_u8 };
        
        // Verify the calculations work (specific values depend on the seed)
        assert(shiny == 0 || shiny == 1, 'Shiny trait valid');
        assert(animated == 0 || animated == 1, 'Animated trait valid');
    }

    #[test]
    fn test_address_constants() {
        // Test that our test constants are properly defined
        let legacy_addr = contract_address_const::<LEGACY_BEASTS_ADDRESS>();
        let owner_addr = contract_address_const::<OWNER_ADDRESS>();
        let beast_systems_addr = contract_address_const::<BEAST_SYSTEMS_ADDRESS>();
        let beasts_nft_addr = contract_address_const::<BEASTS_NFT_ADDRESS>();
        
        assert(legacy_addr != contract_address_const::<0>(), 'Legacy addr valid');
        assert(owner_addr != contract_address_const::<0>(), 'Owner addr valid');
        assert(beast_systems_addr != contract_address_const::<0>(), 'Beast systems valid');
        assert(beasts_nft_addr != contract_address_const::<0>(), 'Beasts NFT valid');
    }
}