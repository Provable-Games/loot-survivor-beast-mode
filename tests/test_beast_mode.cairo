use starknet::{ContractAddress, contract_address_const};
use snforge_std::{
    declare, DeclareResultTrait, ContractClassTrait,
    start_cheat_caller_address, stop_cheat_caller_address,
    start_cheat_block_number, stop_cheat_block_number,
    start_cheat_block_hash, stop_cheat_block_hash,
    start_mock_call, mock_call
};

use beast_mode::interfaces::{
    IBeastModeDispatcher, IBeastModeDispatcherTrait, DataResult
};

// Import mock contracts
mod mock_contracts;

use mock_contracts::{
    IMockBeastNFTDispatcher, IMockBeastNFTDispatcherTrait,
    Beast,
};

// Test constants
const OWNER: felt252 = 'OWNER';
const PLAYER1: felt252 = 'PLAYER1';
const PLAYER2: felt252 = 'PLAYER2';

// Contract addresses for mocking
fn GAME_TOKEN_ADDRESS() -> ContractAddress {
    contract_address_const::<'GAME_TOKEN'>()
}

fn GAME_COLLECTABLE_ADDRESS() -> ContractAddress {
    contract_address_const::<'GAME_COLLECTABLE'>()
}

fn ADVENTURER_SYSTEMS_ADDRESS() -> ContractAddress {
    contract_address_const::<'ADVENTURER_SYSTEMS'>()
}

fn LEGACY_BEASTS_ADDRESS() -> ContractAddress {
    contract_address_const::<'LEGACY_BEASTS'>()
}

fn PAYMENT_TOKEN_ADDRESS() -> ContractAddress {
    contract_address_const::<'PAYMENT_TOKEN'>()
}

fn REWARD_TOKEN_ADDRESS() -> ContractAddress {
    contract_address_const::<'REWARD_TOKEN'>()
}

fn RENDERER_ADDRESS() -> ContractAddress {
    contract_address_const::<'RENDERER'>()
}

fn TICKET_RECEIVER_ADDRESS() -> ContractAddress {
    contract_address_const::<'TICKET_RECEIVER'>()
}

// Deploy helper function for mock beast NFT
fn deploy_mock_beast_nft() -> IMockBeastNFTDispatcher {
    let contract = declare("MockBeastNFT").unwrap().contract_class();
    let (contract_address, _) = contract.deploy(@array![]).unwrap();
    IMockBeastNFTDispatcher { contract_address }
}

// Deploy the beast mode contract with mock beast NFT and set up consistent mock calls
fn deploy_beast_mode_with_mock_nft() -> (IBeastModeDispatcher, IMockBeastNFTDispatcher) {
    // Deploy only the mock beast NFT contract
    let mock_beast_nft = deploy_mock_beast_nft();
    
    // Deploy beast mode contract with mock beast NFT and regular addresses for others
    let contract = declare("beast_mode").unwrap().contract_class();
    
    let opening_time = 1000_u64;
    let settings_id = 1_u32;
    let cost_to_play = 100_u256;
    let renderer_address = RENDERER_ADDRESS();
    let ticket_receiver_address = TICKET_RECEIVER_ADDRESS();
    
    let (contract_address, _) = contract
        .deploy(
            @array![
                opening_time.into(),
                GAME_TOKEN_ADDRESS().into(),
                GAME_COLLECTABLE_ADDRESS().into(),
                ADVENTURER_SYSTEMS_ADDRESS().into(),
                mock_beast_nft.contract_address.into(), // Use our mock beast NFT
                LEGACY_BEASTS_ADDRESS().into(),
                PAYMENT_TOKEN_ADDRESS().into(),
                REWARD_TOKEN_ADDRESS().into(),
                renderer_address.into(),
                0, // empty golden pass array
                ticket_receiver_address.into(),
                settings_id.into(),
                cost_to_play.low.into(),
                cost_to_play.high.into(),
            ]
        )
        .unwrap();
    
    // Set up only the mock calls that ALWAYS return the same values
    setup_consistent_mocks();
    
    (IBeastModeDispatcher { contract_address }, mock_beast_nft)
}

