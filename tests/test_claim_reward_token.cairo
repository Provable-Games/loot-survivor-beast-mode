#[cfg(test)]
mod test_claim_reward_token {
    use starknet::{ContractAddress, contract_address_const};
    use snforge_std::{
        declare, ContractClassTrait, DeclareResultTrait, cheat_caller_address,
        stop_cheat_caller_address, mock_call
    };
    use core::serde::Serde;
    use core::traits::Into;
    use core::array::ArrayTrait;
    
    // Import interfaces
    use beast_mode::interfaces::{
        IBeastModeDispatcher, IBeastModeDispatcherTrait,
        IAdventurerSystemsDispatcher, IAdventurerSystemsDispatcherTrait,
        DataResult
    };

    // Test constants
    const OWNER_ADDRESS: felt252 = 0x123456789;
    const PLAYER_ADDRESS: felt252 = 0x987654321;
    const TOKEN_ID: u64 = 12345;
    const ADVENTURER_LEVEL: u16 = 50;
    
    // Contract addresses
    const GAME_ADVENTURER_ADDRESS: felt252 = 0x789;
    const GAME_TOKEN_ADDRESS: felt252 = 0xdef;
    const REWARD_TOKEN_ADDRESS: felt252 = 0xabc;
    const BEAST_SYSTEMS_ADDRESS: felt252 = 0x456;
    const BEASTS_NFT_ADDRESS: felt252 = 0xabc;
    const LEGACY_BEASTS_ADDRESS: felt252 = 0x567;
    const PAYMENT_TOKEN_ADDRESS: felt252 = 0x888;
    const RENDERER_ADDRESS: felt252 = 0x999;
    const TICKET_RECEIVER_ADDRESS: felt252 = 0xaaa;
    
    const OPENING_TIME: u64 = 1000000;
    const COST_TO_PLAY: u256 = 1000;
    const SETTINGS_ID: u32 = 1;

    // Mock contract implementations
    #[starknet::contract]
    mod MockGameToken {
        use starknet::ContractAddress;
        use openzeppelin_token::erc721::interface::IERC721;

        #[storage]
        struct Storage {
            owners: LegacyMap<u256, ContractAddress>,
        }

        #[abi(embed_v0)]
        impl GameTokenImpl of openzeppelin_token::erc721::interface::IERC721<ContractState> {
            fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
                0
            }
            
            fn owner_of(self: @ContractState, token_id: u256) -> ContractAddress {
                self.owners.read(token_id)
            }
            
            fn safe_transfer_from(
                ref self: ContractState,
                from: ContractAddress,
                to: ContractAddress,
                token_id: u256,
                data: Span<felt252>
            ) {
                // Not implemented for test
            }
            
            fn transfer_from(
                ref self: ContractState,
                from: ContractAddress,
                to: ContractAddress,
                token_id: u256
            ) {
                // Not implemented for test
            }
            
            fn approve(ref self: ContractState, to: ContractAddress, token_id: u256) {
                // Not implemented for test
            }
            
            fn set_approval_for_all(ref self: ContractState, operator: ContractAddress, approved: bool) {
                // Not implemented for test
            }
            
            fn get_approved(self: @ContractState, token_id: u256) -> ContractAddress {
                starknet::contract_address_const::<0>()
            }
            
            fn is_approved_for_all(self: @ContractState, owner: ContractAddress, operator: ContractAddress) -> bool {
                false
            }
        }

