use starknet::{ContractAddress, contract_address_const};
use snforge_std::{
    declare, DeclareResultTrait, ContractClassTrait,
    start_cheat_caller_address, stop_cheat_caller_address,
    start_cheat_block_number, stop_cheat_block_number,
    start_cheat_block_hash, stop_cheat_block_hash,
    mock_call
};

use beast_mode::interfaces::{
    IBeastModeDispatcher, IBeastModeDispatcherTrait, DataResult,
    ILegacyBeastsDispatcher, ILegacyBeastsDispatcherTrait
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

// Real mainnet legacy beast contract address
fn LEGACY_BEASTS_MAINNET_ADDRESS() -> ContractAddress {
    contract_address_const::<0x0158160018d590d93528995b340260e65aedd76d28a686e9daa5c4e8fad0c5dd>()
}

// Contract addresses for mocking (non-legacy)
fn GAME_TOKEN_ADDRESS() -> ContractAddress {
    contract_address_const::<'GAME_TOKEN'>()
}

fn GAME_COLLECTABLE_ADDRESS() -> ContractAddress {
    contract_address_const::<'GAME_COLLECTABLE'>()
}

fn ADVENTURER_SYSTEMS_ADDRESS() -> ContractAddress {
    contract_address_const::<'ADVENTURER_SYSTEMS'>()
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

// Deploy beast mode with real legacy beast contract (for fork tests)
fn deploy_beast_mode_with_fork() -> (IBeastModeDispatcher, IMockBeastNFTDispatcher) {
    let mock_beast_nft = deploy_mock_beast_nft();
    
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
                mock_beast_nft.contract_address.into(),
                LEGACY_BEASTS_MAINNET_ADDRESS().into(), // Use real mainnet address
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
    
    (IBeastModeDispatcher { contract_address }, mock_beast_nft)
}

// Deploy beast mode with mock addresses (for non-legacy tests)
fn deploy_beast_mode_with_mocks() -> (IBeastModeDispatcher, IMockBeastNFTDispatcher) {
    let mock_beast_nft = deploy_mock_beast_nft();
    
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
                mock_beast_nft.contract_address.into(),
                contract_address_const::<'LEGACY_BEASTS'>().into(), // Mock address
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
    
    (IBeastModeDispatcher { contract_address }, mock_beast_nft)
}

// Helper functions for mocking
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

fn mock_balance_of_large_call() {
    mock_call(
        REWARD_TOKEN_ADDRESS(),
        selector!("balance_of"),
        1000000000000000000000_u256,
        2  // Contract calls balance_of twice in claim_reward_token
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

fn mock_balance_of_large_call_times(times: u32) {
    mock_call(
        REWARD_TOKEN_ADDRESS(),
        selector!("balance_of"),
        1000000000000000000000_u256,
        times * 2  // Each claim call uses balance_of twice
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

fn mock_premint_collectable_call(times: u32) {
    mock_call(
        GAME_COLLECTABLE_ADDRESS(),
        selector!("premint_collectable"),
        12345_u64,
        times
    );
}

// VRF contract address
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

// ===========================================
// CLAIM BEAST TESTS (using mocks for all)
// ===========================================

#[test]
fn test_claim_beast_mint_parameters() {
    let (beast_mode, mock_beast_nft) = deploy_beast_mode_with_mocks();
    let beast_mode_address = beast_mode.contract_address;
    
    // Test parameters
    let adventurer_id = 1_u64;
    let beast_id = 10_u8;
    let prefix = 1_u8;
    let suffix = 2_u8;
    let level = 5_u16;
    let health = 100_u16;
    let player_address = contract_address_const::<PLAYER1>();
    
    // Set up mocks
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
    let (beast_mode, mock_beast_nft) = deploy_beast_mode_with_mocks();
    let beast_mode_address = beast_mode.contract_address;
    
    // Test parameters
    let adventurer_id = 1_u64;
    let beast_id = 10_u8;
    let prefix = 1_u8;
    let suffix = 2_u8;
    let player_address = contract_address_const::<PLAYER1>();
    
    // Mock calls
    mock_owner_of_call(player_address);
    mock_beast_hash_call('BEAST_HASH_RARE');
    
    // Test with seed that should produce shiny=1, animated=0
    let seed_for_shiny = 0x19000000187_u64; // shiny=391<400(1), animated=400>=400(0)
    mock_valid_collectable_call(seed_for_shiny, 5_u16, 100_u16);
    
    // Call claim_beast
    start_cheat_caller_address(beast_mode_address, player_address);
    beast_mode.claim_beast(adventurer_id, beast_id, prefix, suffix);
    stop_cheat_caller_address(beast_mode_address);
    
    // Get the minted beast details
    let beast: Beast = mock_beast_nft.get_beast(0);
    
    // With seed 391, shiny should be 1, animated should be 0
    assert(beast.shiny == 1, 'Expected shiny trait');
    assert(beast.animated == 0, 'Expected no animated trait');
}

#[test]
fn test_claim_beast_no_rare_traits() {
    let (beast_mode, mock_beast_nft) = deploy_beast_mode_with_mocks();
    let beast_mode_address = beast_mode.contract_address;
    
    // Test parameters
    let adventurer_id = 1_u64;
    let beast_id = 10_u8;
    let prefix = 1_u8;
    let suffix = 2_u8;
    let player_address = contract_address_const::<PLAYER1>();
    
    // Mock calls
    mock_owner_of_call(player_address);
    mock_beast_hash_call('BEAST_HASH_NORMAL');
    
    // Test with seed that should produce shiny=0, animated=0
    let seed_for_no_rare = 0x270F000003E8_u64; // shiny=1000>=400(0), animated=9999>=400(0)
    mock_valid_collectable_call(seed_for_no_rare, 5_u16, 100_u16);
    
    // Call claim_beast
    start_cheat_caller_address(beast_mode_address, player_address);
    beast_mode.claim_beast(adventurer_id, beast_id, prefix, suffix);
    stop_cheat_caller_address(beast_mode_address);
    
    // Get the minted beast details
    let beast: Beast = mock_beast_nft.get_beast(0);
    
    // Both should be 0
    assert(beast.shiny == 0, 'Expected no shiny trait');
    assert(beast.animated == 0, 'Expected no animated trait');
}

#[test]
#[should_panic(expected: ('Invalid collectable',))]
fn test_claim_beast_invalid_collectable() {
    let (beast_mode, _) = deploy_beast_mode_with_mocks();
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
    let (beast_mode, mock_beast_nft) = deploy_beast_mode_with_mocks();
    let beast_mode_address = beast_mode.contract_address;
    
    // Setup two different players
    let player1_address = contract_address_const::<PLAYER1>();
    let player2_address = contract_address_const::<PLAYER2>();
    
    // Mock ownership for adventurer 1
    mock_owner_of_call(player1_address);
    mock_beast_hash_call('BEAST1_HASH');
    mock_valid_collectable_call(1234_u64, 5_u16, 100_u16);
    
    // Player 1 claims their beast
    start_cheat_caller_address(beast_mode_address, player1_address);
    beast_mode.claim_beast(1_u64, 10_u8, 1_u8, 1_u8);
    stop_cheat_caller_address(beast_mode_address);
    
    // Mock ownership for adventurer 2
    mock_owner_of_call(player2_address);
    mock_beast_hash_call('BEAST2_HASH');
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

// ===========================================
// INITIATE AIRDROP TESTS (using mocks)
// ===========================================

#[test]
fn test_initiate_airdrop() {
    let (beast_mode, _) = deploy_beast_mode_with_mocks();
    
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
    let (beast_mode, _) = deploy_beast_mode_with_mocks();
    
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

// ===========================================
// REWARD TOKEN TESTS (using mocks for all)
// ===========================================

#[test]
fn test_claim_reward_token() {
    let (beast_mode, _) = deploy_beast_mode_with_mocks();
    let beast_mode_address = beast_mode.contract_address;
    
    let token_id = 1_u64;
    let player_address = contract_address_const::<PLAYER1>();
    
    // Mock IERC721 owner_of for game token
    mock_owner_of_call(player_address);
    
    // Mock ERC20 balance_of call
    mock_balance_of_large_call();
    
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
    let (beast_mode, _) = deploy_beast_mode_with_mocks();
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
    let (beast_mode, _) = deploy_beast_mode_with_mocks();
    let beast_mode_address = beast_mode.contract_address;
    
    let token_id = 1_u64;
    let owner_address = contract_address_const::<PLAYER1>();
    let caller_address = contract_address_const::<PLAYER2>();
    
    // Setup token ownership to PLAYER1
    mock_owner_of_call(owner_address);
    
    // Set contract reward token balance
    mock_balance_of_large_call();
    
    // Call as PLAYER2 - should panic
    start_cheat_caller_address(beast_mode_address, caller_address);
    beast_mode.claim_reward_token(token_id);
    stop_cheat_caller_address(beast_mode_address);
}

#[test]
#[should_panic(expected: ('Token already claimed',))]
fn test_claim_reward_token_already_claimed() {
    let (beast_mode, _) = deploy_beast_mode_with_mocks();
    let beast_mode_address = beast_mode.contract_address;
    
    let token_id = 1_u64;
    let player_address = contract_address_const::<PLAYER1>();
    
    // Mock token ownership
    mock_owner_of_call_times(player_address, 2);
    
    // Set contract reward token balance
    mock_balance_of_large_call_times(2);
    
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
    let (beast_mode, _) = deploy_beast_mode_with_mocks();
    let beast_mode_address = beast_mode.contract_address;
    
    let token_id = 1_u64;
    let player_address = contract_address_const::<PLAYER1>();
    
    // Mock token ownership
    mock_owner_of_call(player_address);
    
    // Set contract reward token balance
    mock_balance_of_large_call();
    
    // Set adventurer level to return error
    mock_adventurer_level_error('INVALID_ADVENTURER');
    
    // This should panic
    start_cheat_caller_address(beast_mode_address, player_address);
    beast_mode.claim_reward_token(token_id);
    stop_cheat_caller_address(beast_mode_address);
}

// ===========================================
// FORK TESTS (using real mainnet data)
// ===========================================

#[test]
#[fork("mainnet")]
fn test_legacy_beasts_total_supply_fork() {
    // Test real legacy beast contract with correct method name
    let legacy_beasts = ILegacyBeastsDispatcher { 
        contract_address: LEGACY_BEASTS_MAINNET_ADDRESS() 
    };
    
    // Test tokenSupply method (corrected from totalSupply)
    let token_supply = legacy_beasts.tokenSupply();
    assert(token_supply > 75, 'Token supply should be > 75');
    
    // Also test basic functionality
    let beast_76 = legacy_beasts.getBeast(76);
    assert(beast_76.id > 0, 'Beast 76 should have valid ID');
    
    let owner_76 = legacy_beasts.ownerOf(76);
    assert(owner_76.into() != 0, 'Beast 76 should have owner');
}

#[test]
#[fork("mainnet")]
fn test_legacy_beast_data_fork() {
    let legacy_beasts = ILegacyBeastsDispatcher { 
        contract_address: LEGACY_BEASTS_MAINNET_ADDRESS() 
    };
    
    // Test getting data for beast ID 76 and above (first 75 have 0 health/level)
    let beast_76 = legacy_beasts.getBeast(76);
    let owner_76 = legacy_beasts.ownerOf(76);
    
    // Verify we get valid data from beast 76 onwards
    assert(beast_76.id > 0, 'Beast ID should be > 0');
    assert(beast_76.level > 0, 'Beast level should be > 0');
    assert(beast_76.health > 0, 'Beast health should be > 0');
    
    // Verify owner is not zero address
    assert(owner_76.into() != 0, 'Owner should not be zero');
    
    // Test a few more beasts to ensure consistency
    let beast_100 = legacy_beasts.getBeast(100);
    assert(beast_100.id > 0, 'Beast 100 ID should be > 0');
    assert(beast_100.level > 0, 'Beast 100 level should be > 0');
    assert(beast_100.health > 0, 'Beast 100 health should be > 0');
}

#[test]
#[fork("mainnet")]
fn test_airdrop_legacy_beasts_fork() {
    let (beast_mode, mock_beast_nft) = deploy_beast_mode_with_fork();
    
    // First initiate the airdrop
    start_cheat_block_number(beast_mode.contract_address, 1000);
    
    // Mock VRF call for initiation
    mock_vrf_consume_random('VRF_SEED_123');
    
    beast_mode.initiate_airdrop();
    
    // Move forward in blocks to make airdrop ready
    start_cheat_block_number(beast_mode.contract_address, 1200);
    
    // Set up block hash for the airdrop block
    let block_hash = 'BLOCK_HASH_SEED';
    start_cheat_block_hash(beast_mode.contract_address, 1000, block_hash);
    
    // Mock premint_collectable calls
    mock_premint_collectable_call(3);
    
    // Get real legacy beast contract  
    let legacy_beasts = ILegacyBeastsDispatcher { 
        contract_address: LEGACY_BEASTS_MAINNET_ADDRESS() 
    };
    
    // Call airdrop_legacy_beasts with small limit to test with real data
    beast_mode.airdrop_legacy_beasts(3);
    
    // Verify airdrop count increased (starts at 75, adds 3)
    assert(beast_mode.get_airdrop_count() == 78, 'Wrong airdrop count');
    
    // Verify beasts were minted
    assert(mock_beast_nft.get_mint_count() == 3, 'Wrong mint count');
    
    // Verify each beast has valid attributes from real contract
    let mut i: u32 = 0;
    loop {
        if i >= 3 {
            break;
        }
        
        let beast: Beast = mock_beast_nft.get_beast(i.into());
        
        // Get the real beast data from mainnet (76, 77, 78)
        let real_beast = legacy_beasts.getBeast((76 + i).into());
        let real_owner = legacy_beasts.ownerOf((76 + i).into());
        
        // Verify the minted beast matches real legacy beast data
        assert(beast.owner == real_owner, 'Wrong beast owner');
        assert(beast.beast_id == real_beast.id, 'Wrong beast ID');
        assert(beast.prefix == real_beast.prefix, 'Wrong prefix');
        assert(beast.suffix == real_beast.suffix, 'Wrong suffix');
        assert(beast.level == real_beast.level, 'Wrong level');
        assert(beast.health == real_beast.health, 'Wrong health');
        assert(beast.shiny == 0 || beast.shiny == 1, 'Invalid shiny');
        assert(beast.animated == 0 || beast.animated == 1, 'Invalid animated');
        
        i += 1;
    };
    
    stop_cheat_block_number(beast_mode.contract_address);
    stop_cheat_block_hash(beast_mode.contract_address, 1000);
}