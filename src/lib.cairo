use core::poseidon::poseidon_hash_span;
use core::traits::DivRem;
use starknet::ContractAddress;
use starknet::storage::{Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess};
use starknet::{get_contract_address, get_block_number, SyscallResultTrait};
use starknet::syscalls::{get_block_hash_syscall};

// External dependencies
use game_components_metagame::ticket_booth::{
    TicketBoothComponent, TicketBoothComponent::GoldenPass,
};
use openzeppelin_access::ownable::OwnableComponent;

// Local modules
pub mod interfaces;
pub mod structs;
pub mod data;

// Local imports
use interfaces::{
    IBeastSystemsDispatcher, IBeastSystemsDispatcherTrait, ILegacyBeastsDispatcher,
    ILegacyBeastsDispatcherTrait, DataResult, IAdventurerSystemsDispatcher,
    IAdventurerSystemsDispatcherTrait, IBeastModeDispatcher, IBeastModeDispatcherTrait,
};

// External interface imports
use game_components_minigame::interface::{IMinigameDispatcher, IMinigameDispatcherTrait};
use game_components_token::core::interface::{
    IMinigameTokenDispatcher, IMinigameTokenDispatcherTrait,
};
use beasts_nft::interfaces::{IBeastsDispatcher, IBeastsDispatcherTrait};
use openzeppelin_token::erc721::interface::{IERC721Dispatcher, IERC721DispatcherTrait};
use openzeppelin_token::erc20::interface::{
    IERC20Dispatcher, IERC20DispatcherTrait, IERC20SafeDispatcher, IERC20SafeDispatcherTrait,
};

// Survivor tokens locked in this contract
// LS1 beasts extra rewards: 69180 tokens
// Beast rewards: 931_500 tokens
// Reward pool: 2_258_100 tokens
// Total: 3,847,778 tokens

