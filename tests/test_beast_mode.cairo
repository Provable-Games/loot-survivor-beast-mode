use beast_mode::interfaces::{Collectable, IBeastModeDispatcher, IBeastModeDispatcherTrait};
use beasts_nft::interfaces::{IBeastsDispatcher, IBeastsDispatcherTrait};
use beasts_nft::pack::PackableBeast;
use core::serde::Serde;
use openzeppelin_interfaces::upgrades::{IUpgradeableDispatcher, IUpgradeableDispatcherTrait};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, mock_call, start_cheat_caller_address,
    start_mock_call, stop_cheat_caller_address,
};
use starknet::{ClassHash, ContractAddress, contract_address_const};

// Test constants
const OWNER: felt252 = 'OWNER';
const PLAYER1: felt252 = 'PLAYER1';
const PLAYER2: felt252 = 'PLAYER2';

// Mock contract addresses
fn DENSHOKAN_ADDRESS() -> ContractAddress {
    contract_address_const::<'DENSHOKAN'>()
}

fn GAME_TOKEN_ADDRESS() -> ContractAddress {
    contract_address_const::<'GAME_TOKEN'>()
}

fn GAME_CORE_ADDRESS() -> ContractAddress {
    contract_address_const::<'GAME_CORE'>()
}

fn PAYMENT_TOKEN_ADDRESS() -> ContractAddress {
    contract_address_const::<'PAYMENT_TOKEN'>()
}

fn REWARD_TOKEN_ADDRESS() -> ContractAddress {
    contract_address_const::<'REWARD_TOKEN'>()
}

fn TICKET_RECEIVER_ADDRESS() -> ContractAddress {
    contract_address_const::<'TICKET_RECEIVER'>()
}

fn STRK_ADDRESS() -> ContractAddress {
    0x04718f5a0Fc34cC1AF16A1cdee98fFB20C31f5cD61D6Ab07201858f4287c938D.try_into().unwrap()
}

// Deploy real BeastNFT contract (mints 75 genesis beasts to owner)
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
    calldata.append(0); // terminal_timestamp

    let (contract_address, _) = contract.deploy(@calldata).unwrap();
    IBeastsDispatcher { contract_address }
}

fn deploy_beast_mode() -> (IBeastModeDispatcher, IBeastsDispatcher) {
    let beast_nft = deploy_beast_nft();

    let contract = declare("beast_mode").unwrap().contract_class();

    let owner_address = contract_address_const::<OWNER>();
    let opening_time = 1000_u64;
    let settings_id = 1_u32;
    let cost_to_play = 100_u256;

    let (contract_address, _) = contract
        .deploy(
            @array![
                owner_address.into(), opening_time.into(), DENSHOKAN_ADDRESS().into(),
                GAME_TOKEN_ADDRESS().into(), GAME_CORE_ADDRESS().into(),
                beast_nft.contract_address.into(), PAYMENT_TOKEN_ADDRESS().into(),
                REWARD_TOKEN_ADDRESS().into(), 0, // empty golden_pass span
                TICKET_RECEIVER_ADDRESS().into(), settings_id.into(), cost_to_play.low.into(),
                cost_to_play.high.into(),
            ],
        )
        .unwrap();

    let beast_mode = IBeastModeDispatcher { contract_address };

    // Set beast_mode as the dungeon (minter) on the BeastNFT contract
    start_cheat_caller_address(beast_nft.contract_address, owner_address);
    beast_nft.set_dungeon_address(beast_mode.contract_address);
    stop_cheat_caller_address(beast_nft.contract_address);

    (beast_mode, beast_nft)
}

// Helper mocks - small adventurer_id values unpack to all-zeros, so
// create_collected_by(adventurer_id) == 0.

fn mock_minted_by_self(beast_mode_address: ContractAddress, times: u32) {
    mock_call(DENSHOKAN_ADDRESS(), selector!("minted_by_address"), beast_mode_address, times);
}

fn mock_collectable(level: u16, health: u16, shiny: u8, animated: u8, times: u32) {
    let collectable = Collectable {
        id: 0,
        level,
        health,
        prefix: 0,
        suffix: 0,
        shiny,
        animated,
        collected_by: 0,
        last_death_timestamp: 0,
    };
    mock_call(GAME_CORE_ADDRESS(), selector!("get_collectable"), collectable, times);
}

