#!/bin/bash
set -e

source .env

# Validate required environment variables
if [ -z "$STARKNET_ACCOUNT" ] || [ -z "$STARKNET_PRIVATE_KEY" ]; then
    echo "Error: STARKNET_ACCOUNT and STARKNET_PRIVATE_KEY must be set in .env"
    exit 1
fi

# Build the project
echo "Building project..."
scarb build

# Check if contract file exists
CONTRACT_FILE="target/dev/beast_mode_beast_mode.contract_class.json"
if [ ! -f "$CONTRACT_FILE" ]; then
    echo "Error: Contract file not found at $CONTRACT_FILE"
    exit 1
fi
echo "Contract file found: $CONTRACT_FILE"

# Constructor parameters for beast_mode contract
SETTINGS_ID="0"
GAME_TOKEN_ADDRESS="0xd9abf3d04eda96f93baf9873bda881a9580c475e551ff23e78c95ab561ea73" # DM game_token_systems
GAME_COLLECTABLE_ADDRESS="0x5f9371543af0b2b546ba273840e1943e81622105241b4498d1dde4de92e2c77"  # DM beast_systems address
ADVENTURER_SYSTEMS_ADDRESS="0x49d0f851a94eb1949ca7181855d71139ad438d546bb6c6bd92a8c67a0f7ae4f"  # DM adventurer_systems address
RENDERER_ADDRESS="0x73a15594fa18812965007ce02209975d6eb3646f0b4d67c218086eb88a9dc67"  # DM renderer address

OPENING_TIME="1704067200"  # Timestamp for when the game opens
PAYMENT_TOKEN="0x035b77e467aa54686237533bb63e942b2a4c8c76f7321cf94ce8955030a8cc2e"  # Dungeon ticket token
TICKET_RECEIVER_ADDRESS="0x01492BB8B748c4a503F3232ba3D9308571bAAbf0F17b48AB17d5D105d61223C9" # Recycler address
COST_TO_PLAY_LOW="1000000000000000000" # 1 Dungeon ticket
COST_TO_PLAY_HIGH="0"

BEAST_NFT_ADDRESS="0x03d6e75fd8270a5098987713fa2c766a3edd0b03161ffeebe81b27dc48a3f335"  # Beast NFT V2
LEGACY_BEASTS_ADDRESS="0x0" # Beast NFT V1

REWARD_TOKEN="0x025ff15ffd980fa811955d471abdf0d0db40f497a0d08e1fedd63545d1f7ab0d"  # Survivor Token
FREE_GAMES_DURATION="86400"  # 24 hours in seconds
FREE_GAMES_CLAIMER_ADDRESS="0x0"

# Golden Pass definitions
# Format: "address:cooldown:game_exp_type:game_exp_value:pass_exp"
# game_exp_type: 0=None, 1=Fixed, 2=Dynamic
# Set to empty string for no golden passes

# Golden token - 23hr cooldown, dynamic 10 days game expiration, no pass expiration
GOLDEN_TOKEN="0x031d69dbf2f3057f8c52397d0054b43e6ee386eb6b3454fa66a3d2b770a5c2da:86400:2:864000:0"

# Bloberts - 8 days cooldown, fixed 7 days game expiration, 7 days pass expiration
BLOBERTS="0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7:7200:1:43200:1735689600"

# Add golden passes to the array if needed
# For now, keeping it empty as per original intent
GOLDEN_PASSES="
$GOLDEN_TOKEN
"

# Function to build golden pass array
build_golden_pass_array() {
    local passes=""
    local first=true
    
    # Skip if GOLDEN_PASSES is empty
    if [[ -z "${GOLDEN_PASSES// }" ]]; then
        echo "[]"
        return
    fi
    
    while IFS= read -r line; do
        # Skip empty lines
        [[ -z "${line// }" ]] && continue
        
        IFS=':' read -r address cooldown exp_type exp_value pass_exp <<< "$line"
        
        # Build the struct format for golden pass
        if [[ $first == true ]]; then
            passes="($address,$cooldown,$exp_type,$exp_value,$pass_exp)"
            first=false
        else
            passes="$passes,($address,$cooldown,$exp_type,$exp_value,$pass_exp)"
        fi
    done <<< "$GOLDEN_PASSES"
    
    echo "[$passes]"
}

