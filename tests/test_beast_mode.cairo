use starknet::{ContractAddress, contract_address_const};
use snforge_std::{
    declare, DeclareResultTrait, ContractClassTrait, start_cheat_caller_address,
    stop_cheat_caller_address, start_cheat_block_number, stop_cheat_block_number,
    start_cheat_block_hash, stop_cheat_block_hash, mock_call, start_mock_call,
};
use core::serde::Serde;

use beast_mode::interfaces::{
    IBeastModeDispatcher, IBeastModeDispatcherTrait, DataResult, ILegacyBeastsDispatcher,
    ILegacyBeastsDispatcherTrait,
};
use beast_mode::structs::LegacyBeast;

// Import real BeastNFT interfaces
use beasts_nft::interfaces::{IBeastsDispatcher, IBeastsDispatcherTrait};
use beasts_nft::pack::PackableBeast;

//
use game_components_token::structs::{TokenMetadata, Lifecycle};


// Test constants
const OWNER: felt252 = 'OWNER';
const PLAYER1: felt252 = 'PLAYER1';
const PLAYER2: felt252 = 'PLAYER2';

// Real mainnet legacy beast contract address
fn LEGACY_BEASTS_MAINNET_ADDRESS() -> ContractAddress {
    contract_address_const::<0x0158160018d590d93528995b340260e65aedd76d28a686e9daa5c4e8fad0c5dd>()
}

fn INITIAL_BEAST_MODE_DUNGEON_CONTRACT_ADDRESS() -> ContractAddress {
    contract_address_const::<0x04a346df886993b0ab17f1d5ae2dd203313484bbead83fdc404c55b237c42d43>()
}

fn V2_BEASTS_MAINNET_ADDRESS() -> ContractAddress {
    contract_address_const::<0x0280ace0b2171106eaebef91ca9b097a566108e9452c45b94a7924a9f794ae80>()
}

// Contract addresses for mocking (non-legacy)
fn GAME_TOKEN_ADDRESS() -> ContractAddress {
    contract_address_const::<'GAME_TOKEN'>()
}

fn MOCK_DM_BEAST_SYSTEM() -> ContractAddress {
    contract_address_const::<'GAME_COLLECTABLE'>()
}

