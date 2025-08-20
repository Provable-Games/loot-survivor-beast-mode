# Beast Mode: A Death Mountain Dungeon for Loot Survivor

Beast Mode is a custom dungeon implementation built on top of [Death Mountain](https://github.com/Provable-Games/death-mountain), the token-agnostic onchain dungeon creator framework. This dungeon integrates with the Loot Survivor game ecosystem, allowing adventurers to collect and mint unique beast NFTs through strategic gameplay.

## 🏔️ Built on Death Mountain

Death Mountain provides the foundational dungeon mechanics including:

- Adventurer system with stats and equipment
- Beast combat and reward mechanics
- Item and marketplace systems
- Composable, token-agnostic architecture

Beast Mode extends these capabilities with specialized beast collection mechanics and NFT integration.

## 🎮 Features

### Core Functionality

- **Autonomous Pricing**: Uses TWAMM to sell tickets to the dungeon.
- **Collectible Beast NFTs**: Collect crypto native creatures by being the first to defeat them.

### Smart Contract Architecture

```
BeastModeContract
├── TicketBoothComponent (access control & payments)
├── OwnableComponent (admin functions)
├── Beast Claiming System
│   ├── claim_beast (mint NFTs from collectables)
│   └── airdrop_legacy_beast (migrate from mainnet)
├── Reward System
│   └── claim_reward_token (level-based rewards)
└── VRF Integration (randomization for airdrops)
```

## 🚀 Getting Started

### Prerequisites

- Cairo 2.10.1
- Scarb (Starknet's package manager)
- Starknet Foundry (snforge) for testing

### Installation

```bash
# Clone the repository
git clone https://github.com/your-org/loot-survivor-beast-mode
cd loot-survivor-beast-mode

# Build the contracts
scarb build

# Run tests
scarb test
```

## 🧪 Testing

The project includes comprehensive test coverage (84.3% baseline) for:

- Beast claiming and validation
- Rare trait generation
- Legacy beast airdrop system
- Reward token distribution
- Security and edge cases

```bash
# Run all tests
scarb test

# Run with coverage
snforge test --coverage

# Check coverage percentage
lcov --summary coverage/coverage.lcov
```

## 📦 Dependencies

### Death Mountain Components

- `game_components_metagame`: TicketBooth and metagame components
- `game_components_minigame`: Minigame interface integration

### NFT & Token Standards

- `beasts_nft`: Beast NFT minting interface
- `openzeppelin_token`: ERC721/ERC20 implementations
- `openzeppelin_access`: Ownable pattern

### Starknet Core

- `starknet`: Core functionality and syscalls
- VRF integration via Cartridge provider

## 🎯 How It Works

1. **Purchase a Dungeon Token**: Players can purchase a Dungeon Token from Ekubo TWAMM.
2. **Enter the Dungeon**: Use Dungeon Token to unlock the dungeon.
3. **Upgrade Adventurer**: Upgrade the stats and purchase equipment to increase your chances of survival.
4. **Defeat and Collect Beasts**: Be the first to defeat a beast to mint a battle-ready beast NFT.

## 🔧 Configuration

The contract is initialized with:

- Game token and collectable addresses
- Beast NFT contract address
- Payment and reward token addresses
- TicketBooth settings (cost, cooldowns)

## 📄 Contract Interfaces

- `IBeastMode`: Main contract interface
- `IBeastSystems`: Beast validation and minting
- `IAdventurerSystems`: Adventurer data retrieval
- `ILegacyBeasts`: Legacy beast migration

## 🤝 Contributing

Contributions must maintain:

- 80%+ test coverage
- Zero warnings (except known contract size)
- Proper formatting (`scarb fmt`)

See [CLAUDE.md](./CLAUDE.md) for detailed development guidelines.

## 📜 License

This project is licensed under the MIT License.
