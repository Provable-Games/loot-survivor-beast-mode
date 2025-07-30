use starknet::ContractAddress;

// Beast struct to store minted beast data
#[derive(Drop, Serde, Copy, starknet::Store)]
pub struct Beast {
    pub owner: ContractAddress,
    pub beast_id: u8,
    pub prefix: u8,
    pub suffix: u8,
    pub level: u16,
    pub health: u16,
    pub shiny: u8,
    pub animated: u8,
}

#[starknet::interface]
pub trait IMockBeastNFT<TContractState> {
    fn mint(
        ref self: TContractState,
        to: ContractAddress,
        beast_id: u8,
        prefix: u8,
        suffix: u8,
        level: u16,
        health: u16,
        shiny: u8,
        animated: u8,
    );
    
    fn get_mint_count(self: @TContractState) -> u32;
    fn get_beast(self: @TContractState, index: u256) -> Beast;
}

#[starknet::contract]
pub mod MockBeastNFT {
    use starknet::ContractAddress;
    use starknet::storage::{Map, StoragePointerReadAccess, StoragePointerWriteAccess, StoragePathEntry};
    use super::Beast;

    #[storage]
    struct Storage {
        beasts: Map<u256, Beast>,
        mint_count: u32,
    }

    #[abi(embed_v0)]
    impl MockBeastNFTImpl of super::IMockBeastNFT<ContractState> {
        fn mint(
            ref self: ContractState,
            to: ContractAddress,
            beast_id: u8,
            prefix: u8,
            suffix: u8,
            level: u16,
            health: u16,
            shiny: u8,
            animated: u8,
        ) {
            let current_count = self.mint_count.read();
            let beast = Beast {
                owner: to,
                beast_id,
                prefix,
                suffix,
                level,
                health,
                shiny,
                animated,
            };
            
            // Store the beast using the current count as index
            self.beasts.entry(current_count.into()).write(beast);
            self.mint_count.write(current_count + 1);
        }

        fn get_mint_count(self: @ContractState) -> u32 {
            self.mint_count.read()
        }
        
        fn get_beast(self: @ContractState, index: u256) -> Beast {
            self.beasts.entry(index).read()
        }
    }
}