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

// Mock Beast NFT Contract - ONLY contract we need to deploy
#[starknet::interface]
pub trait IMockBeastNFT<TContractState> {
    // Mint function matching the real interface
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
    
    // Getter functions to verify mint was called with correct params
    fn get_last_mint(self: @TContractState) -> (ContractAddress, u8, u8, u8, u16, u16, u8, u8);
    fn get_mint_count(self: @TContractState) -> u32;
    fn get_beast(self: @TContractState, index: u256) -> Beast;
    fn get_all_beasts(self: @TContractState) -> Array<Beast>;
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

        fn get_last_mint(self: @ContractState) -> (ContractAddress, u8, u8, u8, u16, u16, u8, u8) {
            let count = self.mint_count.read();
            if count == 0 {
                // Return default values if no mints
                return (
                    starknet::contract_address_const::<0>(),
                    0, 0, 0, 0, 0, 0, 0
                );
            }
            
            let last_beast = self.beasts.entry((count - 1).into()).read();
            (
                last_beast.owner,
                last_beast.beast_id,
                last_beast.prefix,
                last_beast.suffix,
                last_beast.level,
                last_beast.health,
                last_beast.shiny,
                last_beast.animated,
            )
        }

        fn get_mint_count(self: @ContractState) -> u32 {
            self.mint_count.read()
        }
        
        fn get_beast(self: @ContractState, index: u256) -> Beast {
            self.beasts.entry(index).read()
        }
        
        fn get_all_beasts(self: @ContractState) -> Array<Beast> {
            let mut beasts = array![];
            let count = self.mint_count.read();
            let mut i: u32 = 0;
            
            loop {
                if i >= count {
                    break;
                }
                
                let beast = self.beasts.entry(i.into()).read();
                beasts.append(beast);
                i += 1;
            };
            
            beasts
        }
    }
}