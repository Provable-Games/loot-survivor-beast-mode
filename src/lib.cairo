// External dependencies
use game_components_metagame::ticket_booth::{TicketBoothComponent, TicketBoothComponent::GoldenPass};
use starknet::ContractAddress;
use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};

// Local modules
mod interfaces;
mod structs;


// Local imports
use interfaces::{
    IBeastSystemsDispatcher, IBeastSystemsDispatcherTrait,
    ILegacyBeastsDispatcher, ILegacyBeastsDispatcherTrait,
    CollectableResult
};

// External interface imports
use beasts_nft::interfaces::{IBeastsDispatcher, IBeastsDispatcherTrait};
use openzeppelin_token::erc721::interface::{IERC721Dispatcher, IERC721DispatcherTrait};

#[starknet::contract]
pub mod beast_mode {
    use super::*;

    component!(path: TicketBoothComponent, storage: ticket_booth, event: TicketBoothEvent);

    #[abi(embed_v0)]
    impl TicketBoothImpl = TicketBoothComponent::TicketBoothImpl<ContractState>;
    impl TicketBoothInternalImpl = TicketBoothComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        ticket_booth: TicketBoothComponent::Storage,
        // Rename to avoid collision with ticket_booth.game_token_address
        beast_game_token_address: ContractAddress,
        game_collectable_address: ContractAddress,
        beast_nft_address: ContractAddress,
        legacy_beasts_address: ContractAddress,
        airdrop_count: u16,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        TicketBoothEvent: TicketBoothComponent::Event,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        opening_time: u64,
        game_token_address: ContractAddress,
        game_collectable_address: ContractAddress,
        beast_nft_address: ContractAddress,
        legacy_beasts_address: ContractAddress,
        payment_token: ContractAddress,
        renderer_address: ContractAddress,
        golden_pass_address: ContractAddress,
        ticket_receiver_address: ContractAddress,
    ) {
        // Initialize storage
        self.beast_game_token_address.write(game_token_address);
        self.game_collectable_address.write(game_collectable_address);
        self.beast_nft_address.write(beast_nft_address);
        self.legacy_beasts_address.write(legacy_beasts_address);
        self.airdrop_count.write(0);

        // Configure ticket booth
        let cost_to_play: u256 = 1000000000000000000; // 1 ETH
        let settings_id = 0;
        let golden_pass = GoldenPass {
            cooldown: 82800,        // 23 hours in seconds
            game_expiration: 864000 // 10 days in seconds
        };

        self.ticket_booth.initializer(
            opening_time,
            game_token_address,
            payment_token,
            cost_to_play.try_into().unwrap(),
            ticket_receiver_address,
            Some(game_token_address), // game_address
            Some(settings_id),
            Some(0), // start_time
            Some(0), // expiration_time
            Option::Some("https://lootsurvivor.io"),
            Some(renderer_address),
            Some(array![(golden_pass_address, golden_pass)].span()),
        );
    }

    #[external(v0)]
    fn claim_beast(
        ref self: ContractState, 
        adventurer_id: u64, 
        beast_id: u8, 
        prefix: u8, 
        suffix: u8,
    ) {
        // Read contract addresses
        let game_token_address = self.beast_game_token_address.read();
        let game_collectable_address = self.game_collectable_address.read();
        let beast_nft_address = self.beast_nft_address.read();

        // Create dispatchers
        let beast_systems = IBeastSystemsDispatcher { contract_address: game_collectable_address };
        let beasts_nft = IBeastsDispatcher { contract_address: beast_nft_address };
        let game_token = IERC721Dispatcher { contract_address: game_token_address };

        // Calculate entity hash and validate collectable
        let entity_hash = beast_systems.get_beast_hash(beast_id, prefix, suffix);
        
        match beast_systems.get_valid_collectable(
            starknet::get_contract_address(), 
            adventurer_id, 
            entity_hash
        ) {
            CollectableResult::Ok((seed, level, health)) => {
                // Determine rare traits (1% chance each)
                let shiny = if (seed % 10000_u64) < 100_u64 { 1_u8 } else { 0_u8 };
                let animated = if ((seed / 10000_u64) % 10000_u64) < 100_u64 { 1_u8 } else { 0_u8 };

                // Mint the beast NFT
                beasts_nft.mint(
                    game_token.owner_of(adventurer_id.into()),
                    beast_id,
                    prefix,
                    suffix,
                    level,
                    health,
                    shiny,
                    animated,
                );
            },
            CollectableResult::Err(_) => {
                core::panic_with_felt252('Invalid collectable'.into());
            },
        }
    }

    #[external(v0)]
    fn airdrop_legacy_beasts(ref self: ContractState) {
        // Increment airdrop counter
        let mut airdrop_count = self.airdrop_count.read();
        airdrop_count += 1;
        self.airdrop_count.write(airdrop_count);

        // Get legacy beast data
        let legacy_beasts_dispatcher = ILegacyBeastsDispatcher {
            contract_address: self.legacy_beasts_address.read(),
        };
        let beast = legacy_beasts_dispatcher.getBeast(airdrop_count.into());

        // Generate seed for traits
        let beast_systems = IBeastSystemsDispatcher {
            contract_address: self.game_collectable_address.read(),
        };
        let seed = beast_systems.premint_collectable(
            beast.id, beast.prefix, beast.suffix, beast.level, beast.health
        );

        // Determine rare traits (1% chance each)
        let shiny = if (seed % 10000_u64) < 100_u64 { 1_u8 } else { 0_u8 };
        let animated = if ((seed / 10000_u64) % 10000_u64) < 100_u64 { 1_u8 } else { 0_u8 };

        // Mint the beast NFT
        let beasts_nft = IBeastsDispatcher { contract_address: self.beast_nft_address.read() };
        beasts_nft.mint(
            legacy_beasts_dispatcher.ownerOf(airdrop_count.into()),
            beast.id,
            beast.prefix,
            beast.suffix,
            beast.level,
            beast.health,
            shiny,
            animated,
        );
    }

    // Getter functions
    #[external(v0)]
    fn get_game_token_address(self: @ContractState) -> ContractAddress {
        self.beast_game_token_address.read()
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