// Set up mock calls that always return the same values using start_mock_call
fn setup_consistent_mocks() {
    let legacy_owner = contract_address_const::<'LEGACY_OWNER'>();
    
    // Mock legacy beasts totalSupply - always return 100
    start_mock_call(
        LEGACY_BEASTS_ADDRESS(),
        selector!("totalSupply"),
        100_u256
    );
    
    // Mock legacy beasts ownerOf - always return legacy owner
    start_mock_call(
        LEGACY_BEASTS_ADDRESS(),
        selector!("ownerOf"),
        legacy_owner
    );

    start_mock_call(
        REWARD_TOKEN_ADDRESS(),
        selector!("balance_of"),
        1000000000000000000000_u256,
    );
}

// Helper functions for flexible mock calls that need different values per test
fn mock_owner_of_call(owner: ContractAddress) {
    mock_call(
        GAME_TOKEN_ADDRESS(),
        selector!("owner_of"),
        owner,
        1
    );
}

fn mock_beast_hash_call(hash: felt252) {
    mock_call(
        GAME_COLLECTABLE_ADDRESS(),
        selector!("get_beast_hash"),
        hash,
        1
    );
}

fn mock_valid_collectable_call(seed: u64, level: u16, health: u16) {
    mock_call(
        GAME_COLLECTABLE_ADDRESS(),
        selector!("get_valid_collectable"),
        DataResult::Ok((seed, level, health)),
        1
    );
}

fn mock_valid_collectable_error(error_msg: felt252) {
    mock_call(
        GAME_COLLECTABLE_ADDRESS(),
        selector!("get_valid_collectable"),
        DataResult::<(u64, u16, u16)>::Err(error_msg),
        1
    );
}

fn mock_getBeast_call(id: u8, prefix: u8, suffix: u8, level: u16, health: u16, times: u32) {
    mock_call(
        LEGACY_BEASTS_ADDRESS(),
        selector!("getBeast"),
        (id, prefix, suffix, level, health), // Return as tuple directly
        times
    );
}

fn mock_adventurer_level_call(level: u8) {
    mock_call(
        ADVENTURER_SYSTEMS_ADDRESS(),
        selector!("get_adventurer_level"),
        DataResult::Ok(level),
        1
    );
}

fn mock_adventurer_level_error(error_msg: felt252) {
    mock_call(
        ADVENTURER_SYSTEMS_ADDRESS(),
        selector!("get_adventurer_level"),
        DataResult::<u8>::Err(error_msg),
        1
    );
}

fn mock_erc20_transfer_call(success: bool) {
    mock_call(
        REWARD_TOKEN_ADDRESS(),
        selector!("transfer"),
        success,
        1
    );
}

fn mock_balance_of_zero_call() {
    mock_call(
        REWARD_TOKEN_ADDRESS(),
        selector!("balance_of"),
        0_u256,
        1
    );
}

fn mock_owner_of_call_times(owner: ContractAddress, times: u32) {
    mock_call(
        GAME_TOKEN_ADDRESS(),
        selector!("owner_of"),
        owner,
        times
    );
}

fn mock_adventurer_level_call_once(level: u8) {
    mock_call(
        ADVENTURER_SYSTEMS_ADDRESS(),
        selector!("get_adventurer_level"),
        DataResult::Ok(level),
        1
    );
}

// VRF contract address (from vrf.cairo)
fn VRF_PROVIDER_ADDRESS() -> ContractAddress {
    contract_address_const::<0x051fea4450da9d6aee758bdeba88b2f665bcbf549d2c61421aa724e9ac0ced8f>()
}

fn mock_vrf_consume_random(random_value: felt252) {
    mock_call(
        VRF_PROVIDER_ADDRESS(),
        selector!("consume_random"),
        random_value,
        1
    );
}

fn mock_premint_collectable_call(times: u32) {
    // premint_collectable returns a u64 (entity_id)
    mock_call(
        GAME_COLLECTABLE_ADDRESS(),
        selector!("premint_collectable"),
        12345_u64, // Return some entity ID
        times
    );
}