# Contract class declaration
echo "Starting contract declaration..."
DECLARE_OUTPUT=$(starkli declare --account "$STARKNET_ACCOUNT" --private-key "$STARKNET_PRIVATE_KEY" --rpc https://api.cartridge.gg/x/starknet/sepolia "$CONTRACT_FILE" 2>&1)
echo "Declare output: $DECLARE_OUTPUT"

CLASS_HASH=$(echo "$DECLARE_OUTPUT" | grep -oE "0x[0-9a-fA-F]+" | tail -1)

if [ -z "$CLASS_HASH" ]; then
    echo "Error: Failed to extract class hash"
    echo "Declare output: $DECLARE_OUTPUT"
    exit 1
fi

# Build golden pass array
GOLDEN_PASS_ARRAY=$(build_golden_pass_array)
echo "Golden passes: $GOLDEN_PASS_ARRAY"

# Contract deployment with golden passes
echo "Starting deployment..."
echo "Deploying with parameters:"
echo "  CLASS_HASH: $CLASS_HASH"
echo "  OPENING_TIME: $OPENING_TIME"
echo "  GOLDEN_PASS_ARRAY: $GOLDEN_PASS_ARRAY"
echo ""

# Deploy with timeout and better error handling
# First, let's print all parameters for debugging
echo "Deploy command parameters:"
echo "  1. OPENING_TIME: $OPENING_TIME"
echo "  2. GAME_TOKEN_ADDRESS: $GAME_TOKEN_ADDRESS"
echo "  3. GAME_COLLECTABLE_ADDRESS: $GAME_COLLECTABLE_ADDRESS"
echo "  4. ADVENTURER_SYSTEMS_ADDRESS: $ADVENTURER_SYSTEMS_ADDRESS"
echo "  5. BEAST_NFT_ADDRESS: $BEAST_NFT_ADDRESS"
echo "  6. LEGACY_BEASTS_ADDRESS: $LEGACY_BEASTS_ADDRESS"
echo "  7. PAYMENT_TOKEN: $PAYMENT_TOKEN"
echo "  8. REWARD_TOKEN: $REWARD_TOKEN"
echo "  9. REWARD_TOKEN_DELAY: $REWARD_TOKEN_DELAY"
echo "  10. RENDERER_ADDRESS: $RENDERER_ADDRESS"
echo "  11. GOLDEN_PASS_ARRAY: $GOLDEN_PASS_ARRAY"
echo "  12. TICKET_RECEIVER_ADDRESS: $TICKET_RECEIVER_ADDRESS"
echo "  13. SETTINGS_ID: $SETTINGS_ID"
echo "  14. COST_TO_PLAY: $COST_TO_PLAY_LOW $COST_TO_PLAY_HIGH (u256)"
echo ""

# Build the deployment command
# For empty arrays, we need to pass 0 as the array length
if [ "$GOLDEN_PASS_ARRAY" = "[]" ]; then
    GOLDEN_PASS_PARAM="0"
else
    # Count the number of golden passes
    PASS_COUNT=$(echo "$GOLDEN_PASSES" | grep -c '^[^[:space:]]' || true)
    
    # Parse golden passes into individual parameters
    GOLDEN_PASS_PARAMS=""
    while IFS= read -r line; do
        # Skip empty lines
        [[ -z "${line// }" ]] && continue
        
        IFS=':' read -r address cooldown exp_type exp_value pass_exp <<< "$line"
        
        # Add each field as a separate parameter
        GOLDEN_PASS_PARAMS="$GOLDEN_PASS_PARAMS $address $cooldown $exp_type $exp_value $pass_exp"
    done <<< "$GOLDEN_PASSES"
    
    GOLDEN_PASS_PARAM="$PASS_COUNT$GOLDEN_PASS_PARAMS"
fi

echo "Executing deployment..."
echo "Golden pass parameter: $GOLDEN_PASS_PARAM"
echo ""

# First check account balance
echo "Checking account balance..."
ACCOUNT_ADDRESS="0x418ed348930686c844fda4556173457d3f71ae547262406d271de534af6b35e"
BALANCE_OUTPUT=$(starkli call \
    --rpc https://api.cartridge.gg/x/starknet/sepolia \
    0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7 \
    balanceOf \
    $ACCOUNT_ADDRESS 2>&1 || echo "Balance check failed")
echo "Account balance check: $BALANCE_OUTPUT"
echo ""

# Deploy the contract
echo "Starting starkli deploy command..."
echo "Note: This may take a few minutes..."

# Run deployment without timeout to see what happens
starkli deploy \
    --account "$STARKNET_ACCOUNT" \
    --private-key "$STARKNET_PRIVATE_KEY" \
    --rpc https://api.cartridge.gg/x/starknet/sepolia \
    $CLASS_HASH \
    $OPENING_TIME \
    $GAME_TOKEN_ADDRESS \
    $GAME_COLLECTABLE_ADDRESS \
    $ADVENTURER_SYSTEMS_ADDRESS \
    $BEAST_NFT_ADDRESS \
    $LEGACY_BEASTS_ADDRESS \
    $PAYMENT_TOKEN \
    $REWARD_TOKEN \
    $FREE_GAMES_DURATION \
    $RENDERER_ADDRESS \
    $GOLDEN_PASS_PARAM \
    $TICKET_RECEIVER_ADDRESS \
    $SETTINGS_ID \
    $COST_TO_PLAY_LOW \
    $COST_TO_PLAY_HIGH \
    $FREE_GAMES_CLAIMER_ADDRESS

DEPLOY_EXIT_CODE=$?

if [ $DEPLOY_EXIT_CODE -ne 0 ]; then
    echo "Error: Deployment failed with exit code $DEPLOY_EXIT_CODE"
    exit 1
fi

echo ""
echo "Deployment completed successfully!"
echo "Class Hash: $CLASS_HASH"