fn mock_denshokan_owner_of(owner: ContractAddress, times: u32) {
    mock_call(DENSHOKAN_ADDRESS(), selector!("owner_of"), owner, times);
}

fn mock_reward_transfer(times: u32) {
    mock_call(REWARD_TOKEN_ADDRESS(), selector!("transfer"), true, times);
}

// Sets up all mocks needed for a single successful claim_beast call.
fn setup_successful_claim(beast_mode_address: ContractAddress, player: ContractAddress) {
    mock_minted_by_self(beast_mode_address, 1);
    mock_collectable(5_u16, 100_u16, 0_u8, 0_u8, 1);
    mock_denshokan_owner_of(player, 1);
    mock_reward_transfer(1);
}

// ===========================================
// CLAIM BEAST TESTS
// ===========================================

#[test]
fn test_claim_beast_mints_with_expected_traits() {
    let (beast_mode, beast_nft) = deploy_beast_mode();
    let beast_mode_address = beast_mode.contract_address;
    let player = contract_address_const::<PLAYER1>();

    let adventurer_id: felt252 = 1;
    let beast_id = 10_u8;
    let prefix = 1_u8;
    let suffix = 2_u8;
    let level = 5_u16;
    let health = 100_u16;

    mock_minted_by_self(beast_mode_address, 1);
    mock_collectable(level, health, 0_u8, 0_u8, 1);
    mock_denshokan_owner_of(player, 1);
    mock_reward_transfer(1);

    let token_id = beast_mode.claim_beast(adventurer_id, beast_id, prefix, suffix);

    // 75 genesis beasts pre-minted, so this should be token 76
    assert(token_id == 76, 'Expected token_id 76');
    assert(beast_nft.total_supply() == 76, 'Wrong total supply');

    let beast: PackableBeast = beast_nft.get_beast(76);
    assert(beast.id == beast_id, 'Wrong beast_id');
    assert(beast.prefix == prefix, 'Wrong prefix');
    assert(beast.suffix == suffix, 'Wrong suffix');
    assert(beast.level == level, 'Wrong level');
    assert(beast.health == health, 'Wrong health');
    assert(beast.shiny == 0, 'Expected no shiny');
    assert(beast.animated == 0, 'Expected no animated');

    assert(beast_nft.is_minted(beast_id, prefix, suffix), 'Beast not marked as minted');
}

#[test]
fn test_claim_beast_propagates_shiny_animated() {
    let (beast_mode, beast_nft) = deploy_beast_mode();
    let beast_mode_address = beast_mode.contract_address;
    let player = contract_address_const::<PLAYER1>();

    mock_minted_by_self(beast_mode_address, 1);
    mock_collectable(5_u16, 100_u16, 1_u8, 1_u8, 1);
    mock_denshokan_owner_of(player, 1);
    mock_reward_transfer(1);

    beast_mode.claim_beast(1, 10_u8, 1_u8, 2_u8);

    let beast: PackableBeast = beast_nft.get_beast(76);
    assert(beast.shiny == 1, 'Expected shiny');
    assert(beast.animated == 1, 'Expected animated');
}

#[test]
#[should_panic(expected: ('Not beast mode',))]
fn test_claim_beast_wrong_dungeon() {
    let (beast_mode, _) = deploy_beast_mode();

    // Adventurer was minted by a different dungeon
    let other_dungeon = contract_address_const::<'OTHER_DUNGEON'>();
    mock_call(DENSHOKAN_ADDRESS(), selector!("minted_by_address"), other_dungeon, 1);

    beast_mode.claim_beast(1, 10_u8, 1_u8, 2_u8);
}

#[test]
#[should_panic(expected: ('Not your collectable',))]
fn test_claim_beast_wrong_collectable_owner() {
    let (beast_mode, _) = deploy_beast_mode();
    let beast_mode_address = beast_mode.contract_address;

    mock_minted_by_self(beast_mode_address, 1);

    // Return a collectable that was claimed by a different adventurer
    let collectable = Collectable {
        id: 0,
        level: 5,
        health: 100,
        prefix: 0,
        suffix: 0,
        shiny: 0,
        animated: 0,
        collected_by: 999_u64,
        last_death_timestamp: 0,
    };
    mock_call(GAME_CORE_ADDRESS(), selector!("get_collectable"), collectable, 1);

    beast_mode.claim_beast(1, 10_u8, 1_u8, 2_u8);
}

