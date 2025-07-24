# Beast Mode: Death Mountain Dungeon Contract

A Starknet contract for the Death Mountain dungeon, where the main purpose is to collect unique beasts.

## Overview

This contract implements the "Beast Mode" dungeon, allowing players to claim and mint beast NFTs by interacting with the dungeon. It integrates a TicketBooth component for access control and payment, and exposes functions for claiming beasts and retrieving contract addresses.

## Contract Structure

```
BeastModeContract
├── TicketBoothComponent (embedded)
├── claim_beast (external)
├── get_game_token_address (external)
├── get_game_collectable_address (external)
└── get_beast_nft_address (external)
```

## Usage

- Players interact with the contract to claim beasts by providing their adventurer ID and beast details.
- The contract checks ownership, validates collectables, and mints beast NFTs with unique traits.
- The TicketBooth component manages access, payments, and cooldowns for dungeon entry.

## Testing

```bash
scarb test
```

## Dependencies

- `starknet`: Core Starknet functionality
- `game_components_metagame`: Metagame components (TicketBooth, context, etc.)
- `death_mountain`: Dungeon logic and collectable validation
- `beasts`: Beast NFT minting interface
- `openzeppelin_token`: ERC721 NFT standard

## License

This project is licensed under the MIT License. 