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
OWNER="0x07bdEaC5b256fa53c11B0bC0368Af72916203987429032F37254465ee4Ec078b"

SETTINGS_ID="0"
GAME_TOKEN_ADDRESS="0x79fdfdf5db57b6e1afc91553b21160b9ff126d59ed014299ba5b85fb1ddaa17" # DM game_token_systems
GAME_COLLECTABLE_ADDRESS="0x5400b1e09b9de846793083a87be3007dfe385e1768bb517a9e6055bf0f2e9c2"  # DM beast_systems address
ADVENTURER_SYSTEMS_ADDRESS="0x71d62b73c5c5e39daa080400cc021aa98f6992e1c9a340ed7c7a3f97745257c"  # DM adventurer_systems address
RENDERER_ADDRESS="0x19aecaea1d2daffe37b477b8a2a595ebd0d8c566b30146c6c8bc769f76bfe17"  # DM renderer address

OPENING_TIME="1757728800"  # Timestamp for when the game opens
PAYMENT_TOKEN="0x0"  # Dungeon ticket token
TICKET_RECEIVER_ADDRESS="0x0" # Recycler address
COST_TO_PLAY_LOW="1000000000000000000" # 1 Dungeon ticket
COST_TO_PLAY_HIGH="0"

BEAST_NFT_ADDRESS="0x0"  # Beast NFT V2
BEAST_NFT_OLD_ADDRESS="0x0280ace0b2171106eaebef91ca9b097a566108e9452c45b94a7924a9f794ae80"  # Beast NFT V2
LEGACY_BEASTS_ADDRESS="0x0158160018d590d93528995b340260e65aedd76d28a686e9daa5c4e8fad0c5dd" # Beast NFT V1

REWARD_TOKEN="0x042DD777885AD2C116be96d4D634abC90A26A790ffB5871E037Dd5Ae7d2Ec86B"  # Survivor Token
FREE_GAMES_DURATION="1209600"  # 14 days in seconds
FREE_GAMES_CLAIMER_ADDRESS="0x05343e2bf531a2a90d6a0b575a1eb41f8b74b0da63f668beb4135043f9457844"
BONUS_DURATION="1209600"  # 14 days in seconds

# Golden Pass definitions
# Format: "address:cooldown:game_exp_type:game_exp_value:pass_exp"
# game_exp_type: 0=None, 1=Fixed, 2=Dynamic
# Set to empty string for no golden passes

# Golden token - 7 days cooldown, dynamic 10 days game expiration, no pass expiration
GOLDEN_TOKEN="0x027838dea749f41c6f8a44fcfa791788e6101080c1b3cd646a361f653ad10e2d:604800:2:864000:0"

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
echo "Using account: $STARKNET_ACCOUNT"

# First, let's check if the contract is already declared by computing the class hash
COMPUTED_CLASS_HASH=$(starkli class-hash "$CONTRACT_FILE" 2>&1)
echo "Computed class hash: $COMPUTED_CLASS_HASH"

# Extract account address from the JSON file
ACCOUNT_ADDRESS=$(cat "$STARKNET_ACCOUNT" | grep -o '"address"[[:space:]]*:[[:space:]]*"[^"]*"' | grep -o '0x[0-9a-fA-F]*')
echo "Account address: $ACCOUNT_ADDRESS"

# Try to declare the contract
# First attempt without compiler version flag
echo "Attempting declare without compiler version..."
DECLARE_OUTPUT=$(starkli declare \
    --account "$STARKNET_ACCOUNT" \
    --private-key "$STARKNET_PRIVATE_KEY" \
    --rpc https://starknet-mainnet.g.alchemy.com/starknet/version/rpc/v0_8/6Pzw4ZYxhoeS_bpcXV9oI5FjSCdKZE8d \
    "$CONTRACT_FILE" 2>&1)
    
DECLARE_EXIT_CODE=$?
echo "Declare exit code: $DECLARE_EXIT_CODE"
echo "Declare output: $DECLARE_OUTPUT"

# Extract class hash from output
if echo "$DECLARE_OUTPUT" | grep -q "already declared"; then
    echo "Contract already declared, extracting class hash..."
    # Extract from "Class hash:" line
    CLASS_HASH=$(echo "$DECLARE_OUTPUT" | grep -A1 "already declared" | grep -oE "0x[0-9a-fA-F]+" | tail -1)
elif echo "$DECLARE_OUTPUT" | grep -q "Class hash declared:"; then
    echo "Contract successfully declared, extracting class hash..."
    CLASS_HASH=$(echo "$DECLARE_OUTPUT" | grep -A1 "Class hash declared:" | grep -oE "0x[0-9a-fA-F]+" | tail -1)