#[test]
fn test_multiple_players_claim_beasts() {
    let (beast_mode, beast_nft) = deploy_beast_mode();
    let beast_mode_address = beast_mode.contract_address;
    let player1 = contract_address_const::<PLAYER1>();
    let player2 = contract_address_const::<PLAYER2>();

    setup_successful_claim(beast_mode_address, player1);
    beast_mode.claim_beast(1, 10_u8, 1_u8, 1_u8);

    setup_successful_claim(beast_mode_address, player2);
    beast_mode.claim_beast(2, 20_u8, 2_u8, 2_u8);

    assert(beast_nft.total_supply() == 77, 'Wrong total supply');

    let beast1: PackableBeast = beast_nft.get_beast(76);
    assert(beast1.id == 10, 'Wrong id beast 1');
    assert(beast1.prefix == 1, 'Wrong prefix beast 1');
    assert(beast1.suffix == 1, 'Wrong suffix beast 1');

    let beast2: PackableBeast = beast_nft.get_beast(77);
    assert(beast2.id == 20, 'Wrong id beast 2');
    assert(beast2.prefix == 2, 'Wrong prefix beast 2');
    assert(beast2.suffix == 2, 'Wrong suffix beast 2');

    assert(beast_nft.is_minted(10, 1, 1), 'Beast 1 not marked');
    assert(beast_nft.is_minted(20, 2, 2), 'Beast 2 not marked');
}

// ===========================================
// JACKPOT TESTS
// ===========================================

#[test]
fn test_claim_jackpot_pain_whisper() {
    let (beast_mode, beast_nft) = deploy_beast_mode();
    let beast_mode_address = beast_mode.contract_address;
    let player = contract_address_const::<PLAYER1>();

    // Mint a pain whisper beast (id=1, prefix=47, suffix=11)
    setup_successful_claim(beast_mode_address, player);
    beast_mode.claim_beast(1, 1_u8, 47_u8, 11_u8);

    // Beast NFT owner check returns the player
    mock_call(beast_nft.contract_address, selector!("owner_of"), player, 1);

    // STRK transfer succeeds
    mock_call(STRK_ADDRESS(), selector!("transfer"), true, 1);

    start_cheat_caller_address(beast_mode_address, player);
    beast_mode.claim_jackpot(76_u64);
    stop_cheat_caller_address(beast_mode_address);

    assert(beast_mode.jackpot_claimed(76_u64), 'Jackpot not marked claimed');
}

#[test]
fn test_claim_jackpot_torment_bane() {
    let (beast_mode, beast_nft) = deploy_beast_mode();
    let beast_mode_address = beast_mode.contract_address;
    let player = contract_address_const::<PLAYER1>();

    // Mint a torment bane beast (id=53, prefix=61, suffix=1)
    setup_successful_claim(beast_mode_address, player);
    beast_mode.claim_beast(1, 53_u8, 61_u8, 1_u8);

    mock_call(beast_nft.contract_address, selector!("owner_of"), player, 1);
    mock_call(STRK_ADDRESS(), selector!("transfer"), true, 1);

    start_cheat_caller_address(beast_mode_address, player);
    beast_mode.claim_jackpot(76_u64);
    stop_cheat_caller_address(beast_mode_address);

    assert(beast_mode.jackpot_claimed(76_u64), 'Jackpot not marked claimed');
}

#[test]
#[should_panic(expected: ('Not token owner',))]
fn test_claim_jackpot_not_owner() {
    let (beast_mode, beast_nft) = deploy_beast_mode();
    let beast_mode_address = beast_mode.contract_address;
    let owner = contract_address_const::<PLAYER1>();
    let attacker = contract_address_const::<PLAYER2>();

    // Mint a valid jackpot beast
    setup_successful_claim(beast_mode_address, owner);
    beast_mode.claim_beast(1, 1_u8, 47_u8, 11_u8);

    // Beast NFT owner check returns PLAYER1
    mock_call(beast_nft.contract_address, selector!("owner_of"), owner, 1);

    // Caller is PLAYER2 - should be rejected
    start_cheat_caller_address(beast_mode_address, attacker);
    beast_mode.claim_jackpot(76_u64);
    stop_cheat_caller_address(beast_mode_address);
}

