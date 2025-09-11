use starknet::ContractAddress;
use super::structs::LegacyBeast;

#[derive(Drop, Serde, Copy)]
pub enum DataResult<T> {
    Ok: T,
    Err: felt252,
}

#[starknet::interface]
pub trait IBeastSystems<T> {
    fn get_beast_hash(self: @T, beast_id: u8, prefix: u8, suffix: u8) -> felt252;
    fn get_valid_collectable(
        self: @T, contract_address: ContractAddress, adventurer_id: u64, entity_hash: felt252,
    ) -> DataResult<(u64, u16, u16)>;
    fn premint_collectable(
        self: @T, beast_seed: u64, beast_id: u8, prefix: u8, suffix: u8, level: u16, health: u16,
    ) -> u64;
}

#[starknet::interface]
pub trait IAdventurerSystems<T> {
    fn get_adventurer_level(self: @T, adventurer_id: u64) -> u8;
    fn get_adventurer_health(self: @T, adventurer_id: u64) -> u16;
    fn get_adventurer_dungeon(self: @T, adventurer_id: u64) -> ContractAddress;
}

#[starknet::interface]
pub trait ILegacyBeasts<T> {
    fn getBeast(self: @T, token_id: u256) -> LegacyBeast;
    fn ownerOf(self: @T, token_id: u256) -> ContractAddress;
    fn tokenSupply(self: @T) -> u256;
}

#[starknet::interface]
pub trait IBeastMode<T> {
    // View functions
    fn get_opening_time(self: @T) -> u64;
    fn get_game_token_address(self: @T) -> ContractAddress;
    fn get_game_collectable_address(self: @T) -> ContractAddress;
    fn get_beast_nft_address(self: @T) -> ContractAddress;
    fn get_legacy_beasts_address(self: @T) -> ContractAddress;
    fn get_airdrop_count(self: @T) -> u16;
    fn get_airdrop_block_number(self: @T) -> u64;
    fn get_reward_token_address(self: @T) -> ContractAddress;
    fn get_free_games_duration(self: @T) -> u64;
    fn get_bonus_duration(self: @T) -> u64;
    fn get_free_games_claimer_address(self: @T) -> ContractAddress;
    fn get_free_games_claimed(self: @T) -> u32;
    fn get_reward_tokens_claimed(self: @T) -> u32;
    fn get_beast_airdrop_count(self: @T) -> u16;
    fn has_adventurer_claimed_reward(self: @T, token_id: u64) -> bool;
    fn jackpot_claimed(self: @T, token_id: u64) -> bool;

    // State-changing functions
    fn claim_beast(ref self: T, adventurer_id: u64, beast_id: u8, prefix: u8, suffix: u8) -> u256;
    fn claim_reward_token(ref self: T, token_id: u64);
    fn initiate_airdrop(ref self: T);
    fn airdrop_legacy_beasts(ref self: T, limit: u16);
    fn airdrop_legacy_beast_reward_tokens(ref self: T, limit: u16);
    fn airdrop_top_legacy_adventurers(ref self: T, limit: u16);
    fn claim_free_game(ref self: T, to: ContractAddress, player_name: Option<felt252>) -> u64;
    fn claim_jackpot(ref self: T, token_id: u64);

    // Owner-only functions
    fn update_opening_time(ref self: T, new_opening_time: u64);
    fn update_payment_token(ref self: T, new_payment_token: ContractAddress);
    fn update_ticket_receiver_address(ref self: T, new_ticket_receiver_address: ContractAddress);
    fn update_settings_id(ref self: T, new_settings_id: Option<u32>);
    fn update_cost_to_play(ref self: T, new_cost_to_play: u128);
}
