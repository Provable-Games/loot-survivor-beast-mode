use starknet::ContractAddress;
use super::structs::LegacyBeast;

#[derive(Drop, Serde, Copy)]
pub enum CollectableResult {
    Ok: (u64, u16, u16),
    Err: felt252,
}

#[starknet::interface]
pub trait IBeastSystems<T> {
    fn get_beast_hash(self: @T, beast_id: u8, prefix: u8, suffix: u8) -> felt252;
    fn get_valid_collectable(
        self: @T, contract_address: ContractAddress, adventurer_id: u64, entity_hash: felt252,
    ) -> CollectableResult;
    fn premint_collectable(
        self: @T, beast_id: u8, prefix: u8, suffix: u8, level: u16, health: u16,
    ) -> u64;
}

#[starknet::interface]
pub trait ILegacyBeasts<T> {
    fn getBeast(self: @T, token_id: u256) -> LegacyBeast;
    fn ownerOf(self: @T, token_id: u256) -> ContractAddress;
    fn totalSupply(self: @T) -> u256;
}