#[test]
fn test_claim_beast_mint_parameters() {
    let (beast_mode, mock_beast_nft) = deploy_beast_mode_with_mock_nft();
    let beast_mode_address = beast_mode.contract_address;
    
    // Test parameters
    let adventurer_id = 1_u64;
    let beast_id = 10_u8;
    let prefix = 1_u8;
    let suffix = 2_u8;
    let level = 5_u16;
    let health = 100_u16;
    let player_address = contract_address_const::<PLAYER1>();
    
    // Set up flexible mocks for this specific test
    mock_owner_of_call(player_address);
    mock_beast_hash_call('BEAST_HASH_123');
    mock_valid_collectable_call(12345_u64, level, health);
    
    // Call claim_beast
    start_cheat_caller_address(beast_mode_address, player_address);
    beast_mode.claim_beast(adventurer_id, beast_id, prefix, suffix);
    stop_cheat_caller_address(beast_mode_address);
    
    // Verify mint was called once
    assert(mock_beast_nft.get_mint_count() == 1, 'Mint not called once');
    
    // Get the minted beast details
    let beast: Beast = mock_beast_nft.get_beast(0);
    
    // Verify the owner is the same as the adventurer token owner
    assert(beast.owner == player_address, 'Wrong beast owner');
    
    // Verify beast parameters match inputs
    assert(beast.beast_id == beast_id, 'Wrong beast_id');
    assert(beast.prefix == prefix, 'Wrong prefix');
    assert(beast.suffix == suffix, 'Wrong suffix');
    
    // Verify level and health from get_valid_collectable
    assert(beast.level == level, 'Wrong level');
    assert(beast.health == health, 'Wrong health');
    
    // Verify shiny and animated are either 0 or 1
    assert(beast.shiny == 0 || beast.shiny == 1, 'Invalid shiny value');
    assert(beast.animated == 0 || beast.animated == 1, 'Invalid animated value');
}

#[test]
fn test_claim_beast_rare_traits() {
    let (beast_mode, mock_beast_nft) = deploy_beast_mode_with_mock_nft();
    let beast_mode_address = beast_mode.contract_address;
    
    // Test parameters
    let adventurer_id = 1_u64;
    let beast_id = 10_u8;
    let prefix = 1_u8;
    let suffix = 2_u8;
    let player_address = contract_address_const::<PLAYER1>();
    
    // Mock the IERC721 owner_of call
    mock_owner_of_call(player_address);
    
    // Mock the IBeastSystems get_beast_hash call
    mock_beast_hash_call('BEAST_HASH_RARE');
    
    // Test with seed that should produce shiny=1, animated=0
    // For shiny: lower 32 bits should be < 400
    // For animated: upper 32 bits should be >= 400
    // Seed: 0x19000000187 gives: lower=0x187(391), upper=0x190(400)
    let seed_for_shiny = 0x19000000187_u64; // shiny=391<400(1), animated=400>=400(0)
    mock_valid_collectable_call(seed_for_shiny, 5_u16, 100_u16);
    
    // Call claim_beast
    start_cheat_caller_address(beast_mode_address, player_address);
    beast_mode.claim_beast(adventurer_id, beast_id, prefix, suffix);
    stop_cheat_caller_address(beast_mode_address);
    
    // Get the minted beast details
    let beast: Beast = mock_beast_nft.get_beast(0);
    
    // With seed 399, shiny should be 1, animated should be 0
    assert(beast.shiny == 1, 'Expected shiny trait');
    assert(beast.animated == 0, 'Expected no animated trait');
}