        #[external(v0)]
        fn set_owner(ref self: ContractState, token_id: u256, owner: ContractAddress) {
            self.owners.write(token_id, owner);
        }
    }

    #[starknet::contract]
    mod MockRewardToken {
        use starknet::ContractAddress;
        use openzeppelin_token::erc20::interface::IERC20;

        #[storage]
        struct Storage {
            balances: LegacyMap<ContractAddress, u256>,
        }

        #[abi(embed_v0)]
        impl RewardTokenImpl of openzeppelin_token::erc20::interface::IERC20<ContractState> {
            fn total_supply(self: @ContractState) -> u256 {
                1000000
            }
            
            fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
                self.balances.read(account)
            }
            
            fn allowance(self: @ContractState, owner: ContractAddress, spender: ContractAddress) -> u256 {
                0
            }
            
            fn transfer(ref self: ContractState, recipient: ContractAddress, amount: u256) -> bool {
                let caller = starknet::get_caller_address();
                let current_balance = self.balances.read(caller);
                assert(current_balance >= amount, 'Insufficient balance');
                
                self.balances.write(caller, current_balance - amount);
                let recipient_balance = self.balances.read(recipient);
                self.balances.write(recipient, recipient_balance + amount);
                true
            }
            
            fn transfer_from(
                ref self: ContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256,
            ) -> bool {
                // Not implemented for test
                false
            }
            
            fn approve(ref self: ContractState, spender: ContractAddress, amount: u256) -> bool {
                // Not implemented for test
                false
            }
        }

        #[external(v0)]
        fn set_balance(ref self: ContractState, account: ContractAddress, balance: u256) {
            self.balances.write(account, balance);
        }
    }

    #[starknet::contract]
    mod MockAdventurerSystems {
        use starknet::ContractAddress;
        use beast_mode::interfaces::DataResult;

        #[storage]
        struct Storage {
            levels: LegacyMap<u64, u16>,
        }

        #[abi(embed_v0)]
        impl AdventurerSystemsImpl of beast_mode::interfaces::IAdventurerSystems<ContractState> {
            fn get_adventurer_level(
                self: @ContractState, dungeon: ContractAddress, adventurer_id: u64
            ) -> DataResult {
                let level = self.levels.read(adventurer_id);
                DataResult::Ok((0, level, 100)) // seed, level, health
            }
        }

        #[external(v0)]
        fn set_level(ref self: ContractState, adventurer_id: u64, level: u16) {
            self.levels.write(adventurer_id, level);
        }
    }

    // Helper functions
    fn deploy_mock_game_token() -> ContractAddress {
        let contract = declare("MockGameToken").unwrap().contract_class();
        let (contract_address, _) = contract.deploy(@ArrayTrait::new()).unwrap();
        contract_address
    }
    
    fn deploy_mock_reward_token() -> ContractAddress {
        let contract = declare("MockRewardToken").unwrap().contract_class();
        let (contract_address, _) = contract.deploy(@ArrayTrait::new()).unwrap();
        contract_address
    }
    
    fn deploy_mock_adventurer_systems() -> ContractAddress {
        let contract = declare("MockAdventurerSystems").unwrap().contract_class();
        let (contract_address, _) = contract.deploy(@ArrayTrait::new()).unwrap();
        contract_address
    }
    
    fn deploy_beast_mode_contract(
        game_token_addr: ContractAddress,
        reward_token_addr: ContractAddress,
        adventurer_systems_addr: ContractAddress
    ) -> ContractAddress {
        let contract = declare("beast_mode").unwrap().contract_class();
        
        let mut constructor_calldata = array![];
        OPENING_TIME.serialize(ref constructor_calldata);
        game_token_addr.serialize(ref constructor_calldata);
        contract_address_const::<BEAST_SYSTEMS_ADDRESS>().serialize(ref constructor_calldata);
        adventurer_systems_addr.serialize(ref constructor_calldata);
        contract_address_const::<BEASTS_NFT_ADDRESS>().serialize(ref constructor_calldata);
        contract_address_const::<LEGACY_BEASTS_ADDRESS>().serialize(ref constructor_calldata);
        contract_address_const::<PAYMENT_TOKEN_ADDRESS>().serialize(ref constructor_calldata);
        reward_token_addr.serialize(ref constructor_calldata);
        contract_address_const::<RENDERER_ADDRESS>().serialize(ref constructor_calldata);
        
        // Golden pass - empty for tests
        let golden_pass: Array<felt252> = ArrayTrait::new();
        golden_pass.span().serialize(ref constructor_calldata);
        
        contract_address_const::<TICKET_RECEIVER_ADDRESS>().serialize(ref constructor_calldata);
        SETTINGS_ID.serialize(ref constructor_calldata);
        COST_TO_PLAY.serialize(ref constructor_calldata);
        
        cheat_caller_address(contract_address_const::<0>(), contract_address_const::<OWNER_ADDRESS>());
        let (contract_address, _) = contract.deploy(@constructor_calldata).unwrap();
        stop_cheat_caller_address(contract_address_const::<0>());
        
        contract_address
    }

    #[test]
    fn test_claim_reward_token_success() {
        // Deploy mock contracts
        let game_token_addr = deploy_mock_game_token();
        let reward_token_addr = deploy_mock_reward_token();
        let adventurer_systems_addr = deploy_mock_adventurer_systems();
        let beast_mode_addr = deploy_beast_mode_contract(game_token_addr, reward_token_addr, adventurer_systems_addr);
        
        // Setup mock contracts
        let game_token = MockGameToken::contract_address_for_contract_address(game_token_addr);
        let reward_token = MockRewardToken::contract_address_for_contract_address(reward_token_addr);
        let adventurer_systems = MockAdventurerSystems::contract_address_for_contract_address(adventurer_systems_addr);
        let beast_mode = IBeastModeDispatcher { contract_address: beast_mode_addr };
        
        // Set up the test scenario
        game_token.set_owner(TOKEN_ID.into(), contract_address_const::<PLAYER_ADDRESS>());
        adventurer_systems.set_level(TOKEN_ID, ADVENTURER_LEVEL);
        reward_token.set_balance(beast_mode_addr, 1000000000000000000000); // Contract has enough tokens for level 50 * 10^18
        
        // Mock the adventurer systems call
        mock_call(
            adventurer_systems_addr,
            "get_adventurer_level",
            array![beast_mode_addr.into(), TOKEN_ID.into()],
            array![0, ADVENTURER_LEVEL.into(), 100] // seed, level, health
        );
        
        // Mock the game token owner call
        mock_call(
            game_token_addr,
            "owner_of",
            array![TOKEN_ID.into()],
            array![contract_address_const::<PLAYER_ADDRESS>()]
        );
        
        // Mock the reward token balance call
        mock_call(
            reward_token_addr,
            "balance_of",
            array![beast_mode_addr.into()],
            array![1000000000000000000000]
        );
        
        // Mock the reward token transfer call (level * 10^18)
        mock_call(
            reward_token_addr,
            "transfer",
            array![contract_address_const::<PLAYER_ADDRESS>(), (ADVENTURER_LEVEL * 1000000000000000000_u256).into()],
            array![true]
        );
        
        // Set caller as the player
        cheat_caller_address(contract_address_const::<0>(), contract_address_const::<PLAYER_ADDRESS>());
        
        // Call claim_reward_token
        beast_mode.claim_reward_token(TOKEN_ID);
        
        stop_cheat_caller_address(contract_address_const::<0>());
    }

    #[test]
    #[should_panic(expected: ('Not token owner',))]
    fn test_claim_reward_token_not_owner() {
        // Deploy mock contracts
        let game_token_addr = deploy_mock_game_token();
        let reward_token_addr = deploy_mock_reward_token();
        let adventurer_systems_addr = deploy_mock_adventurer_systems();
        let beast_mode_addr = deploy_beast_mode_contract(game_token_addr, reward_token_addr, adventurer_systems_addr);
        
        // Setup mock contracts
        let game_token = MockGameToken::contract_address_for_contract_address(game_token_addr);
        let beast_mode = IBeastModeDispatcher { contract_address: beast_mode_addr };
        
        // Set up the test scenario - token owned by different address
        game_token.set_owner(TOKEN_ID.into(), contract_address_const::<0x111111111>());
        
        // Mock the game token owner call
        mock_call(
            game_token_addr,
            "owner_of",
            array![TOKEN_ID.into()],
            array![contract_address_const::<0x111111111>()]
        );
        
        // Set caller as different player
        cheat_caller_address(contract_address_const::<0>(), contract_address_const::<PLAYER_ADDRESS>());
        
        // Call claim_reward_token - should fail
        beast_mode.claim_reward_token(TOKEN_ID);
        
        stop_cheat_caller_address(contract_address_const::<0>());
    }

    #[test]
    #[should_panic(expected: ('Invalid adventurer',))]
    fn test_claim_reward_token_invalid_adventurer() {
        // Deploy mock contracts
        let game_token_addr = deploy_mock_game_token();
        let reward_token_addr = deploy_mock_reward_token();
        let adventurer_systems_addr = deploy_mock_adventurer_systems();
        let beast_mode_addr = deploy_beast_mode_contract(game_token_addr, reward_token_addr, adventurer_systems_addr);
        
        // Setup mock contracts
        let game_token = MockGameToken::contract_address_for_contract_address(game_token_addr);
        let beast_mode = IBeastModeDispatcher { contract_address: beast_mode_addr };
        
        // Set up the test scenario
        game_token.set_owner(TOKEN_ID.into(), contract_address_const::<PLAYER_ADDRESS>());
        
        // Mock the game token owner call
        mock_call(
            game_token_addr,
            "owner_of",
            array![TOKEN_ID.into()],
            array![contract_address_const::<PLAYER_ADDRESS>()]
        );
        
        // Mock the adventurer systems call to return error
        mock_call(
            adventurer_systems_addr,
            "get_adventurer_level",
            array![beast_mode_addr.into(), TOKEN_ID.into()],
            array![1] // Error result
        );
        
        // Set caller as the player
        cheat_caller_address(contract_address_const::<0>(), contract_address_const::<PLAYER_ADDRESS>());
        
        // Call claim_reward_token - should fail
        beast_mode.claim_reward_token(TOKEN_ID);
        
        stop_cheat_caller_address(contract_address_const::<0>());
    }

    #[test]
    #[should_panic(expected: ('No reward tokens available',))]
    fn test_claim_reward_token_no_supply() {
        // Deploy mock contracts
        let game_token_addr = deploy_mock_game_token();
        let reward_token_addr = deploy_mock_reward_token();
        let adventurer_systems_addr = deploy_mock_adventurer_systems();
        let beast_mode_addr = deploy_beast_mode_contract(game_token_addr, reward_token_addr, adventurer_systems_addr);
        
        // Setup mock contracts
        let game_token = MockGameToken::contract_address_for_contract_address(game_token_addr);
        let beast_mode = IBeastModeDispatcher { contract_address: beast_mode_addr };
        
        // Set up the test scenario - contract has 0 reward tokens
        game_token.set_owner(TOKEN_ID.into(), contract_address_const::<PLAYER_ADDRESS>());
        
        // Mock the game token owner call
        mock_call(
            game_token_addr,
            "owner_of",
            array![TOKEN_ID.into()],
            array![contract_address_const::<PLAYER_ADDRESS>()]
        );
        
        // Mock the reward token balance call - contract has 0 tokens
        mock_call(
            reward_token_addr,
            "balance_of",
            array![beast_mode_addr.into()],
            array![0]
        );
        
        // Set caller as the player
        cheat_caller_address(contract_address_const::<0>(), contract_address_const::<PLAYER_ADDRESS>());
        
        // Call claim_reward_token - should fail early due to no supply
        beast_mode.claim_reward_token(TOKEN_ID);
        
        stop_cheat_caller_address(contract_address_const::<0>());
    }
} 