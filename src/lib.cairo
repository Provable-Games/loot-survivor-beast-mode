use core::poseidon::poseidon_hash_span;
use core::traits::DivRem;
use starknet::ContractAddress;
use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
use starknet::{get_contract_address, get_block_number, SyscallResultTrait};
use starknet::syscalls::{get_block_hash_syscall};

// External dependencies
use game_components_metagame::ticket_booth::{
    TicketBoothComponent, TicketBoothComponent::GoldenPass,
};
use openzeppelin_access::ownable::OwnableComponent;

// Local modules
mod interfaces;
mod structs;
mod vrf;

// Local VRF import
use vrf::{VRFImpl};

// Local imports
use interfaces::{
    IBeastSystemsDispatcher, IBeastSystemsDispatcherTrait, ILegacyBeastsDispatcher,
    ILegacyBeastsDispatcherTrait, CollectableResult,
};

// External interface imports
use beasts_nft::interfaces::{IBeastsDispatcher, IBeastsDispatcherTrait};
use openzeppelin_token::erc721::interface::{IERC721Dispatcher, IERC721DispatcherTrait};

#[starknet::contract]
pub mod beast_mode {
    use super::*;

    component!(path: TicketBoothComponent, storage: ticket_booth, event: TicketBoothEvent);
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl TicketBoothImpl = TicketBoothComponent::TicketBoothImpl<ContractState>;
    impl TicketBoothInternalImpl = TicketBoothComponent::InternalImpl<ContractState>;
    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        ticket_booth: TicketBoothComponent::Storage,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        game_collectable_address: ContractAddress,
        beast_nft_address: ContractAddress,
        legacy_beasts_address: ContractAddress,
        #[allow(starknet::colliding_storage_paths)]
        game_token_address: ContractAddress,
        #[allow(starknet::colliding_storage_paths)]
        opening_time: u64,
        airdrop_vrf_seed: felt252,
        airdrop_block_number: u64,
        airdrop_count: u16,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        TicketBoothEvent: TicketBoothComponent::Event,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
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
        golden_pass: Span<(ContractAddress, GoldenPass)>,
        ticket_receiver_address: ContractAddress,
        settings_id: u32,
        cost_to_play: u256,
    ) {
        // Initialize ownable component with deployer as owner
        self.ownable.initializer(starknet::get_caller_address());

        // Initialize storage
        self.game_collectable_address.write(game_collectable_address);
        self.beast_nft_address.write(beast_nft_address);
        self.legacy_beasts_address.write(legacy_beasts_address);
        self.game_token_address.write(game_token_address);
        self.opening_time.write(opening_time);

        self
            .ticket_booth
            .initializer(
                opening_time,
                game_token_address,
                payment_token,
                cost_to_play.try_into().unwrap(),
                ticket_receiver_address,
                Option::Some(game_token_address),
                Option::Some(settings_id),
                Option::Some(0), // start_time
                Option::Some(0), // expiration_time
                Option::Some("https://lootsurvivor.io"),
                Option::Some(renderer_address),
                Option::Some(golden_pass),
            );
    }

    #[external(v0)]
    fn claim_beast(
        ref self: ContractState, adventurer_id: u64, beast_id: u8, prefix: u8, suffix: u8,
    ) {
        // Read contract addresses
        let game_token_address = self.game_token_address.read();
        let game_collectable_address = self.game_collectable_address.read();
        let beast_nft_address = self.beast_nft_address.read();

        // Create dispatchers
        let beast_systems = IBeastSystemsDispatcher { contract_address: game_collectable_address };
        let beasts_nft = IBeastsDispatcher { contract_address: beast_nft_address };
        let game_token = IERC721Dispatcher { contract_address: game_token_address };

        // Calculate entity hash and validate collectable
        let entity_hash = beast_systems.get_beast_hash(beast_id, prefix, suffix);

        match beast_systems
            .get_valid_collectable(get_contract_address(), adventurer_id, entity_hash) {
            CollectableResult::Ok((
                seed, level, health,
            )) => {
                // Determine rare traits (4% chance each) using different parts of the seed
                // Use the lower 32 bits for shiny trait
                let shiny_seed = (seed & 0xFFFFFFFF_u64) % 10000_u64;
                let shiny = if shiny_seed < 400_u64 {
                    1_u8
                } else {
                    0_u8
                };

                // Use the upper 32 bits for animated trait
                let animated_seed = ((seed / 0x100000000_u64) & 0xFFFFFFFF_u64) % 10000_u64;
                let animated = if animated_seed < 400_u64 {
                    1_u8
                } else {
                    0_u8
                };

                // Mint the beast NFT
                beasts_nft
                    .mint(
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
    fn initiate_airdrop(ref self: ContractState) {
        let existing_block_number = self.airdrop_block_number.read();
        assert(existing_block_number == 0, 'Airdrop already initiated');

        // Get VRF seed
        let vrf_seed = VRFImpl::seed();
        self.airdrop_vrf_seed.write(vrf_seed);

        // Get block number
        let block_number = get_block_number() + 100;
        self.airdrop_block_number.write(block_number);

        // Set airdrop count to 75
        self.airdrop_count.write(75);
    }

    #[external(v0)]
    fn airdrop_legacy_beasts(ref self: ContractState, limit: u16) {
        let airdrop_block_number = self.airdrop_block_number.read();
        assert(airdrop_block_number != 0, 'Airdrop not initiated');

        let current_block_number = get_block_number();
        assert(current_block_number + 10 > airdrop_block_number, 'Airdrop not ready');

        // Get legacy beast data
        let legacy_beasts_dispatcher = ILegacyBeastsDispatcher {
            contract_address: self.legacy_beasts_address.read(),
        };

        // Increment airdrop counter
        let mut airdrop_count = self.airdrop_count.read();

        let vrf_seed = self.airdrop_vrf_seed.read();
        let block_seed = get_block_hash_syscall(airdrop_block_number).unwrap_syscall();

        let new_limit = airdrop_count + limit;
        let total_supply = legacy_beasts_dispatcher.totalSupply();

        while airdrop_count < new_limit && airdrop_count < total_supply.try_into().unwrap() {
            airdrop_count += 1;

            let airdrop_hash = poseidon_hash_span(
                [airdrop_count.into(), block_seed.into(), vrf_seed].span(),
            );
            let (_beast_seed, _) = felt_to_two_u64(airdrop_hash);

            let beast = legacy_beasts_dispatcher.getBeast(airdrop_count.into());

            // Save collectable entity
            let beast_systems = IBeastSystemsDispatcher {
                contract_address: self.game_collectable_address.read(),
            };
            let seed = beast_systems
                .premint_collectable(
                    beast.id, beast.prefix, beast.suffix, beast.level, beast.health,
                );

            // Determine rare traits (8% chance each) using different parts of the seed
            // Use the lower 32 bits for shiny trait
            let shiny_seed = (seed & 0xFFFFFFFF_u64) % 10000_u64;
            let shiny = if shiny_seed < 800_u64 {
                1_u8
            } else {
                0_u8
            };

            // Use the upper 32 bits for animated trait
            let animated_seed = ((seed / 0x100000000_u64) & 0xFFFFFFFF_u64) % 10000_u64;
            let animated = if animated_seed < 800_u64 {
                1_u8
            } else {
                0_u8
            };

            // Mint the beast NFT
            let beasts_nft = IBeastsDispatcher { contract_address: self.beast_nft_address.read() };
            beasts_nft
                .mint(
                    legacy_beasts_dispatcher.ownerOf(airdrop_count.into()),
                    beast.id,
                    beast.prefix,
                    beast.suffix,
                    beast.level,
                    beast.health,
                    shiny,
                    animated,
                );
        };

        self.airdrop_count.write(airdrop_count);
    }

    // Getter functions
    #[external(v0)]
    fn get_opening_time(self: @ContractState) -> u64 {
        self.opening_time.read()
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

    #[external(v0)]
    fn get_legacy_beasts_address(self: @ContractState) -> ContractAddress {
        self.legacy_beasts_address.read()
    }

    #[external(v0)]
    fn get_airdrop_count(self: @ContractState) -> u16 {
        self.airdrop_count.read()
    }

    #[external(v0)]
    fn get_airdrop_block_number(self: @ContractState) -> u64 {
        self.airdrop_block_number.read()
    }

    // Owner-only update functions
    #[external(v0)]
    fn update_opening_time(ref self: ContractState, new_opening_time: u64) {
        self.ownable.assert_only_owner();
        self.ticket_booth.update_opening_time_internal(new_opening_time);
    }

    #[external(v0)]
    fn update_payment_token(ref self: ContractState, new_payment_token: ContractAddress) {
        self.ownable.assert_only_owner();
        self.ticket_booth.update_payment_token_internal(new_payment_token);
    }

    #[external(v0)]
    fn update_ticket_receiver_address(
        ref self: ContractState, new_ticket_receiver_address: ContractAddress,
    ) {
        self.ownable.assert_only_owner();
        self.ticket_booth.update_ticket_receiver_address_internal(new_ticket_receiver_address);
    }

    #[external(v0)]
    fn update_settings_id(ref self: ContractState, new_settings_id: Option<u32>) {
        self.ownable.assert_only_owner();
        self.ticket_booth.update_settings_id_internal(new_settings_id);
    }

    #[external(v0)]
    fn update_cost_to_play(ref self: ContractState, new_cost_to_play: u128) {
        self.ownable.assert_only_owner();
        self.ticket_booth.update_cost_to_play_internal(new_cost_to_play);
    }

    fn felt_to_two_u64(value: felt252) -> (u64, u64) {
        let to_u256: u256 = value.try_into().unwrap();
        let (d, r) = DivRem::div_rem(to_u256.low, 0x10000000000000000);
        (d.try_into().unwrap(), r.try_into().unwrap())
    }
}