#[test]
fn test_claim_beast_no_rare_traits() {
    let (beast_mode, mock_beast_nft) = deploy_beast_mode_with_mock_nft();
    let beast_mode_address = beast_mode.contract_address;
    
    // Test parameters
    let adventurer_id = 1_u64;
    let beast_id = 10_u8;
    let prefix = 1_u8;
    let suffix = 2_u8;
    let player_address = contract_address_const::<PLAYER1>();
    
    // Mock the IERC721 owner_of call
    mock_owner_of_call(player_address);
    
    // Mock the IBeastSystems get_beast_hash call
    mock_beast_hash_call('BEAST_HASH_NORMAL');
    
    // Test with seed that should produce shiny=0, animated=0
    // Both lower and upper 32 bits should be >= 400
    // Use a much larger seed: 0x270F000003E8 gives: lower=1000, upper=9999
    let seed_for_no_rare = 0x270F000003E8_u64; // shiny=1000>=400(0), animated=9999>=400(0)
    mock_valid_collectable_call(seed_for_no_rare, 5_u16, 100_u16);
    
    // Call claim_beast
    start_cheat_caller_address(beast_mode_address, player_address);
    beast_mode.claim_beast(adventurer_id, beast_id, prefix, suffix);
    stop_cheat_caller_address(beast_mode_address);
    
    // Get the minted beast details
    let beast: Beast = mock_beast_nft.get_beast(0);
    
    // With seed 500, both should be 0
    assert(beast.shiny == 0, 'Expected no shiny trait');
    assert(beast.animated == 0, 'Expected no animated trait');
}

#[test]
#[should_panic(expected: ('Invalid collectable',))]
fn test_claim_beast_invalid_collectable() {
    let (beast_mode, _) = deploy_beast_mode_with_mock_nft();
    let beast_mode_address = beast_mode.contract_address;
    
    // Test parameters
    let adventurer_id = 1_u64;
    let beast_id = 10_u8;
    let prefix = 1_u8;
    let suffix = 2_u8;
    let player_address = contract_address_const::<PLAYER1>();
    
    // Set up mocks for this test
    mock_owner_of_call(player_address);
    mock_beast_hash_call('INVALID_HASH');
    mock_valid_collectable_error('NOT_VALID');
    
    // This should panic with 'Invalid collectable'
    start_cheat_caller_address(beast_mode_address, player_address);
    beast_mode.claim_beast(adventurer_id, beast_id, prefix, suffix);
    stop_cheat_caller_address(beast_mode_address);
}

#[test]
fn test_multiple_players_claim_beasts() {
    let (beast_mode, mock_beast_nft) = deploy_beast_mode_with_mock_nft();
    let beast_mode_address = beast_mode.contract_address;
    
    // Setup two different players
    let player1_address = contract_address_const::<PLAYER1>();
    let player2_address = contract_address_const::<PLAYER2>();
    
    // Mock ownership for adventurer 1
    mock_owner_of_call(player1_address);
    
    // Mock beast hash for beast 1
    mock_beast_hash_call('BEAST1_HASH');
    
    // Mock valid collectable for beast 1
    mock_valid_collectable_call(1234_u64, 5_u16, 100_u16);
    
    // Player 1 claims their beast
    start_cheat_caller_address(beast_mode_address, player1_address);
    beast_mode.claim_beast(1_u64, 10_u8, 1_u8, 1_u8);
    stop_cheat_caller_address(beast_mode_address);
    
    // Mock ownership for adventurer 2
    mock_owner_of_call(player2_address);
    
    // Mock beast hash for beast 2
    mock_beast_hash_call('BEAST2_HASH');
    
    // Mock valid collectable for beast 2
    mock_valid_collectable_call(5678_u64, 10_u16, 200_u16);
    
    // Player 2 claims their beast
    start_cheat_caller_address(beast_mode_address, player2_address);
    beast_mode.claim_beast(2_u64, 20_u8, 2_u8, 2_u8);
    stop_cheat_caller_address(beast_mode_address);
    
    // Verify both beasts were minted
    assert(mock_beast_nft.get_mint_count() == 2, 'Should have 2 mints');
    
    // Verify first beast (player 1)
    let beast1: Beast = mock_beast_nft.get_beast(0);
    assert(beast1.owner == player1_address, 'Wrong owner for beast 1');
    assert(beast1.beast_id == 10, 'Wrong ID for beast 1');
    assert(beast1.prefix == 1, 'Wrong prefix for beast 1');
    assert(beast1.suffix == 1, 'Wrong suffix for beast 1');
    assert(beast1.level == 5, 'Wrong level for beast 1');
    assert(beast1.health == 100, 'Wrong health for beast 1');
    
    // Verify second beast (player 2)
    let beast2: Beast = mock_beast_nft.get_beast(1);
    assert(beast2.owner == player2_address, 'Wrong owner for beast 2');
    assert(beast2.beast_id == 20, 'Wrong ID for beast 2');
    assert(beast2.prefix == 2, 'Wrong prefix for beast 2');
    assert(beast2.suffix == 2, 'Wrong suffix for beast 2');
    assert(beast2.level == 10, 'Wrong level for beast 2');
    assert(beast2.health == 200, 'Wrong health for beast 2');
}