const REWARD_POOL: u32 = 2_258_100; // 2.25 million Survivor tokens
const REWARD_TOKEN_DECIMALS: u256 = 1_000_000_000_000_000_000; // 18 decimals
const MAX_FREE_GAMES: u32 = 586_000; // 586,000 free games

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
        adventurer_systems_address: ContractAddress,
        game_collectable_address: ContractAddress,
        legacy_beasts_address: ContractAddress,
        beast_nft_address: ContractAddress,
        free_games_duration: u64,
        free_games_claimer_address: ContractAddress,
        free_games_claimed: u32,
        reward_token: ContractAddress,
        reward_tokens_claimed: u32,
        adventurer_claimed_reward: Map<u64, bool>,
        airdrop_block_number: u64,
        beast_airdrop_count: u16,
        token_airdrop_count: u16,
        top_adventurer_airdrop_count: u16,
        bonus_duration: u64,
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
        game_token_address: ContractAddress,
        game_collectable_address: ContractAddress,
        adventurer_systems_address: ContractAddress,
        beast_nft_address: ContractAddress,
        legacy_beasts_address: ContractAddress,
        payment_token: ContractAddress,
        reward_token: ContractAddress,
        renderer_address: ContractAddress,
        golden_pass: Span<(ContractAddress, GoldenPass)>,
        ticket_receiver_address: ContractAddress,
        settings_id: u32,
        cost_to_play: u256,
        free_games_duration: u64,
        free_games_claimer_address: ContractAddress,
        bonus_duration: u64,
    ) {
        self.ownable.initializer(owner);

        // Initialize storage
        self.opening_time.write(opening_time);
        self.game_token_address.write(game_token_address);
        self.adventurer_systems_address.write(adventurer_systems_address);
        self.game_collectable_address.write(game_collectable_address);
        self.beast_nft_address.write(beast_nft_address);
        self.legacy_beasts_address.write(legacy_beasts_address);
        self.free_games_claimer_address.write(free_games_claimer_address);
        self.reward_token.write(reward_token);
        self.free_games_duration.write(free_games_duration);
        self.bonus_duration.write(bonus_duration);
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
                Option::None, // games start_time
                Option::None, // games expiration_time
                Option::Some("https://lootsurvivor.io"),
                Option::Some(renderer_address),
                Option::Some(golden_pass),
            );
    }

    #[external(v0)]
    fn claim_beast(
        ref self: ContractState, adventurer_id: u64, beast_id: u8, prefix: u8, suffix: u8,
    ) -> u256 {
        // Read contract addresses
        let game_token_address = self.game_token_address.read();
        let game_collectable_address = self.game_collectable_address.read();
        let beast_nft_address = self.beast_nft_address.read();

        // Create dispatchers
        let beast_systems = IBeastSystemsDispatcher { contract_address: game_collectable_address };
        let beasts_nft = IBeastsDispatcher { contract_address: beast_nft_address };
        let minigame = IMinigameDispatcher { contract_address: game_token_address };
        let game_token = IERC721Dispatcher { contract_address: minigame.token_address() };

        // Calculate entity hash and validate collectable
        let entity_hash = beast_systems.get_beast_hash(beast_id, prefix, suffix);

        match beast_systems
            .get_valid_collectable(get_contract_address(), adventurer_id, entity_hash) {
            DataResult::Ok((
                seed, level, health,
            )) => {
                // Determine rare traits (5% chance each) using different parts of the seed
                // Use the lower 32 bits for shiny trait
                let shiny_seed = (seed & 0xFFFFFFFF_u64) % 10000_u64;
                let shiny = if shiny_seed < 500_u64 {
                    1_u8
                } else {
                    0_u8
                };

                // Use the upper 32 bits for animated trait
                let animated_seed = ((seed / 0x100000000_u64) & 0xFFFFFFFF_u64) % 10000_u64;
                let animated = if animated_seed < 500_u64 {
                    1_u8
                } else {
                    0_u8
                };

                let owner = game_token.owner_of(adventurer_id.into());

                // Mint the beast NFT
                let token_id: u256 = beasts_nft
                    .mint(owner, beast_id, prefix, suffix, level, health, shiny, animated);

                // Transfer beast reward tokens
                let reward_amount = get_beast_reward_amount(beast_id);
                let reward_token = IERC20SafeDispatcher {
                    contract_address: self.reward_token.read(),
                };
                let _transfer_result = reward_token
                    .transfer(owner, reward_amount.into() * REWARD_TOKEN_DECIMALS);

                token_id
            },
            DataResult::Err(_e) => {
                core::panic_with_felt252('Invalid collectable'.into());
                0
            },
        }
    }

    #[external(v0)]
    fn initiate_airdrop(ref self: ContractState) {
        self.ownable.assert_only_owner();

        let existing_block_number = self.airdrop_block_number.read();
        assert(existing_block_number == 0, 'Airdrop already initiated');

        // Get block number
        let beast_mode = IBeastModeDispatcher {
            contract_address: 0x04a346df886993b0ab17f1d5ae2dd203313484bbead83fdc404c55b237c42d43
                .try_into()
                .unwrap(),
        };
        let block_number = beast_mode.get_airdrop_block_number();
        self.airdrop_block_number.write(block_number);

        // Set airdrop count to 75
        self.beast_airdrop_count.write(75);
        self.token_airdrop_count.write(75);
    }

    #[external(v0)]
    fn airdrop_legacy_beasts(ref self: ContractState, limit: u16) {
        self.ownable.assert_only_owner();

        let airdrop_block_number = self.airdrop_block_number.read();
        assert(airdrop_block_number != 0, 'Airdrop not initiated');

        let current_block_number = get_block_number();
        assert(current_block_number + 10 > airdrop_block_number, 'Airdrop not ready');

        // Get legacy beast data
        let legacy_beasts_dispatcher = ILegacyBeastsDispatcher {
            contract_address: self.legacy_beasts_address.read(),
        };
        let total_supply = legacy_beasts_dispatcher.tokenSupply();

        let mut beast_airdrop_count = self.beast_airdrop_count.read();
        assert(beast_airdrop_count.into() < total_supply, 'All beasts airdropped');

        let block_seed = get_block_hash_syscall(airdrop_block_number).unwrap_syscall();

        let new_limit = beast_airdrop_count + limit;

        while beast_airdrop_count < new_limit
            && beast_airdrop_count < total_supply.try_into().unwrap() {
            beast_airdrop_count += 1;

            let airdrop_hash = poseidon_hash_span(
                [beast_airdrop_count.into(), block_seed.into()].span(),
            );
            let (beast_seed, _) = felt_to_two_u64(airdrop_hash);

            let beast = legacy_beasts_dispatcher.getBeast(beast_airdrop_count.into());

            // Save collectable entity
            let beast_systems = IBeastSystemsDispatcher {
                contract_address: self.game_collectable_address.read(),
            };
            beast_systems
                .premint_collectable(
                    beast_seed, beast.id, beast.prefix, beast.suffix, beast.level, beast.health,
                );

            let beasts_nft = IBeastsDispatcher { contract_address: self.beast_nft_address.read() };
            if beast_airdrop_count.into() <= beasts_nft.total_supply() {
                continue;
            }

            // Determine rare traits (10% chance each) using different parts of the seed
            // Use the lower 32 bits for shiny trait
            let shiny_seed = (beast_seed & 0xFFFFFFFF_u64) % 10000_u64;
            let shiny = if shiny_seed < 1000_u64 {
                1_u8
            } else {
                0_u8
            };

            // Use the upper 32 bits for animated trait
            let animated_seed = ((beast_seed / 0x100000000_u64) & 0xFFFFFFFF_u64) % 10000_u64;
            let animated = if animated_seed < 1000_u64 {
                1_u8
            } else {
                0_u8
            };

            // Mint the beast NFT
            beasts_nft
                .mint(
                    legacy_beasts_dispatcher.ownerOf(beast_airdrop_count.into()),
                    beast.id,
                    beast.prefix,
                    beast.suffix,
                    beast.level,
                    beast.health,
                    shiny,
                    animated,
                );
        };

        self.beast_airdrop_count.write(beast_airdrop_count);
    }

    #[external(v0)]
    fn airdrop_legacy_beast_reward_tokens(ref self: ContractState, limit: u16) {
        self.ownable.assert_only_owner();

        let mut token_airdrop_count = self.token_airdrop_count.read();
        assert(token_airdrop_count < self.beast_airdrop_count.read(), 'All tokens airdropped');

        let legacy_beasts_dispatcher = ILegacyBeastsDispatcher {
            contract_address: self.legacy_beasts_address.read(),
        };
        let new_limit = token_airdrop_count + limit;

        while token_airdrop_count < new_limit
            && token_airdrop_count < self.beast_airdrop_count.read() {
            token_airdrop_count += 1;

            let beast = legacy_beasts_dispatcher.getBeast(token_airdrop_count.into());

            let mut reward_amount = get_beast_reward_amount(beast.id);
            // Add 108 to the reward for LS1 beasts
            if (token_airdrop_count <= 2381) {
                reward_amount += 108;
            } else {
                reward_amount += 36;
            }
            let reward_token = IERC20Dispatcher { contract_address: self.reward_token.read() };
            reward_token
                .transfer(
                    legacy_beasts_dispatcher.ownerOf(token_airdrop_count.into()),
                    reward_amount.into() * REWARD_TOKEN_DECIMALS,
                );
        };

        self.token_airdrop_count.write(token_airdrop_count);
    }

    #[external(v0)]
    fn airdrop_top_legacy_adventurers(ref self: ContractState, limit: u16) {
        self.ownable.assert_only_owner();

        let mut airdrop_count = self.top_adventurer_airdrop_count.read();
        assert(airdrop_count < 1000, 'All top adventurers airdropped');

        let erc721 = IERC721Dispatcher {
            contract_address: 0x018108b32cea514a78ef1b0e4a0753e855cdf620bc0565202c02456f618c4dc4
                .try_into()
                .unwrap(),
        };
        let new_limit = airdrop_count + limit;

        while airdrop_count < new_limit && airdrop_count < 1000 {
            let adventurer_id = *data::top_adventurer_ids().at(airdrop_count.into());

            let position = airdrop_count + 1;
            let mut reward_amount = get_top_adventurer_reward_amount(position);

            let reward_token = IERC20Dispatcher { contract_address: self.reward_token.read() };
            reward_token
                .transfer(
                    erc721.owner_of(adventurer_id.into()),
                    reward_amount.into() * REWARD_TOKEN_DECIMALS,
                );

            airdrop_count += 1;
        };

        self.top_adventurer_airdrop_count.write(airdrop_count);
    }

    #[external(v0)]
    fn claim_reward_token(ref self: ContractState, token_id: u64) {
        let reward_tokens_claimed = self.reward_tokens_claimed.read();
        assert(reward_tokens_claimed < REWARD_POOL, 'All tokens claimed');

        // Check if adventurer has already claimed
        let already_claimed = self.adventurer_claimed_reward.entry(token_id).read();
        assert!(!already_claimed, "Token already claimed");

        // Check adventurer is from beast mode dungeon
        let adventurer_systems_address = self.adventurer_systems_address.read();
        let adventurer_systems = IAdventurerSystemsDispatcher {
            contract_address: adventurer_systems_address,
        };
        let dungeon = adventurer_systems.get_adventurer_dungeon(token_id);
        assert!(dungeon == get_contract_address(), "Adventurer not from beast mode dungeon");

        // Check adventurer health
        let health = adventurer_systems.get_adventurer_health(token_id);
        assert!(health == 0, "Adventurer must be dead");

        // Get adventurer level to determine reward amount
        let mut level: u16 = adventurer_systems.get_adventurer_level(token_id).into();
        assert!(level > 2, "Adventurer must be level 3 or higher");

        // Cap at level 50
        if level > 50 {
            level = 50;
        }

        // Double reward after opening week
        let minigame = IMinigameDispatcher { contract_address: self.game_token_address.read() };
        let token_metadata = IMinigameTokenDispatcher { contract_address: minigame.token_address() }
            .token_metadata(token_id);
        if token_metadata.minted_at >= self.opening_time.read()
            + self.free_games_duration.read()
            + self.bonus_duration.read() {
            level *= 2;
        } else if token_metadata.minted_at >= self.opening_time.read()
            + self.free_games_duration.read() {
            level *= 4;
        }

        // Use the smaller of level or available rewards
        let reward_amount: u32 = if level.into() + reward_tokens_claimed <= REWARD_POOL {
            level.into()
        } else {
            REWARD_POOL - reward_tokens_claimed
        };

        // Transfer reward tokens to the token owner
        let game_token = IERC721Dispatcher { contract_address: minigame.token_address() };
        let token_owner = game_token.owner_of(token_id.into());

        let reward_token = IERC20Dispatcher { contract_address: self.reward_token.read() };
        reward_token.transfer(token_owner, reward_amount.into() * REWARD_TOKEN_DECIMALS);

        // Mark token_id has claimed
        self.adventurer_claimed_reward.entry(token_id).write(true);

        // Update reward tokens claimed
        self.reward_tokens_claimed.write(reward_tokens_claimed + reward_amount);
    }

    #[external(v0)]
    fn claim_free_game(
        ref self: ContractState, to: ContractAddress, player_name: Option<felt252>,
    ) -> u64 {
        assert(
            starknet::get_caller_address() == self.free_games_claimer_address.read(), 'Not Allowed',
        );
        assert(self.free_games_claimed.read() < MAX_FREE_GAMES, 'All free games claimed');

        let opening_time = self.opening_time.read();
        let current_time = starknet::get_block_timestamp();
        let claim_expiration = opening_time + self.free_games_duration.read();
        assert(current_time < claim_expiration, 'Opening campaign has ended');

        let token_id = self
            .ticket_booth
            .mint_game(
                player_name, to, false, Option::Some(opening_time), Option::Some(claim_expiration),
            );

        self.free_games_claimed.write(self.free_games_claimed.read() + 1);

        token_id
    }

    #[external(v0)]
    fn claim_jackpot(ref self: ContractState, token_id: u64) {
        let already_claimed = self.jackpot_claimed.entry(token_id).read();
        assert!(!already_claimed, "Token already claimed");

        // Check token owner
        let caller = starknet::get_caller_address();
        let erc721 = IERC721Dispatcher { contract_address: self.beast_nft_address.read() };
        let token_owner = erc721.owner_of(token_id.into());
        assert(caller == token_owner, 'Not token owner');

        let beasts = IBeastsDispatcher { contract_address: self.beast_nft_address.read() };
        let beast = beasts.get_beast(token_id.into());
        if (beast.id == 29) {
            assert(beast.prefix == 18, 'Not demon');
            assert(beast.suffix == 6, 'Not grasp');
        } else if (beast.id == 1) {
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
    fn update_free_games_claimer_address(
        ref self: ContractState, new_free_games_claimer_address: ContractAddress,
    ) {
        self.ownable.assert_only_owner();
        self.free_games_claimer_address.write(new_free_games_claimer_address);
    }

    #[external(v0)]
    fn withdraw_funds(ref self: ContractState, token_address: ContractAddress, amount: u256) {
        self.ownable.assert_only_owner();
        let token = IERC20Dispatcher { contract_address: token_address };
        token.transfer(self.ownable.Ownable_owner.read(), amount);
    }

    // Getter functions
    #[external(v0)]
    fn get_free_games_duration(self: @ContractState) -> u64 {
        self.free_games_duration.read()
    }

    #[external(v0)]
    fn get_bonus_duration(self: @ContractState) -> u64 {
        self.bonus_duration.read()
    }

    #[external(v0)]
    fn get_free_games_claimer_address(self: @ContractState) -> ContractAddress {
        self.free_games_claimer_address.read()
    }

    #[external(v0)]
    fn get_free_games_claimed(self: @ContractState) -> u32 {
        self.free_games_claimed.read()
    }

    #[external(v0)]
    fn get_reward_tokens_claimed(self: @ContractState) -> u32 {
        self.reward_tokens_claimed.read()
    }

    #[external(v0)]
    fn get_reward_token_address(self: @ContractState) -> ContractAddress {
        self.reward_token.read()
    }

    #[external(v0)]
    fn get_game_collectable_address(self: @ContractState) -> ContractAddress {
        self.game_collectable_address.read()
    }

    #[external(v0)]
    fn get_game_token_address(self: @ContractState) -> ContractAddress {
        self.game_token_address.read()
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
    fn get_beast_airdrop_count(self: @ContractState) -> u16 {
        self.beast_airdrop_count.read()
    }

    #[external(v0)]
    fn get_airdrop_block_number(self: @ContractState) -> u64 {
        self.airdrop_block_number.read()
    }

    #[external(v0)]
    fn has_adventurer_claimed_reward(self: @ContractState, token_id: u64) -> bool {
        self.adventurer_claimed_reward.entry(token_id).read()
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

    fn get_top_adventurer_reward_amount(position: u16) -> u16 {
        if (position == 1) {
            25000
        } else if (position == 2) {
            10000
        } else if (position == 3) {
            5150
        } else if (position <= 10) {
            3000
        } else if (position <= 50) {
            2000
        } else if (position <= 100) {
            1000
        } else {
            150
        }
    }
}