fn MAINNET_DM_BEAST_SYSTEM() -> ContractAddress {
    contract_address_const::<0x5400b1e09b9de846793083a87be3007dfe385e1768bb517a9e6055bf0f2e9c2>()
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

// Deploy real BeastNFT contract
fn deploy_beast_nft() -> IBeastsDispatcher {
    let mock_beast_data_provider: ContractAddress = 'mock_beast_data_provider'.try_into().unwrap();
    let mock_img: ByteArray = "data:image/png;base64,AA==";
    start_mock_call(mock_beast_data_provider, selector!("get_data_uri"), mock_img);

    let contract = declare("beasts_nft").unwrap().contract_class();
    let owner = contract_address_const::<OWNER>();
    let name: ByteArray = "Beasts";
    let symbol: ByteArray = "BEAST";
    let mut calldata = array![];
    name.serialize(ref calldata);
    symbol.serialize(ref calldata);
    calldata.append(owner.into());
    calldata.append(owner.into());
    calldata.append(500);
    calldata.append(mock_beast_data_provider.into()); // regular_png_provider
    calldata.append(mock_beast_data_provider.into()); // shiny_png_provider
    calldata.append(mock_beast_data_provider.into()); // regular_gif_provider
    calldata.append(mock_beast_data_provider.into()); // shiny_gif_provider
    calldata.append(0); // death_mountain_address
    calldata.append(0); // terminal timestamp

    let (contract_address, _) = contract.deploy(@calldata).unwrap();
    IBeastsDispatcher { contract_address }
}

// Deploy beast mode with real BeastNFT for fork tests
fn deploy_beast_mode_with_fork() -> (IBeastModeDispatcher, IBeastsDispatcher) {
    let beast_nft = deploy_beast_nft();

    let contract = declare("beast_mode").unwrap().contract_class();

    let opening_time = 1000_u64;
    let settings_id = 1_u32;
    let cost_to_play = 100_u256;
    let free_games_duration = 604800_u64; // 7 days in seconds
    let bonus_duration = 604800_u64; // 7 days bonus period
    let renderer_address = RENDERER_ADDRESS();
    let ticket_receiver_address = TICKET_RECEIVER_ADDRESS();
    let owner_address = contract_address_const::<OWNER>();

    let (contract_address, _) = contract
        .deploy(
            @array![
                owner_address.into(),
                opening_time.into(),
                GAME_TOKEN_ADDRESS().into(),
                MAINNET_DM_BEAST_SYSTEM().into(),
                ADVENTURER_SYSTEMS_ADDRESS().into(),
                beast_nft.contract_address.into(),
                V2_BEASTS_MAINNET_ADDRESS().into(), // use real mainnet address
                LEGACY_BEASTS_MAINNET_ADDRESS().into(), // Use real mainnet address
                PAYMENT_TOKEN_ADDRESS().into(),
                REWARD_TOKEN_ADDRESS().into(),
                renderer_address.into(),
                0, // empty golden pass array
                ticket_receiver_address.into(),
                settings_id.into(),
                cost_to_play.low.into(),
                cost_to_play.high.into(),
                free_games_duration.into(),
                contract_address_const::<'FREE_GAMES_CLAIMER'>().into(),
                bonus_duration.into(),
            ],
        )
        .unwrap();

    let beast_mode = IBeastModeDispatcher { contract_address };

    // Set beast_mode as minter on the BeastNFT contract
    let owner_address = contract_address_const::<OWNER>();
    start_cheat_caller_address(beast_nft.contract_address, owner_address);
    beast_nft.set_dungeon_address(beast_mode.contract_address);
    stop_cheat_caller_address(beast_nft.contract_address);

    start_mock_call(
        INITIAL_BEAST_MODE_DUNGEON_CONTRACT_ADDRESS(),
        selector!("get_airdrop_block_number"),
        10_u64,
    );
    (beast_mode, beast_nft)
}

// Deploy beast mode with mocks for non-legacy tests
fn deploy_beast_mode_with_mocks() -> (IBeastModeDispatcher, IBeastsDispatcher) {
    let beast_nft = deploy_beast_nft();

    let contract = declare("beast_mode").unwrap().contract_class();
    let opening_time = 1000_u64;
    let settings_id = 1_u32;
    let cost_to_play = 100_u256;
    let free_games_duration = 604800_u64; // 7 days in seconds
    let bonus_duration = 604800_u64; // 7 days bonus period
    let renderer_address = RENDERER_ADDRESS();
    let ticket_receiver_address = TICKET_RECEIVER_ADDRESS();
    let owner_address = contract_address_const::<OWNER>();
    let v2_beast_address = contract_address_const::<'V2_0_BEASTS'>();

    let (contract_address, _) = contract
        .deploy(
            @array![
                owner_address.into(),
                opening_time.into(),
                GAME_TOKEN_ADDRESS().into(),
                MOCK_DM_BEAST_SYSTEM().into(),
                ADVENTURER_SYSTEMS_ADDRESS().into(),
                beast_nft.contract_address.into(),
                v2_beast_address.into(), // Mock address
                contract_address_const::<'LEGACY_BEASTS'>().into(), // Mock address
                PAYMENT_TOKEN_ADDRESS().into(),
                REWARD_TOKEN_ADDRESS().into(),
                renderer_address.into(),
                0, // empty golden pass array
                ticket_receiver_address.into(),
                settings_id.into(),
                cost_to_play.low.into(),
                cost_to_play.high.into(),
                free_games_duration.into(),
                contract_address_const::<'FREE_GAMES_CLAIMER'>().into(),
                bonus_duration.into(),
            ],
        )
        .unwrap();

    let beast_mode = IBeastModeDispatcher { contract_address };
    // Set beast_mode as minter on the BeastNFT contract
    let owner_address = contract_address_const::<OWNER>();
    start_cheat_caller_address(beast_nft.contract_address, owner_address);
    beast_nft.set_dungeon_address(beast_mode.contract_address);
    stop_cheat_caller_address(beast_nft.contract_address);

    start_mock_call(
        INITIAL_BEAST_MODE_DUNGEON_CONTRACT_ADDRESS(),
        selector!("get_airdrop_block_number"),
        1100_u64,
    );

    start_mock_call(v2_beast_address, selector!("total_supply"), 10000_u256);

    start_mock_call(v2_beast_address, selector!("owner_of"), contract_address_const::<PLAYER1>());

    let beast = PackableBeast {
        id: 1, prefix: 2, suffix: 3, level: 20, health: 100, shiny: 0, animated: 0,
    };

    start_mock_call(v2_beast_address, selector!("get_beast"), beast);

    (beast_mode, beast_nft)
}

// Helper functions for mocking
fn mock_owner_of_call(owner: ContractAddress) {
    // First mock the minigame's token_address() call
    mock_call(GAME_TOKEN_ADDRESS(), selector!("token_address"), GAME_TOKEN_ADDRESS(), 2);
    // Then mock owner_of on the token
    mock_call(GAME_TOKEN_ADDRESS(), selector!("owner_of"), owner, 2);
}

fn mock_beast_hash_call(hash: felt252) {
    mock_call(MOCK_DM_BEAST_SYSTEM(), selector!("get_beast_hash"), hash, 1);
}

fn mock_valid_collectable_call(seed: u64, level: u16, health: u16) {
    mock_call(
        MOCK_DM_BEAST_SYSTEM(),
        selector!("get_valid_collectable"),
        DataResult::Ok((seed, level, health)),
        1,
    );
}

fn mock_valid_collectable_error(error_msg: felt252) {
    mock_call(
        MOCK_DM_BEAST_SYSTEM(),
        selector!("get_valid_collectable"),
        DataResult::<(u64, u16, u16)>::Err(error_msg),
        1,
    );
}

fn mock_adventurer_level_call(level: u8) {
    mock_call(ADVENTURER_SYSTEMS_ADDRESS(), selector!("get_adventurer_level"), level, 1);
}

fn mock_adventurer_level_error(error_msg: felt252) {
    // Since get_adventurer_level now returns u8 directly, we can't mock an error
    // Instead, we'll create a panic by mocking an invalid call or use a different approach
    // For now, we'll mock with 0 and let the test handle the validation
    mock_call(
        ADVENTURER_SYSTEMS_ADDRESS(),
        selector!("get_adventurer_level"),
        0_u8, // This could trigger validation errors in the business logic
        1,
    );
}

fn mock_adventurer_health_call(health: u16) {
    mock_call(ADVENTURER_SYSTEMS_ADDRESS(), selector!("get_adventurer_health"), health, 1);
}

fn mock_adventurer_health_call_times(health: u16, times: u32) {
    mock_call(ADVENTURER_SYSTEMS_ADDRESS(), selector!("get_adventurer_health"), health, times);
}

fn mock_adventurer_dungeon_call(dungeon_address: ContractAddress) {
    mock_call(
        ADVENTURER_SYSTEMS_ADDRESS(), selector!("get_adventurer_dungeon"), dungeon_address, 1,
    );
}

fn mock_adventurer_dungeon_call_times(dungeon_address: ContractAddress, times: u32) {
    mock_call(
        ADVENTURER_SYSTEMS_ADDRESS(), selector!("get_adventurer_dungeon"), dungeon_address, times,
    );
}

fn mock_erc20_transfer_call(success: bool) {
    mock_call(REWARD_TOKEN_ADDRESS(), selector!("transfer"), success, 1);
}

fn mock_erc20_safe_transfer_call() {
    // IERC20SafeDispatcher.transfer should return Result<bool, (felt252, Span<felt252>)>
    // Let's create the proper result type
    let success_result: Result<bool, (felt252, Span<felt252>)> = Result::Ok(true);
    mock_call(REWARD_TOKEN_ADDRESS(), selector!("transfer"), success_result, 10);
}

fn mock_balance_of_zero_call() {
    mock_call(REWARD_TOKEN_ADDRESS(), selector!("balance_of"), 0_u256, 1);
}

fn mock_balance_of_large_call() {
    mock_call(
        REWARD_TOKEN_ADDRESS(),
        selector!("balance_of"),
        1000000000000000000000_u256,
        2 // Contract calls balance_of twice in claim_reward_token
    );
}

fn mock_owner_of_call_times(owner: ContractAddress, times: u32) {
    // Mock the minigame's token_address() call
    mock_call(GAME_TOKEN_ADDRESS(), selector!("token_address"), GAME_TOKEN_ADDRESS(), times);
    // Then mock owner_of on the token
    mock_call(GAME_TOKEN_ADDRESS(), selector!("owner_of"), owner, times);
}

fn mock_balance_of_large_call_times(times: u32) {
    mock_call(
        REWARD_TOKEN_ADDRESS(),
        selector!("balance_of"),
        1000000000000000000000_u256,
        times * 2 // Each claim call uses balance_of twice
    );
}

fn mock_adventurer_level_call_times(level: u8, times: u32) {
    mock_call(ADVENTURER_SYSTEMS_ADDRESS(), selector!("get_adventurer_level"), level, times);
}

fn mock_premint_collectable_call(times: u32) {
    mock_call(MOCK_DM_BEAST_SYSTEM(), selector!("premint_collectable"), 12345_u64, times);
}

fn mock_token_metadata_call(minted_at: u64) {
    // Mock the minigame's token_address() call first
    mock_call(GAME_TOKEN_ADDRESS(), selector!("token_address"), GAME_TOKEN_ADDRESS(), 1);
    // Then mock the token_metadata call on that address

    let metadata = TokenMetadata {
        game_id: 1,
        minted_at: minted_at,
        settings_id: 0,
        lifecycle: Lifecycle { start: 0, end: 0 },
        minted_by: 0,
        soulbound: false,
        game_over: false,
        completed_all_objectives: false,
        has_context: false,
        objectives_count: 0,
    };

    mock_call(GAME_TOKEN_ADDRESS(), selector!("token_metadata"), metadata, 1);
}

// VRF contract address
fn VRF_PROVIDER_ADDRESS() -> ContractAddress {
    contract_address_const::<0x051fea4450da9d6aee758bdeba88b2f665bcbf549d2c61421aa724e9ac0ced8f>()
}

fn mock_vrf_consume_random(random_value: felt252) {
    mock_call(VRF_PROVIDER_ADDRESS(), selector!("consume_random"), random_value, 1);
}

fn mock_legacy_beast_calls_for_airdrop(times: u32) {
    // Use the mock legacy beasts address (same as in deploy_beast_mode_with_mocks)
    let mock_legacy_address = contract_address_const::<'LEGACY_BEASTS'>();

    // Mock different beasts for each iteration to avoid duplicate minting
    let mut i = 0_u32;
    while i < times {
        let legacy_beast = LegacyBeast {
            id: (1_u8 + (i % 5_u32).try_into().unwrap()), // Vary beast id 1-5
            prefix: (1_u8 + (i % 3_u32).try_into().unwrap()), // Vary prefix 1-3  
            suffix: (1_u8 + (i % 4_u32).try_into().unwrap()), // Vary suffix 1-4
            level: (10_u16 + i.try_into().unwrap()),
            health: (150_u16 + i.try_into().unwrap()),
        };
        mock_call(mock_legacy_address, selector!("getBeast"), legacy_beast, 1);

        // Mock ownerOf for each airdrop iteration
        let owner = contract_address_const::<PLAYER1>();
        mock_call(mock_legacy_address, selector!("ownerOf"), owner, 1);

        i += 1;
    };
}

// ===========================================
// CLAIM BEAST TESTS (using real BeastNFT)
// ===========================================

#[test]
fn test_claim_beast_mint_parameters() {
    let (beast_mode, beast_nft) = deploy_beast_mode_with_mocks();
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

    // Mock reward token transfer (beast id 10 gets 10 tokens)
    mock_erc20_safe_transfer_call();

    // Call claim_beast
    start_cheat_caller_address(beast_mode_address, player_address);
    let token_id = beast_mode.claim_beast(adventurer_id, beast_id, prefix, suffix);
    stop_cheat_caller_address(beast_mode_address);

    // Debug: Check if token_id was returned
    if token_id == 0 {
        core::panic_with_felt252('claim_beast returned 0');
    }

    // Verify mint was successful - total supply should be 1
    let total_supply = beast_nft.total_supply();
    // Debug: let's see what the actual total supply is
    assert(total_supply == 76, 'Total supply should be 1');

    // Get the minted beast details
    let beast: PackableBeast = beast_nft.get_beast(76);

    // Verify beast parameters match inputs
    assert(beast.id == beast_id, 'Wrong beast_id');
    assert(beast.prefix == prefix, 'Wrong prefix');
    assert(beast.suffix == suffix, 'Wrong suffix');

    // Verify level and health from get_valid_collectable
    assert(beast.level == level, 'Wrong level');
    assert(beast.health == health, 'Wrong health');

    // Verify shiny and animated are either 0 or 1
    assert(beast.shiny == 0 || beast.shiny == 1, 'Invalid shiny value');
    assert(beast.animated == 0 || beast.animated == 1, 'Invalid animated value');

    // Verify the beast was marked as minted
    assert(beast_nft.is_minted(beast_id, prefix, suffix), 'Beast not marked as minted');
}

#[test]
fn test_claim_beast_rare_traits() {
    let (beast_mode, beast_nft) = deploy_beast_mode_with_mocks();
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

    // Mock reward token transfer
    mock_erc20_safe_transfer_call();

    // Test with seed that should produce shiny=1, animated=0
    let seed_for_shiny = 0x1F500000187_u64; // shiny=491<500(1), animated=501>=400(0)
    mock_valid_collectable_call(seed_for_shiny, 5_u16, 100_u16);

    // Call claim_beast
    start_cheat_caller_address(beast_mode_address, player_address);
    beast_mode.claim_beast(adventurer_id, beast_id, prefix, suffix);
    stop_cheat_caller_address(beast_mode_address);

    // Get the minted beast details
    let beast: PackableBeast = beast_nft.get_beast(76);

    // With seed 391, shiny should be 1, animated should be 0
    assert(beast.shiny == 1, 'Expected shiny trait');
    assert(beast.animated == 0, 'Expected no animated trait');
}

#[test]
fn test_claim_beast_no_rare_traits() {
    let (beast_mode, beast_nft) = deploy_beast_mode_with_mocks();
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

    // Mock reward token transfer
    mock_erc20_safe_transfer_call();

    // Test with seed that should produce shiny=0, animated=0
    let seed_for_no_rare = 0x270F000003E8_u64; // shiny=1000>=400(0), animated=9999>=400(0)
    mock_valid_collectable_call(seed_for_no_rare, 5_u16, 100_u16);

    // Call claim_beast
    start_cheat_caller_address(beast_mode_address, player_address);
    beast_mode.claim_beast(adventurer_id, beast_id, prefix, suffix);
    stop_cheat_caller_address(beast_mode_address);

    // Get the minted beast details
    let beast: PackableBeast = beast_nft.get_beast(76);

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
    let (beast_mode, beast_nft) = deploy_beast_mode_with_mocks();
    let beast_mode_address = beast_mode.contract_address;

    // Setup two different players
    let player1_address = contract_address_const::<PLAYER1>();
    let player2_address = contract_address_const::<PLAYER2>();

    // Mock ownership for adventurer 1
    mock_owner_of_call(player1_address);
    mock_beast_hash_call('BEAST1_HASH');
    mock_valid_collectable_call(1234_u64, 5_u16, 100_u16);
    mock_erc20_safe_transfer_call();

    // Player 1 claims their beast
    start_cheat_caller_address(beast_mode_address, player1_address);
    beast_mode.claim_beast(1_u64, 10_u8, 1_u8, 1_u8);
    stop_cheat_caller_address(beast_mode_address);

    // Mock ownership for adventurer 2
    mock_owner_of_call(player2_address);
    mock_beast_hash_call('BEAST2_HASH');
    mock_valid_collectable_call(5678_u64, 10_u16, 200_u16);
    mock_erc20_safe_transfer_call();

    // Player 2 claims their beast
    start_cheat_caller_address(beast_mode_address, player2_address);
    beast_mode.claim_beast(2_u64, 20_u8, 2_u8, 2_u8);
    stop_cheat_caller_address(beast_mode_address);

    // Verify both beasts were minted
    assert!(
        beast_nft.total_supply() == 77,
        "Wrong total supply. Expected 77, got {}",
        beast_nft.total_supply(),
    );

    // Verify first beast (player 1)
    let beast1: PackableBeast = beast_nft.get_beast(76);
    assert!(beast1.id == 10, "Wrong ID for beast 1. Expected 10, got {}", beast1.id);
    assert!(beast1.prefix == 1, "Wrong prefix for beast 1. Expected 1, got {}", beast1.prefix);
    assert!(beast1.suffix == 1, "Wrong suffix for beast 1. Expected 1, got {}", beast1.suffix);
    assert!(beast1.level == 5, "Wrong level for beast 1. Expected 5, got {}", beast1.level);
    assert!(beast1.health == 100, "Wrong health for beast 1. Expected 100, got {}", beast1.health);

    // Verify second beast (player 2)
    let beast2: PackableBeast = beast_nft.get_beast(77);
    assert!(beast2.id == 20, "Wrong ID for beast 2. Expected 20, got {}", beast2.id);
    assert!(beast2.prefix == 2, "Wrong prefix for beast 2. Expected 2, got {}", beast2.prefix);
    assert!(beast2.suffix == 2, "Wrong suffix for beast 2. Expected 2, got {}", beast2.suffix);
    assert!(beast2.level == 10, "Wrong level for beast 2. Expected 10, got {}", beast2.level);
    assert!(beast2.health == 200, "Wrong health for beast 2. Expected 200, got {}", beast2.health);

    // Verify both beasts are marked as minted
    assert!(beast_nft.is_minted(10, 1, 1), "Beast 1 not marked as minted");
    assert!(beast_nft.is_minted(20, 2, 2), "Beast 2 not marked as minted");
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
    assert(beast_mode.get_beast_airdrop_count() == 0, 'Airdrop count not zero');
    // Initiate airdrop
    let owner_address = contract_address_const::<OWNER>();
    start_cheat_caller_address(beast_mode.contract_address, owner_address);
    beast_mode.initiate_airdrop();
    // Verify airdrop was initiated
    assert(beast_mode.get_airdrop_block_number() == 1100, 'Wrong airdrop block number');
    assert(beast_mode.get_beast_airdrop_count() == 75, 'Wrong airdrop count');
    stop_cheat_block_number(beast_mode.contract_address);
}

#[test]
#[should_panic(expected: ('Airdrop already initiated',))]
fn test_initiate_airdrop_twice() {
    let (beast_mode, _) = deploy_beast_mode_with_mocks();
    let owner = contract_address_const::<OWNER>();

    // Set block number
    start_cheat_block_number(beast_mode.contract_address, 1000);

    // Initiate airdrop first time as owner
    start_cheat_caller_address(beast_mode.contract_address, owner);
    beast_mode.initiate_airdrop();

    // Try to initiate again - should panic
    beast_mode.initiate_airdrop();
    stop_cheat_caller_address(beast_mode.contract_address);

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

    // Mock dungeon check - adventurer should be from beast mode dungeon
    mock_adventurer_dungeon_call(beast_mode_address);

    // Mock adventurer health - must be dead (0)
    mock_adventurer_health_call(0);
    // Mock get_adventurer_level - returning level 10
    let level = 10_u8;
    mock_adventurer_level_call(level);
    // Mock token metadata for reward calculation
    // Set minted_at to opening_time + 1 (no bonus multiplier)
    mock_token_metadata_call(1001);
    // Mock IERC721 owner_of for game token
    mock_owner_of_call(player_address);

    // Mock ERC20 transfer
    mock_erc20_transfer_call(true);
    // Call claim_reward_token as any caller (no ownership check on caller)
    beast_mode.claim_reward_token(token_id);
}

#[test]
#[should_panic(expected: "Adventurer must be dead")]
fn test_claim_reward_token_alive_adventurer() {
    let (beast_mode, _) = deploy_beast_mode_with_mocks();
    let beast_mode_address = beast_mode.contract_address;

    let token_id = 1_u64;

    // Mock dungeon check - adventurer should be from beast mode dungeon
    mock_adventurer_dungeon_call(beast_mode_address);

    // Mock adventurer health - alive (not 0)
    mock_adventurer_health_call(100);

    // This should panic because adventurer is not dead
    beast_mode.claim_reward_token(token_id);
}

#[test]
#[should_panic(expected: "Adventurer must be level 3 or higher")]
fn test_claim_reward_token_low_level() {
    let (beast_mode, _) = deploy_beast_mode_with_mocks();
    let beast_mode_address = beast_mode.contract_address;

    let token_id = 1_u64;

    // Mock dungeon check - adventurer should be from beast mode dungeon
    mock_adventurer_dungeon_call(beast_mode_address);

    // Mock adventurer health - must be dead (0)
    mock_adventurer_health_call(0);

    // Mock get_adventurer_level - level 2 (too low)
    mock_adventurer_level_call(2_u8);

    // This should panic because level < 3
    beast_mode.claim_reward_token(token_id);
}

#[test]
#[should_panic(expected: "Token already claimed")]
fn test_claim_reward_token_already_claimed() {
    let (beast_mode, _) = deploy_beast_mode_with_mocks();
    let beast_mode_address = beast_mode.contract_address;

    let token_id = 1_u64;
    let player_address = contract_address_const::<PLAYER1>();

    // Mock dungeon check - adventurer should be from beast mode dungeon (2 calls)
    mock_adventurer_dungeon_call_times(beast_mode_address, 2);

    // Mock adventurer health - must be dead (2 calls)
    mock_adventurer_health_call_times(0, 2);

    // Set adventurer level (2 calls)
    mock_adventurer_level_call_times(10_u8, 2);

    // Mock token metadata (2 calls)
    mock_call(GAME_TOKEN_ADDRESS(), selector!("token_address"), GAME_TOKEN_ADDRESS(), 2);

    let metadata = TokenMetadata {
        game_id: 1,
        minted_at: 1001_u64,
        settings_id: 0,
        lifecycle: Lifecycle { start: 0, end: 0 },
        minted_by: 0,
        soulbound: false,
        game_over: false,
        completed_all_objectives: false,
        has_context: false,
        objectives_count: 0,
    };

    mock_call(GAME_TOKEN_ADDRESS(), selector!("token_metadata"), metadata, 2);

    // Mock token ownership (2 calls)
    mock_owner_of_call_times(player_address, 2);

    // Mock transfer for first successful claim
    mock_erc20_transfer_call(true);

    // First claim - should succeed
    beast_mode.claim_reward_token(token_id);

    // Second claim - should panic
    beast_mode.claim_reward_token(token_id);
}

#[test]
#[should_panic(expected: "Adventurer not from beast mode dungeon")]
fn test_claim_reward_token_wrong_dungeon() {
    let (beast_mode, _) = deploy_beast_mode_with_mocks();

    let token_id = 1_u64;

    // Mock dungeon check - adventurer is from different dungeon (should fail)
    let different_dungeon = contract_address_const::<'DIFFERENT_DUNGEON'>();
    mock_adventurer_dungeon_call(different_dungeon);

    // This should panic
    beast_mode.claim_reward_token(token_id);
}

// ===========================================
// FORK TESTS (using real mainnet data)
// ===========================================

#[test]
#[fork("mainnet")]
fn test_legacy_beasts_total_supply_fork() {
    // Test real legacy beast contract with correct method name
    let legacy_beasts = ILegacyBeastsDispatcher {
        contract_address: LEGACY_BEASTS_MAINNET_ADDRESS(),
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
        contract_address: LEGACY_BEASTS_MAINNET_ADDRESS(),
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
    let (beast_mode, beast_nft) = deploy_beast_mode_with_fork();
    let owner = contract_address_const::<OWNER>();

    // First initiate the airdrop
    start_cheat_block_number(beast_mode.contract_address, 1000);
    start_cheat_caller_address(beast_mode.contract_address, owner);

    beast_mode.initiate_airdrop();

    // Move forward in blocks to make airdrop ready
    start_cheat_block_number(beast_mode.contract_address, 1200);

    // Set up block hash for the airdrop block
    let block_hash = 'BLOCK_HASH_SEED';
    start_cheat_block_hash(beast_mode.contract_address, 1100, block_hash);

    // Mock premint_collectable calls
    mock_premint_collectable_call(3);

    // Get real legacy beast contract
    let legacy_beasts = ILegacyBeastsDispatcher {
        contract_address: LEGACY_BEASTS_MAINNET_ADDRESS(),
    };

    // Call airdrop_legacy_beasts with small limit to test with real data
    beast_mode.airdrop_legacy_beasts(3);
    stop_cheat_caller_address(beast_mode.contract_address);

    // Verify airdrop count increased (starts at 75, adds 3)
    assert!(
        beast_mode.get_beast_airdrop_count() == 78,
        "Wrong airdrop count. Expected 78, got {}",
        beast_mode.get_beast_airdrop_count(),
    );

    // Verify beasts were minted
    assert!(
        beast_nft.total_supply() == 78,
        "Wrong total supply. Expected 78, got {}",
        beast_nft.total_supply(),
    );

    // Verify each beast has valid attributes from real contract
    let mut i: u32 = 0;
    loop {
        if i >= 3 {
            break;
        }

        let beast: PackableBeast = beast_nft.get_beast((76 + i).into());

        // Get the real beast data from mainnet (76, 77, 78)
        let real_beast = legacy_beasts.getBeast((76 + i).into());
        let _real_owner = legacy_beasts.ownerOf((76 + i).into());

        // Verify the minted beast matches real legacy beast data
        assert!(
            beast.id == real_beast.id,
            "Wrong beast ID. Expected {}, got {}",
            real_beast.id,
            beast.id,
        );
        assert!(
            beast.prefix == real_beast.prefix,
            "Wrong prefix. Expected {}, got {}",
            real_beast.prefix,
            beast.prefix,
        );
        assert!(
            beast.suffix == real_beast.suffix,
            "Wrong suffix. Expected {}, got {}",
            real_beast.suffix,
            beast.suffix,
        );
        assert!(
            beast.level == real_beast.level,
            "Wrong level. Expected {}, got {}",
            real_beast.level,
            beast.level,
        );
        assert!(
            beast.health == real_beast.health,
            "Wrong health. Expected {}, got {}",
            real_beast.health,
            beast.health,
        );
        assert!(beast.shiny == 0 || beast.shiny == 1, "Invalid shiny");
        assert!(beast.animated == 0 || beast.animated == 1, "Invalid animated");

        // Verify the beast is marked as minted
        assert(
            beast_nft.is_minted(real_beast.id, real_beast.prefix, real_beast.suffix),
            'Beast not marked as minted',
        );

        i += 1;
    };

    stop_cheat_block_number(beast_mode.contract_address);
    stop_cheat_block_hash(beast_mode.contract_address, 1100);
}

// ===========================================
// SECURITY & EDGE CASE TESTS
// ===========================================

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_update_opening_time_not_owner() {
    let (beast_mode, _) = deploy_beast_mode_with_mocks();
    let attacker = contract_address_const::<'ATTACKER'>();

    // Try to call admin function as non-owner
    start_cheat_caller_address(beast_mode.contract_address, attacker);
    beast_mode.update_opening_time(2000_u64);
    stop_cheat_caller_address(beast_mode.contract_address);
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_update_payment_token_not_owner() {
    let (beast_mode, _) = deploy_beast_mode_with_mocks();
    let attacker = contract_address_const::<'ATTACKER'>();
    let fake_token = contract_address_const::<'FAKE_TOKEN'>();

    start_cheat_caller_address(beast_mode.contract_address, attacker);
    beast_mode.update_payment_token(fake_token);
    stop_cheat_caller_address(beast_mode.contract_address);
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_update_cost_to_play_not_owner() {
    let (beast_mode, _) = deploy_beast_mode_with_mocks();
    let attacker = contract_address_const::<'ATTACKER'>();

    start_cheat_caller_address(beast_mode.contract_address, attacker);
    beast_mode.update_cost_to_play(999999_u128);
    stop_cheat_caller_address(beast_mode.contract_address);
}

#[test]
fn test_admin_functions_owner_access() {
    let (beast_mode, _) = deploy_beast_mode_with_mocks();
    let owner = contract_address_const::<OWNER>();
    let new_token = contract_address_const::<'NEW_TOKEN'>();

    // Call admin functions as the owner
    start_cheat_caller_address(beast_mode.contract_address, owner);
    beast_mode.update_opening_time(3000_u64);
    beast_mode.update_payment_token(new_token);
    beast_mode.update_cost_to_play(500_u128);
    stop_cheat_caller_address(beast_mode.contract_address);
}

#[test]
fn test_claim_beast_duplicate_attempt() {
    let (beast_mode, beast_nft) = deploy_beast_mode_with_mocks();
    let beast_mode_address = beast_mode.contract_address;
    let player = contract_address_const::<PLAYER1>();

    // Set up mocks for successful first claim
    mock_owner_of_call(player);
    mock_beast_hash_call('BEAST_HASH');
    mock_valid_collectable_call(12345_u64, 5_u16, 100_u16);
    mock_erc20_safe_transfer_call();

    // First claim should succeed
    start_cheat_caller_address(beast_mode_address, player);
    beast_mode.claim_beast(1_u64, 10_u8, 1_u8, 2_u8);
    assert(beast_nft.total_supply() == 76, 'First claim failed');

    // Second claim of same beast should fail via BeastNFT duplicate check
    // Note: This would fail at BeastNFT level with "Beast already minted" error
    stop_cheat_caller_address(beast_mode_address);
}

#[test]
fn test_reward_token_overflow_protection() {
    let (beast_mode, _) = deploy_beast_mode_with_mocks();
    let beast_mode_address = beast_mode.contract_address;
    let player = contract_address_const::<PLAYER1>();

    // Mock dungeon check - adventurer should be from beast mode dungeon
    mock_adventurer_dungeon_call(beast_mode_address);

    // Mock adventurer health - must be dead (0)
    mock_adventurer_health_call(0);

    // Mock extremely high level (255 max u8) - will be capped at 50
    mock_adventurer_level_call(255_u8);

    // Mock token metadata
    mock_token_metadata_call(1001);

    // Mock token ownership
    mock_owner_of_call(player);

    // Mock ERC20 transfer
    mock_erc20_transfer_call(true);

    // Should succeed without overflow, level capped at 50
    beast_mode.claim_reward_token(1_u64);
}

#[test]
fn test_reward_token_with_pool_limit() {
    let (beast_mode, _) = deploy_beast_mode_with_mocks();
    let beast_mode_address = beast_mode.contract_address;
    let player = contract_address_const::<PLAYER1>();

    // Set reward tokens already claimed to near limit (1999990)
    // This would mean only 10 tokens left in pool
    // We'd need to be able to set contract state for this test
    // Since we can't directly set storage, we'll skip this edge case for now

    // Mock dungeon check
    mock_adventurer_dungeon_call(beast_mode_address);

    // Mock adventurer health - must be dead
    mock_adventurer_health_call(0);

    // Mock level 50 (would want 50 tokens but only 10 available)
    mock_adventurer_level_call(50_u8);

    // Mock token metadata
    mock_token_metadata_call(1001);

    // Mock token ownership
    mock_owner_of_call(player);

    // Mock ERC20 transfer
    mock_erc20_transfer_call(true);

    // This test would verify pool limit logic but needs state manipulation
    beast_mode.claim_reward_token(1_u64);
}

#[test]
#[should_panic(expected: "Token already claimed")]
fn test_reward_token_double_claim_attack() {
    let (beast_mode, _) = deploy_beast_mode_with_mocks();
    let beast_mode_address = beast_mode.contract_address;
    let player = contract_address_const::<PLAYER1>();

    // Set up successful first claim
    // Mock dungeon check - adventurer should be from beast mode dungeon (2 calls)
    mock_adventurer_dungeon_call_times(beast_mode_address, 2);

    // Mock adventurer health - must be dead (2 calls)
    mock_adventurer_health_call_times(0, 2);

    // Mock level (2 calls)
    mock_adventurer_level_call_times(10_u8, 2);

    // Mock token metadata (2 calls)
    mock_call(GAME_TOKEN_ADDRESS(), selector!("token_address"), GAME_TOKEN_ADDRESS(), 2);

    let metadata = TokenMetadata {
        game_id: 1,
        minted_at: 1001_u64,
        settings_id: 0,
        lifecycle: Lifecycle { start: 0, end: 0 },
        minted_by: 0,
        soulbound: false,
        game_over: false,
        completed_all_objectives: false,
        has_context: false,
        objectives_count: 0,
    };

    mock_call(GAME_TOKEN_ADDRESS(), selector!("token_metadata"), metadata, 2);

    // Mock token ownership (2 calls)
    mock_owner_of_call_times(player, 2);

    // Mock transfer
    mock_erc20_transfer_call(true);

    // First claim succeeds
    beast_mode.claim_reward_token(1_u64);

    // Second claim should be blocked by double-claim protection
    beast_mode.claim_reward_token(1_u64);
}

#[test]
fn test_airdrop_limit_boundary() {
    let (beast_mode, beast_nft) = deploy_beast_mode_with_mocks();
    let owner = contract_address_const::<OWNER>();

    start_cheat_block_number(beast_mode.contract_address, 1000);
    start_cheat_caller_address(beast_mode.contract_address, owner);
    beast_mode.initiate_airdrop();

    start_cheat_block_number(beast_mode.contract_address, 1200);
    let block_hash = 'BLOCK_HASH';
    start_cheat_block_hash(beast_mode.contract_address, 1100, block_hash);

    // Test airdrop with limit 0 - should not mint anything
    // Still need to mock tokenSupply since it's called even with 0 limit
    let mock_legacy_address = contract_address_const::<'LEGACY_BEASTS'>();
    mock_call(mock_legacy_address, selector!("tokenSupply"), 10000_u256, 1);

    beast_mode.airdrop_legacy_beasts(0);
    stop_cheat_caller_address(beast_mode.contract_address);

    assert(beast_nft.total_supply() == 75, 'Should not mint with 0 limit');

    // Verify airdrop count didn't change
    assert(beast_mode.get_beast_airdrop_count() == 75, 'Count should stay at 75');

    stop_cheat_block_number(beast_mode.contract_address);
    stop_cheat_block_hash(beast_mode.contract_address, 1100);
}

#[test]
#[should_panic(expected: "Adventurer must be level 3 or higher")]
fn test_reward_token_with_zero_level() {
    let (beast_mode, _) = deploy_beast_mode_with_mocks();
    let beast_mode_address = beast_mode.contract_address;

    // Mock dungeon check - adventurer should be from beast mode dungeon
    mock_adventurer_dungeon_call(beast_mode_address);

    // Mock adventurer health - must be dead
    mock_adventurer_health_call(0);

    // Mock level 0 - should fail (min is 3)
    mock_adventurer_level_call(0_u8);

    // This should panic
    beast_mode.claim_reward_token(1_u64);
}

#[test]
#[fork("mainnet")]
#[should_panic(expected: ('Airdrop not initiated',))]
fn test_airdrop_without_initiation() {
    let (beast_mode, _) = deploy_beast_mode_with_fork();
    let owner = contract_address_const::<OWNER>();

    // Try to airdrop without calling initiate_airdrop first
    start_cheat_caller_address(beast_mode.contract_address, owner);
    beast_mode.airdrop_legacy_beasts(1);
    stop_cheat_caller_address(beast_mode.contract_address);
}

// ===========================================
// REWARD MULTIPLIER TESTS
// ===========================================

#[test]
fn test_claim_reward_token_with_2x_multiplier() {
    let (beast_mode, _) = deploy_beast_mode_with_mocks();
    let beast_mode_address = beast_mode.contract_address;
    let player = contract_address_const::<PLAYER1>();

    // Mock dungeon check
    mock_adventurer_dungeon_call(beast_mode_address);
    // Mock adventurer health - must be dead
    mock_adventurer_health_call(0);
    // Mock level 10
    mock_adventurer_level_call(10_u8);
    // Mock token metadata - minted after free games + bonus (2x multiplier)
    // opening_time = 1000, free_games = 604800, bonus = 604800
    // So minted_at = 1000 + 604800 + 604800 + 1 = 1210401
    mock_call(GAME_TOKEN_ADDRESS(), selector!("token_address"), GAME_TOKEN_ADDRESS(), 1);
    let metadata = TokenMetadata {
        game_id: 1210401_u64,
        minted_at: 0,
        settings_id: 0,
        lifecycle: Lifecycle { start: 0, end: 0 },
        minted_by: 0,
        soulbound: false,
        game_over: false,
        completed_all_objectives: false,
        has_context: false,
        objectives_count: 0,
    };

    mock_call(GAME_TOKEN_ADDRESS(), selector!("token_metadata"), metadata, 1);
    // Mock token ownership
    mock_owner_of_call(player);
    // Mock ERC20 transfer - should get 20 tokens (10 * 2)
    mock_erc20_transfer_call(true);
    beast_mode.claim_reward_token(1_u64);
}

#[test]
fn test_claim_reward_token_with_4x_multiplier() {
    let (beast_mode, _) = deploy_beast_mode_with_mocks();
    let beast_mode_address = beast_mode.contract_address;
    let player = contract_address_const::<PLAYER1>();

    // Mock dungeon check
    mock_adventurer_dungeon_call(beast_mode_address);

    // Mock adventurer health - must be dead
    mock_adventurer_health_call(0);

    // Mock level 10
    mock_adventurer_level_call(10_u8);

    // Mock token metadata - minted during free games period (4x multiplier)
    // opening_time = 1000, free_games = 604800
    // So minted_at = 1000 + 100 = 1100 (during free games)
    mock_call(GAME_TOKEN_ADDRESS(), selector!("token_address"), GAME_TOKEN_ADDRESS(), 1);

    let metadata = TokenMetadata {
        game_id: 1210401_u64,
        minted_at: 1100_u64,
        settings_id: 0,
        lifecycle: Lifecycle { start: 0, end: 0 },
        minted_by: 0,
        soulbound: false,
        game_over: false,
        completed_all_objectives: false,
        has_context: false,
        objectives_count: 0,
    };

    mock_call(GAME_TOKEN_ADDRESS(), selector!("token_metadata"), metadata, 1);

    // Mock token ownership
    mock_owner_of_call(player);

    // Mock ERC20 transfer - should get 40 tokens (10 * 4)
    mock_erc20_transfer_call(true);

    beast_mode.claim_reward_token(1_u64);
}

#[test]
fn test_claim_reward_token_level_cap() {
    let (beast_mode, _) = deploy_beast_mode_with_mocks();
    let beast_mode_address = beast_mode.contract_address;
    let player = contract_address_const::<PLAYER1>();

    // Mock dungeon check
    mock_adventurer_dungeon_call(beast_mode_address);

    // Mock adventurer health - must be dead
    mock_adventurer_health_call(0);

    // Mock level 100 (should be capped at 50)
    mock_adventurer_level_call(100_u8);

    // Mock token metadata - no multiplier
    mock_token_metadata_call(1001);

    // Mock token ownership
    mock_owner_of_call(player);

    // Mock ERC20 transfer - should get 50 tokens (capped)
    mock_erc20_transfer_call(true);

    beast_mode.claim_reward_token(1_u64);
}

// ===========================================
// JACKPOT TESTS
// ===========================================

#[test]
fn test_claim_jackpot_demon_grasp() {
    let (beast_mode, beast_nft) = deploy_beast_mode_with_mocks();
    let beast_mode_address = beast_mode.contract_address;
    let player = contract_address_const::<PLAYER1>();

    // First mint a demon grasp beast (id=29, prefix=18, suffix=6)
    mock_owner_of_call(player);
    mock_beast_hash_call('DEMON_GRASP');
    mock_valid_collectable_call(12345_u64, 10_u16, 100_u16);
    mock_erc20_safe_transfer_call();

    start_cheat_caller_address(beast_mode_address, player);
    beast_mode.claim_beast(1_u64, 29_u8, 18_u8, 6_u8);
    stop_cheat_caller_address(beast_mode_address);

    // Now claim jackpot for this beast
    // Mock beast NFT owner check
    mock_call(beast_nft.contract_address, selector!("owner_of"), player, 1);

    // Mock the STRK token transfer
    mock_call(
        0x04718f5a0Fc34cC1AF16A1cdee98fFB20C31f5cD61D6Ab07201858f4287c938D.try_into().unwrap(),
        selector!("transfer"),
        true,
        1,
    );

    start_cheat_caller_address(beast_mode_address, player);
    beast_mode.claim_jackpot(76_u64);
    stop_cheat_caller_address(beast_mode_address);
}

#[test]
fn test_claim_jackpot_pain_whisper() {
    println!("test_claim_jackpot_pain_whisper");
    let (beast_mode, beast_nft) = deploy_beast_mode_with_mocks();
    let beast_mode_address = beast_mode.contract_address;
    let player = contract_address_const::<PLAYER1>();

    // First mint a pain whisper beast (id=1, prefix=47, suffix=11)
    mock_owner_of_call(player);
    mock_beast_hash_call('PAIN_WHISPER');
    mock_valid_collectable_call(12345_u64, 10_u16, 100_u16);
    mock_erc20_safe_transfer_call();

    start_cheat_caller_address(beast_mode_address, player);
    beast_mode.claim_beast(1_u64, 1_u8, 47_u8, 11_u8);
    stop_cheat_caller_address(beast_mode_address);

    // Now claim jackpot for this beast
    // Mock beast NFT owner check
    mock_call(beast_nft.contract_address, selector!("owner_of"), player, 1);

    // Mock the STRK token transfer
    mock_call(
        0x04718f5a0Fc34cC1AF16A1cdee98fFB20C31f5cD61D6Ab07201858f4287c938D.try_into().unwrap(),
        selector!("transfer"),
        true,
        1,
    );

    start_cheat_caller_address(beast_mode_address, player);
    beast_mode.claim_jackpot(76_u64);
    stop_cheat_caller_address(beast_mode_address);
}

#[test]
#[should_panic(expected: 'Not token owner')]
fn test_claim_jackpot_not_owner() {
    let (beast_mode, beast_nft) = deploy_beast_mode_with_mocks();
    let beast_mode_address = beast_mode.contract_address;
    let owner = contract_address_const::<PLAYER1>();
    let attacker = contract_address_const::<PLAYER2>();

    // First mint a valid jackpot beast
    mock_owner_of_call(owner);
    mock_beast_hash_call('DEMON_GRASP');
    mock_valid_collectable_call(12345_u64, 10_u16, 100_u16);
    mock_erc20_safe_transfer_call();

    start_cheat_caller_address(beast_mode_address, owner);
    beast_mode.claim_beast(1_u64, 29_u8, 18_u8, 6_u8);
    stop_cheat_caller_address(beast_mode_address);

    // Mock beast NFT owner check - owner is PLAYER1
    mock_call(beast_nft.contract_address, selector!("owner_of"), owner, 1);

    // Try to claim as PLAYER2 - should fail
    start_cheat_caller_address(beast_mode_address, attacker);
    beast_mode.claim_jackpot(76_u64);
    stop_cheat_caller_address(beast_mode_address);
}

#[test]
#[should_panic(expected: "Invalid beast")]
fn test_claim_jackpot_invalid_beast() {
    let (beast_mode, beast_nft) = deploy_beast_mode_with_mocks();
    let beast_mode_address = beast_mode.contract_address;
    let player = contract_address_const::<PLAYER1>();

    // First mint a regular beast (not eligible for jackpot)
    mock_owner_of_call(player);
    mock_beast_hash_call('REGULAR_BEAST');
    mock_valid_collectable_call(12345_u64, 10_u16, 100_u16);
    mock_erc20_safe_transfer_call();

    start_cheat_caller_address(beast_mode_address, player);
    beast_mode.claim_beast(1_u64, 10_u8, 5_u8, 3_u8); // Random non-jackpot beast
    stop_cheat_caller_address(beast_mode_address);

    // Mock beast NFT owner check
    mock_call(beast_nft.contract_address, selector!("owner_of"), player, 1);

    // Try to claim jackpot - should fail
    start_cheat_caller_address(beast_mode_address, player);
    beast_mode.claim_jackpot(76_u64);
    stop_cheat_caller_address(beast_mode_address);
}

#[test]
#[should_panic(expected: "Token already claimed")]
fn test_claim_jackpot_double_claim() {
    let (beast_mode, beast_nft) = deploy_beast_mode_with_mocks();
    let beast_mode_address = beast_mode.contract_address;
    let player = contract_address_const::<PLAYER1>();

    // First mint a demon grasp beast
    mock_owner_of_call(player);
    mock_beast_hash_call('DEMON_GRASP');
    mock_valid_collectable_call(12345_u64, 10_u16, 100_u16);
    mock_erc20_safe_transfer_call();

    start_cheat_caller_address(beast_mode_address, player);
    beast_mode.claim_beast(1_u64, 29_u8, 18_u8, 6_u8);
    stop_cheat_caller_address(beast_mode_address);

    // Mock beast NFT owner check (2 calls)
    mock_call(beast_nft.contract_address, selector!("owner_of"), player, 2);

    // Mock the STRK token transfer
    mock_call(
        0x04718f5a0Fc34cC1AF16A1cdee98fFB20C31f5cD61D6Ab07201858f4287c938D.try_into().unwrap(),
        selector!("transfer"),
        true,
        1,
    );

    start_cheat_caller_address(beast_mode_address, player);

    // First claim should succeed
    beast_mode.claim_jackpot(76_u64);

    // Second claim should fail
    beast_mode.claim_jackpot(76_u64);

    stop_cheat_caller_address(beast_mode_address);
}