#[test]
fn test_initiate_airdrop() {
    let (beast_mode, _) = deploy_beast_mode_with_mock_nft();
    
    // Set block number
    start_cheat_block_number(beast_mode.contract_address, 1000);
    
    // Mock VRF call
    mock_vrf_consume_random('VRF_SEED_123');
    
    // Verify airdrop not initiated
    assert(beast_mode.get_airdrop_block_number() == 0, 'Airdrop already initiated');
    assert(beast_mode.get_airdrop_count() == 0, 'Airdrop count not zero');
    
    // Initiate airdrop
    beast_mode.initiate_airdrop();
    
    // Verify airdrop was initiated
    assert(beast_mode.get_airdrop_block_number() == 1100, 'Wrong airdrop block number');
    assert(beast_mode.get_airdrop_count() == 75, 'Wrong airdrop count');
    
    stop_cheat_block_number(beast_mode.contract_address);
}

#[test]
#[should_panic(expected: ('Airdrop already initiated',))]
fn test_initiate_airdrop_twice() {
    let (beast_mode, _) = deploy_beast_mode_with_mock_nft();
    
    // Set block number
    start_cheat_block_number(beast_mode.contract_address, 1000);
    
    // Mock VRF call for first initiation
    mock_vrf_consume_random('VRF_SEED_123');
    
    // Initiate airdrop first time
    beast_mode.initiate_airdrop();
    
    // Try to initiate again - should panic
    beast_mode.initiate_airdrop();
    
    stop_cheat_block_number(beast_mode.contract_address);
}

#[test]
fn test_airdrop_legacy_beasts() {
    let (beast_mode, mock_beast_nft) = deploy_beast_mode_with_mock_nft();
    
    // First initiate the airdrop
    start_cheat_block_number(beast_mode.contract_address, 1000);
    
    // Mock VRF call for initiation
    mock_vrf_consume_random('VRF_SEED_123');
    
    beast_mode.initiate_airdrop();
    
    // Move forward in blocks to make airdrop ready
    start_cheat_block_number(beast_mode.contract_address, 1200);
    
    // Set up block hash for the airdrop block (block 1000 where airdrop was initiated)
    let block_hash = 'BLOCK_HASH_SEED';
    start_cheat_block_hash(beast_mode.contract_address, 1000, block_hash);
    
    // Mock getBeast calls for IDs 76-80
    let legacy_owner = contract_address_const::<'LEGACY_OWNER'>();
    
    // Mock getBeast for multiple calls (we'll call with limit 5)
    mock_getBeast_call(5, 1, 2, 10, 50, 5);
    
    // Mock premint_collectable calls (called once per beast)
    mock_premint_collectable_call(5);
    
    // Call airdrop_legacy_beasts with limit of 5
    beast_mode.airdrop_legacy_beasts(5);
    
    // Verify airdrop count increased
    assert(beast_mode.get_airdrop_count() == 80, 'Wrong airdrop count');
    
    // Verify 5 beasts were minted
    assert(mock_beast_nft.get_mint_count() == 5, 'Wrong mint count');
    
    // Verify each beast has correct owner and valid attributes
    let mut i: u32 = 0;
    loop {
        if i >= 5 {
            break;
        }
        
        let beast: Beast = mock_beast_nft.get_beast(i.into());
        assert(beast.owner == legacy_owner, 'Wrong beast owner');
        assert(beast.beast_id == 5, 'Invalid beast ID'); // From our mock
        assert(beast.level == 10, 'Invalid level'); // From our mock
        assert(beast.health == 50, 'Invalid health'); // From our mock
        assert(beast.shiny == 0 || beast.shiny == 1, 'Invalid shiny');
        assert(beast.animated == 0 || beast.animated == 1, 'Invalid animated');
        
        i += 1;
    };
    
    stop_cheat_block_number(beast_mode.contract_address);
    stop_cheat_block_hash(beast_mode.contract_address, 1000);
}

