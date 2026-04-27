use core::hash::HashStateTrait;
use core::poseidon::PoseidonTrait;
use core::traits::DivRem;
use game_components_metagame::ticket_booth::structs::GoldenPass;

// External dependencies
use game_components_metagame::ticket_booth::ticket_booth_component::TicketBoothComponent;
use openzeppelin_access::ownable::OwnableComponent;
use starknet::storage::{Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess};
use starknet::{ContractAddress, get_contract_address};

// Local modules
pub mod interfaces;
pub mod structs;
use beasts_nft::interfaces::{IBeastsDispatcher, IBeastsDispatcherTrait};
use game_components_embeddable_game_standard::token::structs::unpack_minted_by;

// External interface imports
use game_components_interfaces::{IMinigameTokenDispatcher, IMinigameTokenDispatcherTrait};

// Local imports
use interfaces::{IGameCoreSystemsDispatcher, IGameCoreSystemsDispatcherTrait};
use openzeppelin_interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
use openzeppelin_interfaces::erc721::{IERC721Dispatcher, IERC721DispatcherTrait};

const REWARD_TOKEN_DECIMALS: u256 = 1_000_000_000_000_000_000;

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
        #[allow(starknet::colliding_storage_paths)]
        opening_time: u64,
        #[allow(starknet::colliding_storage_paths)]
        game_token_address: ContractAddress,
        #[allow(starknet::colliding_storage_paths)]
        denshokan_address: ContractAddress,
        game_core_address: ContractAddress,
        beasts_nft_address: ContractAddress,
        reward_token: ContractAddress,
        jackpot_claimed: Map<u64, bool>,
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
        owner: ContractAddress,
        opening_time: u64,
        denshokan_address: ContractAddress,
        game_token_address: ContractAddress,
        game_core_address: ContractAddress,
        beasts_nft_address: ContractAddress,
        payment_token: ContractAddress,
        reward_token: ContractAddress,
        golden_pass: Span<(ContractAddress, GoldenPass)>,
        ticket_receiver_address: ContractAddress,
        settings_id: u32,
        cost_to_play: u256,
    ) {
        self.ownable.initializer(owner);

        // Initialize storage
        self.opening_time.write(opening_time);
        self.game_token_address.write(game_token_address);
        self.game_core_address.write(game_core_address);
        self.beasts_nft_address.write(beasts_nft_address);
        self.reward_token.write(reward_token);
        self.denshokan_address.write(denshokan_address);
        self
            .ticket_booth
            .initializer(
                opening_time,
                denshokan_address,
                game_token_address,
                payment_token,
                cost_to_play.try_into().unwrap(),
                ticket_receiver_address,
                Option::Some(game_token_address),
                Option::Some(settings_id),
                Option::None, // games start_time
                Option::None, // games expiration_time
                Option::Some(golden_pass),
            );
    }

    #[external(v0)]
    fn claim_beast(
        ref self: ContractState, adventurer_id: felt252, beast_id: u8, prefix: u8, suffix: u8,
    ) -> u256 {
        // Read contract addresses
        let game_core_address = self.game_core_address.read();
        let beasts_nft_address = self.beasts_nft_address.read();
        let denshokan_address = self.denshokan_address.read();

        // Create dispatchers
        let game_core_systems = IGameCoreSystemsDispatcher { contract_address: game_core_address };
        let beasts_nft = IBeastsDispatcher { contract_address: beasts_nft_address };
        let game_token = IERC721Dispatcher { contract_address: denshokan_address };
        let denshokan = IMinigameTokenDispatcher { contract_address: denshokan_address };

        // Verify adventurer was minted by this dungeon
        let minted_by_address = denshokan.minted_by_address(adventurer_id);
        assert(minted_by_address == get_contract_address(), 'Not beast mode');

        // Compute collectable_id from beast params and adventurer's minted_by
        let minted_by = unpack_minted_by(adventurer_id);
        let beast_hash = PoseidonTrait::new()
            .update(beast_id.into())
            .update(prefix.into())
            .update(suffix.into())
            .finalize();
        let collectable_id = PoseidonTrait::new()
            .update(minted_by.into())
            .update(beast_hash)
            .finalize();

        let collectable = game_core_systems.get_collectable(collectable_id);
        let expected_collected_by = create_collected_by(adventurer_id);
        assert(collectable.collected_by == expected_collected_by, 'Not your collectable');

        let owner = game_token.owner_of(adventurer_id.into());

        // Mint the beast NFT
        let (token_id, _, _): (u256, u16, bool) = beasts_nft
            .mint(
                owner,
                beast_id,
                prefix,
                suffix,
                collectable.level,
                collectable.health,
                collectable.shiny,
                collectable.animated,
            );

        // Transfer beast reward tokens
        let reward_amount = get_beast_reward_amount(beast_id);
        let reward_token = IERC20Dispatcher { contract_address: self.reward_token.read() };
        reward_token.transfer(owner, reward_amount.into() * REWARD_TOKEN_DECIMALS);

        token_id
    }

    #[external(v0)]
    fn claim_jackpot(ref self: ContractState, token_id: u64) {
        let already_claimed = self.jackpot_claimed.entry(token_id).read();
        assert!(!already_claimed, "Token already claimed");

        // Check token owner
        let caller = starknet::get_caller_address();
        let erc721 = IERC721Dispatcher { contract_address: self.beasts_nft_address.read() };
        let token_owner = erc721.owner_of(token_id.into());
        assert(caller == token_owner, 'Not token owner');

        let beasts = IBeastsDispatcher { contract_address: self.beasts_nft_address.read() };
        let beast = beasts.get_beast(token_id.into());
        if (beast.id == 1) {
            assert(beast.prefix == 47, 'Not pain');
            assert(beast.suffix == 11, 'Not whisper');
        } else if (beast.id == 53) {
            assert(beast.prefix == 61, 'Not torment');
            assert(beast.suffix == 1, 'Not bane');
        } else {
            panic!("Invalid beast");
        }

        // Transfer jackpot amount to the caller
        let erc20 = IERC20Dispatcher {
            contract_address: 0x04718f5a0Fc34cC1AF16A1cdee98fFB20C31f5cD61D6Ab07201858f4287c938D
                .try_into()
                .unwrap(),
        };
        let amount = 33333 * REWARD_TOKEN_DECIMALS;
        erc20.transfer(token_owner, amount);
        self.jackpot_claimed.entry(token_id).write(true);
    }

    #[external(v0)]
    fn withdraw_funds(ref self: ContractState, token_address: ContractAddress, amount: u256) {
        self.ownable.assert_only_owner();
        let token = IERC20Dispatcher { contract_address: token_address };
        token.transfer(self.ownable.Ownable_owner.read(), amount);
    }

    #[external(v0)]
    fn get_game_core_address(self: @ContractState) -> ContractAddress {
        self.game_core_address.read()
    }

    #[external(v0)]
    fn get_game_token_address(self: @ContractState) -> ContractAddress {
        self.game_token_address.read()
    }

    #[external(v0)]
    fn get_beasts_nft_address(self: @ContractState) -> ContractAddress {
        self.beasts_nft_address.read()
    }

    #[external(v0)]
    fn jackpot_claimed(self: @ContractState, token_id: u64) -> bool {
        self.jackpot_claimed.entry(token_id).read()
    }

    #[external(v0)]
    fn dungeon_opening_time(self: @ContractState) -> u64 {
        self.opening_time.read()
    }

    // Owner-only update functions
    #[external(v0)]
    fn update_opening_time(ref self: ContractState, new_opening_time: u64) {
        self.ownable.assert_only_owner();
        self.opening_time.write(new_opening_time);
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

    fn get_beast_reward_amount(id: u8) -> u8 {
        if (id >= 1 && id <= 5) || (id >= 26 && id < 31) || (id >= 51 && id < 56) {
            14
        } else if (id >= 6 && id < 11) || (id >= 31 && id < 36) || (id >= 56 && id < 61) {
            12
        } else if (id >= 11 && id < 16) || (id >= 36 && id < 41) || (id >= 61 && id < 66) {
            10
        } else if (id >= 16 && id < 21) || (id >= 41 && id < 46) || (id >= 66 && id < 71) {
            8
        } else {
            6
        }
    }
    use game_components_embeddable_game_standard::token::structs::{
        unpack_minted_at, unpack_salt, unpack_tx_hash,
    };

    // Constants for create_collected_by
    const COLLECTED_BY_TWO_POW_35: u64 = 0x800000000;
    const COLLECTED_BY_TWO_POW_45: u64 = 0x200000000000;

    pub fn create_collected_by(adventurer_id: felt252) -> u64 {
        let minted_at: u64 = unpack_minted_at(adventurer_id);
        let tx_hash: u64 = unpack_tx_hash(adventurer_id).into();
        let salt: u64 = unpack_salt(adventurer_id).into();
        minted_at + (tx_hash * COLLECTED_BY_TWO_POW_35) + (salt * COLLECTED_BY_TWO_POW_45)
    }
}
