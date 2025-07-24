use starknet::ContractAddress;

#[derive(Drop, Serde, Copy)]
struct PackableBeast {
    id: u8,
    prefix: u8,
    suffix: u8,
    level: u16,
    health: u16,
}

#[starknet::interface]
trait IBeasts<T> {
    fn get_beast(self: @T, token_id: u256) -> PackableBeast;
    fn owner_of(self: @T, token_id: u256) -> ContractAddress;
}

#[starknet::contract]
pub mod beast_mode {
    use super::PackableBeast;
    use starknet::ContractAddress;

    #[storage]
    struct Storage {
        game_token_address: ContractAddress,
        game_collectable_address: ContractAddress,
        beast_nft_address: ContractAddress,
        beast_v1_address: ContractAddress,
        airdrop_count: u16,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        BeastClaimed: BeastClaimed,
        BeastAirdropped: BeastAirdropped,
    }

    #[derive(Drop, starknet::Event)]
    struct BeastClaimed {
        adventurer_id: u64,
        beast_id: u8,
        prefix: u8,
        suffix: u8,
    }

    #[derive(Drop, starknet::Event)]
    struct BeastAirdropped {
        token_id: u16,
        beast: PackableBeast,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        game_token_address: ContractAddress,
        game_collectable_address: ContractAddress,
        beast_nft_address: ContractAddress,
        beast_v1_address: ContractAddress,
    ) {
        self.game_token_address.write(game_token_address);
        self.game_collectable_address.write(game_collectable_address);
        self.beast_nft_address.write(beast_nft_address);
        self.beast_v1_address.write(beast_v1_address);
        self.airdrop_count.write(0);
    }

    #[external(v0)]
    fn claim_beast(
        ref self: ContractState, adventurer_id: u64, beast_id: u8, prefix: u8, suffix: u8,
    ) {
        self.emit(BeastClaimed { adventurer_id, beast_id, prefix, suffix });
    }

    #[external(v0)]
    fn airdrop_v1_beasts(ref self: ContractState) {
        let mut airdrop_count = self.airdrop_count.read();
        airdrop_count += 1;
        self.airdrop_count.write(airdrop_count);
        
        let example_beast = PackableBeast {
            id: 1,
            prefix: 0,
            suffix: 0,
            level: 1,
            health: 100,
        };
        
        self.emit(BeastAirdropped { token_id: airdrop_count, beast: example_beast });
    }

    #[external(v0)]
    fn get_game_token_address(self: @ContractState) -> ContractAddress {
        self.game_token_address.read()
    }

    #[external(v0)]
    fn get_game_collectable_address(self: @ContractState) -> ContractAddress {
        self.game_collectable_address.read()
    }

    #[external(v0)]
    fn get_beast_nft_address(self: @ContractState) -> ContractAddress {
        self.beast_nft_address.read()
    }
}