use starknet::ContractAddress;

#[derive(Drop, Copy, Serde, starknet::Store)]
pub struct Collectable {
    pub id: u8,
    pub level: u16,
    pub health: u16,
    pub prefix: u8,
    pub suffix: u8,
    pub shiny: u8,
    pub animated: u8,
    pub collected_by: u64,
    pub last_death_timestamp: u64,
}

#[starknet::interface]
pub trait IGameCoreSystems<T> {
    fn get_collectable(self: @T, collectable_id: felt252) -> Collectable;
}

#[starknet::interface]
pub trait IBeastMode<T> {
    // View functions
    fn dungeon_opening_time(self: @T) -> u64;
    fn get_game_token_address(self: @T) -> ContractAddress;
    fn get_game_core_address(self: @T) -> ContractAddress;
    fn get_beasts_nft_address(self: @T) -> ContractAddress;
    fn jackpot_claimed(self: @T, token_id: u64) -> bool;

    // State-changing functions
    fn claim_beast(
        ref self: T, adventurer_id: felt252, beast_id: u8, prefix: u8, suffix: u8,
    ) -> u256;
    fn claim_jackpot(ref self: T, token_id: u64);

    // Owner-only functions
    fn update_opening_time(ref self: T, new_opening_time: u64);
    fn update_payment_token(ref self: T, new_payment_token: ContractAddress);
    fn update_ticket_receiver_address(ref self: T, new_ticket_receiver_address: ContractAddress);
    fn update_settings_id(ref self: T, new_settings_id: Option<u32>);
    fn update_cost_to_play(ref self: T, new_cost_to_play: u128);
    fn open_dungeon(ref self: T);
    fn close_dungeon(ref self: T);
}