#[test]
fn test_claim_reward_token() {
    let (beast_mode, _) = deploy_beast_mode_with_mock_nft();
    let beast_mode_address = beast_mode.contract_address;
    
    let token_id = 1_u64;
    let player_address = contract_address_const::<PLAYER1>();
    
    // Mock IERC721 owner_of for game token
    mock_owner_of_call(player_address);
    
    // Mock get_adventurer_level - returning Ok with level 10
    let level = 10_u8;
    mock_adventurer_level_call(level);
    
    // Mock ERC20 transfer
    mock_erc20_transfer_call(true);
    
    // Call claim_reward_token as the token owner
    start_cheat_caller_address(beast_mode_address, player_address);
    beast_mode.claim_reward_token(token_id);
    stop_cheat_caller_address(beast_mode_address);
}

#[test]
#[should_panic(expected: ('No reward tokens available',))]
fn test_claim_reward_token_no_balance() {
    let (beast_mode, _) = deploy_beast_mode_with_mock_nft();
    let beast_mode_address = beast_mode.contract_address;
    
    let token_id = 1_u64;
    let player_address = contract_address_const::<PLAYER1>();
    
    // Mock token ownership
    mock_owner_of_call(player_address);
    
    // Set contract reward token balance to 0
    mock_balance_of_zero_call();
    
    // This should panic
    start_cheat_caller_address(beast_mode_address, player_address);
    beast_mode.claim_reward_token(token_id);
    stop_cheat_caller_address(beast_mode_address);
}

#[test]
#[should_panic(expected: ('Not token owner',))]
fn test_claim_reward_token_not_owner() {
    let (beast_mode, _) = deploy_beast_mode_with_mock_nft();
    let beast_mode_address = beast_mode.contract_address;
    
    let token_id = 1_u64;
    let owner_address = contract_address_const::<PLAYER1>();
    let caller_address = contract_address_const::<PLAYER2>();
    
    // Setup token ownership to PLAYER1
    mock_owner_of_call(owner_address);

    // Call as PLAYER2 - should panic
    start_cheat_caller_address(beast_mode_address, caller_address);
    beast_mode.claim_reward_token(token_id);
    stop_cheat_caller_address(beast_mode_address);
}

#[test]
#[should_panic(expected: ('Token already claimed',))]
fn test_claim_reward_token_already_claimed() {
    let (beast_mode, _) = deploy_beast_mode_with_mock_nft();
    let beast_mode_address = beast_mode.contract_address;
    
    let token_id = 1_u64;
    let player_address = contract_address_const::<PLAYER1>();
    
    // Mock token ownership
    mock_owner_of_call_times(player_address, 2);
    
    // Set adventurer level
    mock_adventurer_level_call_once(10_u8);
    
    // Mock transfer for first successful claim
    mock_erc20_transfer_call(true);
    
    // First claim - should succeed
    start_cheat_caller_address(beast_mode_address, player_address);
    beast_mode.claim_reward_token(token_id);
    
    // Second claim - should panic
    beast_mode.claim_reward_token(token_id);
    stop_cheat_caller_address(beast_mode_address);
}

#[test]
#[should_panic(expected: ('Invalid adventurer',))]
fn test_claim_reward_token_invalid_adventurer() {
    let (beast_mode, _) = deploy_beast_mode_with_mock_nft();
    let beast_mode_address = beast_mode.contract_address;
    
    let token_id = 1_u64;
    let player_address = contract_address_const::<PLAYER1>();
    
    // Mock token ownership
    mock_owner_of_call(player_address);
    
    // Set adventurer level to return error
    mock_adventurer_level_error('INVALID_ADVENTURER');
    
    // This should panic
    start_cheat_caller_address(beast_mode_address, player_address);
    beast_mode.claim_reward_token(token_id);
    stop_cheat_caller_address(beast_mode_address);
}