#[test]
#[should_panic(expected: "Invalid beast")]
fn test_claim_jackpot_invalid_beast() {
    let (beast_mode, beast_nft) = deploy_beast_mode();
    let beast_mode_address = beast_mode.contract_address;
    let player = contract_address_const::<PLAYER1>();

    // Mint a non-jackpot beast
    setup_successful_claim(beast_mode_address, player);
    beast_mode.claim_beast(1, 10_u8, 5_u8, 3_u8);

    mock_call(beast_nft.contract_address, selector!("owner_of"), player, 1);

    start_cheat_caller_address(beast_mode_address, player);
    beast_mode.claim_jackpot(76_u64);
    stop_cheat_caller_address(beast_mode_address);
}

#[test]
#[should_panic(expected: ('Not pain',))]
fn test_claim_jackpot_id1_wrong_prefix() {
    let (beast_mode, beast_nft) = deploy_beast_mode();
    let beast_mode_address = beast_mode.contract_address;
    let player = contract_address_const::<PLAYER1>();

    // id=1 but wrong prefix
    setup_successful_claim(beast_mode_address, player);
    beast_mode.claim_beast(1, 1_u8, 5_u8, 11_u8);

    mock_call(beast_nft.contract_address, selector!("owner_of"), player, 1);

    start_cheat_caller_address(beast_mode_address, player);
    beast_mode.claim_jackpot(76_u64);
    stop_cheat_caller_address(beast_mode_address);
}

#[test]
#[should_panic(expected: ('Not torment',))]
fn test_claim_jackpot_id53_wrong_prefix() {
    let (beast_mode, beast_nft) = deploy_beast_mode();
    let beast_mode_address = beast_mode.contract_address;
    let player = contract_address_const::<PLAYER1>();

    // id=53 but wrong prefix
    setup_successful_claim(beast_mode_address, player);
    beast_mode.claim_beast(1, 53_u8, 5_u8, 1_u8);

    mock_call(beast_nft.contract_address, selector!("owner_of"), player, 1);

    start_cheat_caller_address(beast_mode_address, player);
    beast_mode.claim_jackpot(76_u64);
    stop_cheat_caller_address(beast_mode_address);
}

#[test]
#[should_panic(expected: "Token already claimed")]
fn test_claim_jackpot_double_claim() {
    let (beast_mode, beast_nft) = deploy_beast_mode();
    let beast_mode_address = beast_mode.contract_address;
    let player = contract_address_const::<PLAYER1>();

    setup_successful_claim(beast_mode_address, player);
    beast_mode.claim_beast(1, 1_u8, 47_u8, 11_u8);

    mock_call(beast_nft.contract_address, selector!("owner_of"), player, 2);
    mock_call(STRK_ADDRESS(), selector!("transfer"), true, 1);

    start_cheat_caller_address(beast_mode_address, player);
    beast_mode.claim_jackpot(76_u64);
    // Second claim must fail
    beast_mode.claim_jackpot(76_u64);
    stop_cheat_caller_address(beast_mode_address);
}

