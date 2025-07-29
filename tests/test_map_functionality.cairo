#[cfg(test)]
mod test_map_functionality {
    use starknet::{ContractAddress, contract_address_const};
    use snforge_std::{
        declare, ContractClassTrait, DeclareResultTrait, cheat_caller_address,
        stop_cheat_caller_address
    };
    use core::serde::Serde;
    use core::array::ArrayTrait;
    
    // Test constants
    const OWNER_ADDRESS: felt252 = 0x123456789;
    const TOKEN_ID: u64 = 12345;
    
    // Contract addresses
    const GAME_TOKEN_ADDRESS: felt252 = 0xdef;
    const REWARD_TOKEN_ADDRESS: felt252 = 0xabc;
    const BEAST_SYSTEMS_ADDRESS: felt252 = 0x456;
    const BEASTS_NFT_ADDRESS: felt252 = 0xabc;
    const LEGACY_BEASTS_ADDRESS: felt252 = 0x567;
    const PAYMENT_TOKEN_ADDRESS: felt252 = 0x888;
    const RENDERER_ADDRESS: felt252 = 0x999;
    const TICKET_RECEIVER_ADDRESS: felt252 = 0xaaa;
    
    const OPENING_TIME: u64 = 1000000;
    const COST_TO_PLAY: u256 = 1000;
    const SETTINGS_ID: u32 = 1;

    fn deploy_beast_mode_contract() -> ContractAddress {
        let contract = declare("beast_mode").unwrap().contract_class();
        
        let mut constructor_calldata = array![];
        OPENING_TIME.serialize(ref constructor_calldata);
        contract_address_const::<GAME_TOKEN_ADDRESS>().serialize(ref constructor_calldata);
        contract_address_const::<BEAST_SYSTEMS_ADDRESS>().serialize(ref constructor_calldata);
        contract_address_const::<0x789>().serialize(ref constructor_calldata); // game_adventurer_address
        contract_address_const::<BEASTS_NFT_ADDRESS>().serialize(ref constructor_calldata);
        contract_address_const::<LEGACY_BEASTS_ADDRESS>().serialize(ref constructor_calldata);
        contract_address_const::<PAYMENT_TOKEN_ADDRESS>().serialize(ref constructor_calldata);
        contract_address_const::<REWARD_TOKEN_ADDRESS>().serialize(ref constructor_calldata);
        contract_address_const::<RENDERER_ADDRESS>().serialize(ref constructor_calldata);
        
        // Golden pass - empty for tests
        let golden_pass: Array<felt252> = ArrayTrait::new();
        golden_pass.span().serialize(ref constructor_calldata);
        
        contract_address_const::<TICKET_RECEIVER_ADDRESS>().serialize(ref constructor_calldata);
        SETTINGS_ID.serialize(ref constructor_calldata);
        COST_TO_PLAY.serialize(ref constructor_calldata);
        
        cheat_caller_address(contract_address_const::<0>(), contract_address_const::<OWNER_ADDRESS>());
        let (contract_address, _) = contract.deploy(@constructor_calldata).unwrap();
        stop_cheat_caller_address(contract_address_const::<0>());
        
        contract_address
    }

    #[test]
    fn test_contract_deployment() {
        // This test verifies that the contract can be deployed with the Map storage
        let contract_address = deploy_beast_mode_contract();
        
        // If we get here, the contract deployed successfully with Map storage
        assert(contract_address != contract_address_const::<0>(), 'Contract should be deployed');
    }
} 