else
    # Try to extract any hex value as fallback
    CLASS_HASH=$(echo "$DECLARE_OUTPUT" | grep -oE "0x[0-9a-fA-F]+" | tail -1)
fi

if [ -z "$CLASS_HASH" ]; then
    echo "Warning: Failed to extract class hash from declare output"
    echo "Using computed class hash as fallback: $COMPUTED_CLASS_HASH"
    CLASS_HASH=$COMPUTED_CLASS_HASH
    
    # Validate the computed class hash
    if [ -z "$CLASS_HASH" ] || [ "$CLASS_HASH" = "Error:"* ]; then
        echo "Error: Could not determine a valid class hash"
        exit 1
    fi
fi

echo "Using class hash: $CLASS_HASH"

# Wait for the declaration to be confirmed on-chain
if echo "$DECLARE_OUTPUT" | grep -q "Contract declaration transaction"; then
    echo "Waiting for declaration to be confirmed on-chain..."
    sleep 10
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
echo "  0. OWNER: $OWNER"
echo "  1. OPENING_TIME: $OPENING_TIME"
echo "  2. GAME_TOKEN_ADDRESS: $GAME_TOKEN_ADDRESS"
echo "  3. GAME_COLLECTABLE_ADDRESS: $GAME_COLLECTABLE_ADDRESS"
echo "  4. ADVENTURER_SYSTEMS_ADDRESS: $ADVENTURER_SYSTEMS_ADDRESS"
echo "  5. BEAST_NFT_ADDRESS: $BEAST_NFT_ADDRESS"
echo "  6. BEAST_NFT_OLD_ADDRESS: $BEAST_NFT_OLD_ADDRESS"
echo "  7. LEGACY_BEASTS_ADDRESS: $LEGACY_BEASTS_ADDRESS"
echo "  8. PAYMENT_TOKEN: $PAYMENT_TOKEN"
echo "  9. REWARD_TOKEN: $REWARD_TOKEN"
echo "  10. RENDERER_ADDRESS: $RENDERER_ADDRESS"
echo "  11. GOLDEN_PASS_ARRAY: $GOLDEN_PASS_ARRAY"
echo "  12. TICKET_RECEIVER_ADDRESS: $TICKET_RECEIVER_ADDRESS"
echo "  13. SETTINGS_ID: $SETTINGS_ID"
echo "  14. COST_TO_PLAY: $COST_TO_PLAY_LOW $COST_TO_PLAY_HIGH (u256)"
echo "  15. FREE_GAMES_DURATION: $FREE_GAMES_DURATION"
echo "  16. FREE_GAMES_CLAIMER_ADDRESS: $FREE_GAMES_CLAIMER_ADDRESS"
echo "  17. BONUS_DURATION: $BONUS_DURATION"
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
    --rpc https://starknet-mainnet.g.alchemy.com/starknet/version/rpc/v0_8/6Pzw4ZYxhoeS_bpcXV9oI5FjSCdKZE8d \
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
    --rpc https://starknet-mainnet.g.alchemy.com/starknet/version/rpc/v0_8/6Pzw4ZYxhoeS_bpcXV9oI5FjSCdKZE8d \
    $CLASS_HASH \
    $OWNER \
    $OPENING_TIME \
    $GAME_TOKEN_ADDRESS \
    $GAME_COLLECTABLE_ADDRESS \
    $ADVENTURER_SYSTEMS_ADDRESS \
    $BEAST_NFT_ADDRESS \
    $BEAST_NFT_OLD_ADDRESS \
    $LEGACY_BEASTS_ADDRESS \
    $PAYMENT_TOKEN \
    $REWARD_TOKEN \
    $RENDERER_ADDRESS \
    $GOLDEN_PASS_PARAM \
    $TICKET_RECEIVER_ADDRESS \
    $SETTINGS_ID \
    $COST_TO_PLAY_LOW \
    $COST_TO_PLAY_HIGH \
    $FREE_GAMES_DURATION \
    $FREE_GAMES_CLAIMER_ADDRESS \
    $BONUS_DURATION

DEPLOY_EXIT_CODE=$?

if [ $DEPLOY_EXIT_CODE -ne 0 ]; then
    echo "Error: Deployment failed with exit code $DEPLOY_EXIT_CODE"
    exit 1
fi

echo ""
echo "========================================="
echo "Deployment completed successfully!"
echo "========================================="
echo "Class Hash: $CLASS_HASH"
echo ""
echo "To view your deployed contract on Voyager:"
echo "https://voyager.online/class/$CLASS_HASH"