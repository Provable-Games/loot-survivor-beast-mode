use starknet::{ContractAddress, contract_address_const};
use snforge_std::{
    declare, DeclareResultTrait, ContractClassTrait,
    start_cheat_caller_address, stop_cheat_caller_address,
    start_cheat_block_number, stop_cheat_block_number,
    start_cheat_block_hash, stop_cheat_block_hash,
    mock_call
};

use beast_mode::interfaces::{
    IBeastModeDispatcher, IBeastModeDispatcherTrait,
};

// Import mock contracts
mod mock_contracts;

use mock_contracts::{
    IMockBeastNFTDispatcher, IMockBeastNFTDispatcherTrait,
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

// Deploy the beast mode contract with mock beast NFT and mock addresses for others
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
    
    (IBeastModeDispatcher { contract_address }, mock_beast_nft)
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
    let player_address = contract_address_const::<PLAYER1>();
    
    // Mock the IERC721 owner_of call for the game token
    let player_felt: felt252 = player_address.into();
    mock_call(
        GAME_TOKEN_ADDRESS(),
        selector!("owner_of"),
        array![player_felt].span(),
        1
    );
    
    // Mock the IBeastSystems get_beast_hash call
    let expected_hash = 'BEAST_HASH_123';
    mock_call(
        GAME_COLLECTABLE_ADDRESS(),
        selector!("get_beast_hash"),
        array![expected_hash].span(),
        1
    );
    
    // Mock the IBeastSystems get_valid_collectable call - returning Ok result
    let seed = 12345678_u64;
    let level = 5_u16;
    let health = 100_u16;
    // DataResult::Ok((seed, level, health)) - tuple of (u64, u16, u16) = 4 elements total
    let valid_collectable_return: Array<felt252> = array![0, seed.into(), level.into(), health.into()];
    mock_call(
        GAME_COLLECTABLE_ADDRESS(),
        selector!("get_valid_collectable"),
        valid_collectable_return.span(),
        1
    );
    
    // Call claim_beast
    start_cheat_caller_address(beast_mode_address, player_address);
    beast_mode.claim_beast(adventurer_id, beast_id, prefix, suffix);
    stop_cheat_caller_address(beast_mode_address);
    
    // Verify mint was called once
    assert(mock_beast_nft.get_mint_count() == 1, 'Mint not called once');
    
    // Get the minted beast details
    let (
        minted_to,
        minted_beast_id,
        minted_prefix,
        minted_suffix,
        minted_level,
        minted_health,
        minted_shiny,
        minted_animated
    ) = mock_beast_nft.get_last_mint();
    
    // Verify the owner is the same as the adventurer token owner
    assert(minted_to == player_address, 'Wrong beast owner');
    
    // Verify beast parameters match inputs
    assert(minted_beast_id == beast_id, 'Wrong beast_id');
    assert(minted_prefix == prefix, 'Wrong prefix');
    assert(minted_suffix == suffix, 'Wrong suffix');
    
    // Verify level and health from get_valid_collectable
    assert(minted_level == level, 'Wrong level');
    assert(minted_health == health, 'Wrong health');
    
    // Verify shiny and animated are either 0 or 1
    assert(minted_shiny == 0 || minted_shiny == 1, 'Invalid shiny value');
    assert(minted_animated == 0 || minted_animated == 1, 'Invalid animated value');
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
    let player_felt: felt252 = player_address.into();
    mock_call(
        GAME_TOKEN_ADDRESS(),
        selector!("owner_of"),
        array![player_felt].span(),
        1
    );
    
    // Mock the IBeastSystems get_beast_hash call
    mock_call(
        GAME_COLLECTABLE_ADDRESS(),
        selector!("get_beast_hash"),
        array!['BEAST_HASH_RARE'].span(),
        1
    );
    
    // Test with seed that should produce shiny=1, animated=0
    // For shiny: (399 & 0xFFFFFFFF) % 10000 = 399 < 400, so shiny = 1
    let seed_for_shiny = 399_u64;
    mock_call(
        GAME_COLLECTABLE_ADDRESS(),
        selector!("get_valid_collectable"),
        array![0, seed_for_shiny.into(), 5, 100].span(), // DataResult::Ok
        1
    );
    
    // Call claim_beast
    start_cheat_caller_address(beast_mode_address, player_address);
    beast_mode.claim_beast(adventurer_id, beast_id, prefix, suffix);
    stop_cheat_caller_address(beast_mode_address);
    
    // Get the minted beast details
    let (_, _, _, _, _, _, shiny, animated) = mock_beast_nft.get_last_mint();
    
    // With seed 399, shiny should be 1, animated should be 0
    assert(shiny == 1, 'Expected shiny trait');
    assert(animated == 0, 'Expected no animated trait');
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
    let player_felt: felt252 = player_address.into();
    mock_call(
        GAME_TOKEN_ADDRESS(),
        selector!("owner_of"),
        array![player_felt].span(),
        1
    );
    
    // Mock the IBeastSystems get_beast_hash call
    mock_call(
        GAME_COLLECTABLE_ADDRESS(),
        selector!("get_beast_hash"),
        array!['BEAST_HASH_NORMAL'].span(),
        1
    );
    
    // Test with seed that should produce shiny=0, animated=0
    let seed_for_no_rare = 500_u64;
    mock_call(
        GAME_COLLECTABLE_ADDRESS(),
        selector!("get_valid_collectable"),
        array![0, seed_for_no_rare.into(), 5, 100].span(), // DataResult::Ok
        1
    );
    
    // Call claim_beast
    start_cheat_caller_address(beast_mode_address, player_address);
    beast_mode.claim_beast(adventurer_id, beast_id, prefix, suffix);
    stop_cheat_caller_address(beast_mode_address);
    
    // Get the minted beast details
    let (_, _, _, _, _, _, shiny, animated) = mock_beast_nft.get_last_mint();
    
    // With seed 500, both should be 0
    assert(shiny == 0, 'Expected no shiny trait');
    assert(animated == 0, 'Expected no animated trait');
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
    
    // Mock the IERC721 owner_of call
    let player_felt: felt252 = player_address.into();
    mock_call(
        GAME_TOKEN_ADDRESS(),
        selector!("owner_of"),
        array![player_felt].span(),
        1
    );
    
    // Mock the IBeastSystems get_beast_hash call
    mock_call(
        GAME_COLLECTABLE_ADDRESS(),
        selector!("get_beast_hash"),
        array!['INVALID_HASH'].span(),
        1
    );
    
    // Mock get_valid_collectable to return Err
    mock_call(
        GAME_COLLECTABLE_ADDRESS(),
        selector!("get_valid_collectable"),
        array![1, 'NOT_VALID'].span(), // 1 for DataResult::Err variant
        1
    );
    
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
    let player1_felt: felt252 = player1_address.into();
    mock_call(
        GAME_TOKEN_ADDRESS(),
        selector!("owner_of"),
        array![player1_felt].span(),
        1
    );
    
    // Mock beast hash for beast 1
    mock_call(
        GAME_COLLECTABLE_ADDRESS(),
        selector!("get_beast_hash"),
        array!['BEAST1_HASH'].span(),
        1
    );
    
    // Mock valid collectable for beast 1
    mock_call(
        GAME_COLLECTABLE_ADDRESS(),
        selector!("get_valid_collectable"),
        array![0, 1234_u64.into(), 5, 100].span(), // DataResult::Ok
        1
    );
    
    // Player 1 claims their beast
    start_cheat_caller_address(beast_mode_address, player1_address);
    beast_mode.claim_beast(1_u64, 10_u8, 1_u8, 1_u8);
    stop_cheat_caller_address(beast_mode_address);
    
    // Mock ownership for adventurer 2
    let player2_felt: felt252 = player2_address.into();
    mock_call(
        GAME_TOKEN_ADDRESS(),
        selector!("owner_of"),
        array![player2_felt].span(),
        1
    );
    
    // Mock beast hash for beast 2
    mock_call(
        GAME_COLLECTABLE_ADDRESS(),
        selector!("get_beast_hash"),
        array!['BEAST2_HASH'].span(),
        1
    );
    
    // Mock valid collectable for beast 2
    mock_call(
        GAME_COLLECTABLE_ADDRESS(),
        selector!("get_valid_collectable"),
        array![0, 5678_u64.into(), 10, 200].span(), // DataResult::Ok
        1
    );
    
    // Player 2 claims their beast
    start_cheat_caller_address(beast_mode_address, player2_address);
    beast_mode.claim_beast(2_u64, 20_u8, 2_u8, 2_u8);
    stop_cheat_caller_address(beast_mode_address);
    
    // Verify both beasts were minted
    assert(mock_beast_nft.get_mint_count() == 2, 'Should have 2 mints');
    
    // Get all beasts
    let all_beasts = mock_beast_nft.get_all_beasts();
    
    // Verify first beast (player 1)
    let beast1 = *all_beasts.at(0);
    assert(beast1.owner == player1_address, 'Wrong owner for beast 1');
    assert(beast1.beast_id == 10, 'Wrong ID for beast 1');
    assert(beast1.prefix == 1, 'Wrong prefix for beast 1');
    assert(beast1.suffix == 1, 'Wrong suffix for beast 1');
    assert(beast1.level == 5, 'Wrong level for beast 1');
    assert(beast1.health == 100, 'Wrong health for beast 1');
    
    // Verify second beast (player 2)
    let beast2 = *all_beasts.at(1);
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
    beast_mode.initiate_airdrop();
    
    // Move forward in blocks to make airdrop ready
    start_cheat_block_number(beast_mode.contract_address, 1200);
    
    // Set up block hash for the airdrop block
    let block_hash = 'BLOCK_HASH_SEED';
    start_cheat_block_hash(beast_mode.contract_address, 1100, block_hash);
    
    // Mock legacy beasts total supply
    mock_call(
        LEGACY_BEASTS_ADDRESS(),
        selector!("totalSupply"),
        array![100_u256.low.into(), 0].span(), // Total supply of 100
        1
    );
    
    // Mock getBeast calls for IDs 76-80
    let legacy_owner = contract_address_const::<'LEGACY_OWNER'>();
    let legacy_owner_felt: felt252 = legacy_owner.into();
    
    // Mock getBeast for multiple calls (we'll call with limit 5)
    let getBeast_return: Array<felt252> = array![5_u8.into(), 1_u8.into(), 2_u8.into(), 10_u16.into(), 50_u16.into()];
    mock_call(
        LEGACY_BEASTS_ADDRESS(),
        selector!("getBeast"),
        getBeast_return.span(),
        5
    );
    
    // Mock ownerOf for legacy beasts
    mock_call(
        LEGACY_BEASTS_ADDRESS(),
        selector!("ownerOf"),
        array![legacy_owner_felt].span(),
        5
    );
    
    // Call airdrop_legacy_beasts with limit of 5
    beast_mode.airdrop_legacy_beasts(5);
    
    // Verify airdrop count increased
    assert(beast_mode.get_airdrop_count() == 80, 'Wrong airdrop count');
    
    // Verify 5 beasts were minted
    assert(mock_beast_nft.get_mint_count() == 5, 'Wrong mint count');
    
    // Verify all minted beasts
    let all_beasts = mock_beast_nft.get_all_beasts();
    assert(all_beasts.len() == 5, 'Wrong number of beasts');
    
    // Verify each beast has correct owner and valid attributes
    let mut i: u32 = 0;
    loop {
        if i >= 5 {
            break;
        }
        
        let beast = *all_beasts.at(i);
        assert(beast.owner == legacy_owner, 'Wrong beast owner');
        assert(beast.beast_id == 5, 'Invalid beast ID'); // From our mock
        assert(beast.level == 10, 'Invalid level'); // From our mock
        assert(beast.health == 50, 'Invalid health'); // From our mock
        assert(beast.shiny == 0 || beast.shiny == 1, 'Invalid shiny');
        assert(beast.animated == 0 || beast.animated == 1, 'Invalid animated');
        
        i += 1;
    };
    
    stop_cheat_block_number(beast_mode.contract_address);
    stop_cheat_block_hash(beast_mode.contract_address, 1100);
}