// ===========================================
// ADMIN / ACCESS CONTROL TESTS
// ===========================================

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_update_opening_time_not_owner() {
    let (beast_mode, _) = deploy_beast_mode();
    let attacker = contract_address_const::<'ATTACKER'>();

    start_cheat_caller_address(beast_mode.contract_address, attacker);
    beast_mode.update_opening_time(2000_u64);
    stop_cheat_caller_address(beast_mode.contract_address);
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_update_payment_token_not_owner() {
    let (beast_mode, _) = deploy_beast_mode();
    let attacker = contract_address_const::<'ATTACKER'>();
    let fake_token = contract_address_const::<'FAKE_TOKEN'>();

    start_cheat_caller_address(beast_mode.contract_address, attacker);
    beast_mode.update_payment_token(fake_token);
    stop_cheat_caller_address(beast_mode.contract_address);
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_update_cost_to_play_not_owner() {
    let (beast_mode, _) = deploy_beast_mode();
    let attacker = contract_address_const::<'ATTACKER'>();

    start_cheat_caller_address(beast_mode.contract_address, attacker);
    beast_mode.update_cost_to_play(999999_u128);
    stop_cheat_caller_address(beast_mode.contract_address);
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_update_ticket_receiver_not_owner() {
    let (beast_mode, _) = deploy_beast_mode();
    let attacker = contract_address_const::<'ATTACKER'>();
    let fake_receiver = contract_address_const::<'FAKE_RECEIVER'>();

    start_cheat_caller_address(beast_mode.contract_address, attacker);
    beast_mode.update_ticket_receiver_address(fake_receiver);
    stop_cheat_caller_address(beast_mode.contract_address);
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_update_settings_id_not_owner() {
    let (beast_mode, _) = deploy_beast_mode();
    let attacker = contract_address_const::<'ATTACKER'>();

    start_cheat_caller_address(beast_mode.contract_address, attacker);
    beast_mode.update_settings_id(Option::Some(99_u32));
    stop_cheat_caller_address(beast_mode.contract_address);
}

#[test]
fn test_admin_functions_owner_access() {
    let (beast_mode, _) = deploy_beast_mode();
    let owner = contract_address_const::<OWNER>();
    let new_token = contract_address_const::<'NEW_TOKEN'>();
    let new_receiver = contract_address_const::<'NEW_RECEIVER'>();

    start_cheat_caller_address(beast_mode.contract_address, owner);
    beast_mode.update_opening_time(3000_u64);
    beast_mode.update_payment_token(new_token);
    beast_mode.update_cost_to_play(500_u128);
    beast_mode.update_ticket_receiver_address(new_receiver);
    beast_mode.update_settings_id(Option::Some(7_u32));
    beast_mode.close_dungeon();
    beast_mode.open_dungeon();
    stop_cheat_caller_address(beast_mode.contract_address);
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_close_dungeon_not_owner() {
    let (beast_mode, _) = deploy_beast_mode();
    let attacker = contract_address_const::<'ATTACKER'>();

    start_cheat_caller_address(beast_mode.contract_address, attacker);
    beast_mode.close_dungeon();
    stop_cheat_caller_address(beast_mode.contract_address);
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_open_dungeon_not_owner() {
    let (beast_mode, _) = deploy_beast_mode();
    let attacker = contract_address_const::<'ATTACKER'>();

    start_cheat_caller_address(beast_mode.contract_address, attacker);
    beast_mode.open_dungeon();
    stop_cheat_caller_address(beast_mode.contract_address);
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_upgrade_not_owner() {
    let (beast_mode, _) = deploy_beast_mode();
    let attacker = contract_address_const::<'ATTACKER'>();
    let upgradeable = IUpgradeableDispatcher { contract_address: beast_mode.contract_address };
    let new_class_hash: ClassHash = 0x1.try_into().unwrap();

    start_cheat_caller_address(beast_mode.contract_address, attacker);
    upgradeable.upgrade(new_class_hash);
    stop_cheat_caller_address(beast_mode.contract_address);
}

// ===========================================
// VIEW FUNCTIONS
// ===========================================

#[test]
fn test_view_addresses() {
    let (beast_mode, beast_nft) = deploy_beast_mode();

    assert(beast_mode.get_game_token_address() == GAME_TOKEN_ADDRESS(), 'Wrong game token address');
    assert(beast_mode.get_game_core_address() == GAME_CORE_ADDRESS(), 'Wrong game core address');
    assert(
        beast_mode.get_beasts_nft_address() == beast_nft.contract_address,
        'Wrong beast nft address',
    );
    assert(beast_mode.dungeon_opening_time() == 1000_u64, 'Wrong opening time');
}

#[test]
fn test_jackpot_claimed_initial() {
    let (beast_mode, _) = deploy_beast_mode();
    assert(!beast_mode.jackpot_claimed(76_u64), 'Should not be claimed yet');
}