#[test]
fn test_claim_reward_token() {
    let (beast_mode, _) = deploy_beast_mode_with_mock_nft();
    let beast_mode_address = beast_mode.contract_address;
    
    let token_id = 1_u64;
    let player_address = contract_address_const::<PLAYER1>();
    
    // Mock ERC20 balance check for contract
    let contract_balance = 1000000000000000000000_u256; // 1000 tokens with 18 decimals
    let balance_return: Array<felt252> = array![contract_balance.low.into(), contract_balance.high.into()];
    mock_call(
        REWARD_TOKEN_ADDRESS(),
        selector!("balance_of"),
        balance_return.span(),
        2 // Called twice in the function
    );
    
    // Mock IERC721 owner_of for game token
    let player_felt: felt252 = player_address.into();
    mock_call(
        GAME_TOKEN_ADDRESS(),
        selector!("owner_of"),
        array![player_felt].span(),
        1
    );
    
    // Mock get_adventurer_level - returning Ok with level 10
    let level = 10_u8;
    mock_call(
        ADVENTURER_SYSTEMS_ADDRESS(),
        selector!("get_adventurer_level"),
        array![0, level.into()].span(), // DataResult::Ok variant with level
        1
    );
    
    // Mock ERC20 transfer
    mock_call(
        REWARD_TOKEN_ADDRESS(),
        selector!("transfer"),
        array![1].span(), // Return true for successful transfer
        1
    );
    
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
    let player_felt: felt252 = player_address.into();
    mock_call(
        GAME_TOKEN_ADDRESS(),
        selector!("owner_of"),
        array![player_felt].span(),
        1
    );
    
    // Set contract reward token balance to 0
    mock_call(
        REWARD_TOKEN_ADDRESS(),
        selector!("balance_of"),
        array![0, 0].span(), // 0 balance
        1
    );
    
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
    let owner_felt: felt252 = owner_address.into();
    mock_call(
        GAME_TOKEN_ADDRESS(),
        selector!("owner_of"),
        array![owner_felt].span(),
        1
    );
    
    // Set contract reward token balance
    mock_call(
        REWARD_TOKEN_ADDRESS(),
        selector!("balance_of"),
        array![1000000000000000000000_u256.low.into(), 0].span(),
        1
    );
    
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
    let player_felt: felt252 = player_address.into();
    mock_call(
        GAME_TOKEN_ADDRESS(),
        selector!("owner_of"),
        array![player_felt].span(),
        2 // Called twice - once for each claim attempt
    );
    
    // Set contract reward token balance
    mock_call(
        REWARD_TOKEN_ADDRESS(),
        selector!("balance_of"),
        array![1000000000000000000000_u256.low.into(), 0].span(),
        2
    );
    
    // Set adventurer level
    mock_call(
        ADVENTURER_SYSTEMS_ADDRESS(),
        selector!("get_adventurer_level"),
        array![0, 10_u8.into()].span(),
        1 // Only called once on first successful claim
    );
    
    // Mock transfer for first successful claim
    mock_call(
        REWARD_TOKEN_ADDRESS(),
        selector!("transfer"),
        array![1].span(),
        1
    );
    
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
    let player_felt: felt252 = player_address.into();
    mock_call(
        GAME_TOKEN_ADDRESS(),
        selector!("owner_of"),
        array![player_felt].span(),
        1
    );
    
    // Set contract reward token balance
    mock_call(
        REWARD_TOKEN_ADDRESS(),
        selector!("balance_of"),
        array![1000000000000000000000_u256.low.into(), 0].span(),
        1
    );
    
    // Set adventurer level to return error
    mock_call(
        ADVENTURER_SYSTEMS_ADDRESS(),
        selector!("get_adventurer_level"),
        array![1, 'INVALID_ADVENTURER'].span(), // 1 for DataResult::Err variant
        1
    );
    
    // This should panic
    start_cheat_caller_address(beast_mode_address, player_address);
    beast_mode.claim_reward_token(token_id);
    stop_cheat_caller_address(beast_mode_address);
}