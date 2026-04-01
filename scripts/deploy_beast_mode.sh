#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Beast Mode — Deployment Script (sncast)
# =============================================================================
#
# Deploys the Beast Mode dungeon contract.
#
# Constructor args:
#   owner, opening_time (u64), denshokan_address, game_token_address, game_core_address,
#   beasts_nft_address, payment_token, reward_token,
#   golden_pass (Span<(ContractAddress, GoldenPass)>),
#   ticket_receiver_address, settings_id (u32), cost_to_play (u256),
#   
#
# Usage:
#   1. Fill in the configuration values below
#   2. bash scripts/deploy_beast_mode.sh
#
# Prerequisites:
#   - scarb build (artifacts in target/)
#   - sncast account configured (sncast account create / import)
# =============================================================================

# ── Configuration (edit these) ───────────────────────────────────────────────
ADMIN_ADDRESS="0x0418ed348930686c844fda4556173457d3f71ae547262406d271de534af6b35e"                # Admin / owner address
OPENING_TIME="1774979231"                 # Opening time (u64 unix timestamp)
DENSHOKAN_ADDRESS="0x077cc1993e80f31770562a4e2ba73b18eae5696a3aa029cba0daea192149f9c0"            # Denshokan / minigame token minter address
GAME_TOKEN_ADDRESS="0x00134d884bf0d3cddf0a7836f1b7e59cbe40d1cd3f87c41e745d07cd71b3a179"           # GameToken contract address
GAME_CORE_ADDRESS="0x0303441ca6a69cc09f45ea699ccf8719514d312b6bfcc299039aedc5df8f1963"            # GameCore contract address
BEASTS_NFT_ADDRESS="0x046da8955829adf2bda310099a0063451923f02e648cf25a1203aac6335cf0e4"           # Beasts NFT contract address
PAYMENT_TOKEN="0x0452810188C4Cb3AEbD63711a3b445755BC0D6C4f27B923fDd99B1A118858136"                # ERC20 token used for payment
REWARD_TOKEN="0x042dd777885ad2c116be96d4d634abc90a26a790ffb5871e037dd5ae7d2ec86b"                 # ERC20 token used for beast rewards
TICKET_RECEIVER_ADDRESS="0"      # Address that receives ticket payments
SETTINGS_ID="0"                  # Settings ID (u32)
COST_TO_PLAY="1000000000000000000"                 # Cost in token units (u256 low, e.g. 10000000000000000000 for 10 tokens with 18 decimals)

# Golden pass: array of (contract_address, GoldenPass { cooldown, game_expiration, pass_expiration }) tuples
# GameExpiration enum variants: 0=None, 1=Fixed(u64), 2=Dynamic(u64)
# Format: "<length> <addr> <cooldown> <expiration_variant> [expiration_value] <pass_expiration> ..."
GOLDEN_PASS_ADDRESS="0x027838dea749f41c6f8a44fcfa791788e6101080c1b3cd646a361f653ad10e2d"
GOLDEN_PASS_COOLDOWN="604800"       # 7 days in seconds
GOLDEN_PASS_GAME_EXP_VARIANT="2"    # 2 = Dynamic
GOLDEN_PASS_GAME_EXP_VALUE="864000" # 10 days in seconds
GOLDEN_PASS_PASS_EXP="0"            # No pass expiration
GOLDEN_PASS="1 $GOLDEN_PASS_ADDRESS $GOLDEN_PASS_COOLDOWN $GOLDEN_PASS_GAME_EXP_VARIANT $GOLDEN_PASS_GAME_EXP_VALUE $GOLDEN_PASS_PASS_EXP"

ACCOUNT="my-deployer"           # sncast account name
RPC_URL="https://api.cartridge.gg/x/starknet/mainnet/rpc/v0_10"                      # Starknet RPC URL

# ── Validate ─────────────────────────────────────────────────────────────────
for var in ADMIN_ADDRESS OPENING_TIME DENSHOKAN_ADDRESS GAME_TOKEN_ADDRESS GAME_CORE_ADDRESS BEASTS_NFT_ADDRESS PAYMENT_TOKEN REWARD_TOKEN TICKET_RECEIVER_ADDRESS SETTINGS_ID COST_TO_PLAY ACCOUNT RPC_URL; do
    if [[ -z "${!var}" ]]; then
        echo "ERROR: $var is not set. Edit the configuration section in this script."
        exit 1
    fi
done

SNCAST="sncast --account $ACCOUNT --wait"
SNCAST_OPTS="--url $RPC_URL"

# ── Helpers ──────────────────────────────────────────────────────────────────
extract_field() {
    local output="$1"
    local field="$2"
    local value
    value=$(echo "$output" | grep -i "^${field}" | head -1 | sed 's/^[^:]*: *//')
    if [[ -z "$value" ]]; then
        local spaced_field
        spaced_field=$(echo "$field" | sed 's/_/ /g')
        value=$(echo "$output" | grep -i "^${spaced_field}" | head -1 | sed 's/^[^:]*: *//')
    fi
    echo "$value"
}

declare_contract() {
    local name="$1"
    echo "   Declaring $name..." >&2
    local stdout_file stderr_file
    stdout_file=$(mktemp)
    stderr_file=$(mktemp)
    $SNCAST declare $SNCAST_OPTS --contract-name "$name" >"$stdout_file" 2>"$stderr_file" || true
    local out err
    out=$(cat "$stdout_file")
    err=$(cat "$stderr_file")
    rm -f "$stdout_file" "$stderr_file"
    local combined="$out"$'\n'"$err"

    if echo "$combined" | grep -q "is already declared"; then
        local hash
        hash=$(echo "$combined" | grep "is already declared" | grep -oE '0x[0-9a-fA-F]+' | head -1)
        echo "   $name already declared: $hash" >&2
        echo "$hash"
        return 0
    fi

    local hash
    hash=$(extract_field "$combined" "class_hash")
    if [[ -n "$hash" ]]; then
        echo "   $name class_hash: $hash" >&2
        echo "$hash"
        return 0
    fi

    echo "   ERROR declaring $name:" >&2
    echo "   stdout: $out" >&2
    echo "   stderr: $err" >&2
    exit 1
}

deploy_contract() {
    local name="$1"
    local class_hash="$2"
    local calldata="$3"
    echo ">> Deploying $name..." >&2
    local stdout_file stderr_file
    stdout_file=$(mktemp)
    stderr_file=$(mktemp)
    $SNCAST deploy $SNCAST_OPTS --class-hash "$class_hash" \
        --constructor-calldata "$calldata" >"$stdout_file" 2>"$stderr_file" || true
    local out err
    out=$(cat "$stdout_file")
    err=$(cat "$stderr_file")
    rm -f "$stdout_file" "$stderr_file"
    local combined="$out"$'\n'"$err"

    local addr
    addr=$(extract_field "$combined" "contract_address")
    if [[ -n "$addr" ]]; then
        echo "   $name deployed at: $addr" >&2
        echo "$addr"
        return 0
    fi

    echo "   ERROR deploying $name:" >&2
    echo "   stdout: $out" >&2
    echo "   stderr: $err" >&2
    exit 1
}

# ── Deploy ───────────────────────────────────────────────────────────────────
echo "============================================="
echo " Beast Mode — Deployment"
echo "============================================="
echo ""
echo "Admin:              $ADMIN_ADDRESS"
echo "Opening Time:       $OPENING_TIME"
echo "Denshokan:          $DENSHOKAN_ADDRESS"
echo "GameToken:          $GAME_TOKEN_ADDRESS"
echo "GameCore:           $GAME_CORE_ADDRESS"
echo "Beasts NFT:         $BEASTS_NFT_ADDRESS"
echo "Payment Token:      $PAYMENT_TOKEN"
echo "Reward Token:       $REWARD_TOKEN"
echo "Golden Pass:        $GOLDEN_PASS"
echo "Ticket Receiver:    $TICKET_RECEIVER_ADDRESS"
echo "Settings ID:        $SETTINGS_ID"
echo "Cost to Play:       $COST_TO_PLAY"
echo "Account:            $ACCOUNT"
echo "RPC:                $RPC_URL"
echo ""

echo ">> Building contracts..."
scarb build
echo ""

echo ">> Declaring beast_mode contract..."
CLASS_BEAST_MODE=$(declare_contract "beast_mode")
echo ""

# Constructor calldata order (matches src/lib.cairo constructor):
#   owner, opening_time, denshokan_address, game_token_address, game_core_address,
#   beasts_nft_address, payment_token, reward_token,
#   golden_pass (span: length + elements), ticket_receiver_address,
#   settings_id, cost_to_play (u256 = low high),
#
# Note: cost_to_play is u256 serialized as two felts (low, high).
#       For values < 2^128, high = 0.
COST_HIGH="0"
BEAST_MODE_CALLDATA="$ADMIN_ADDRESS $OPENING_TIME $DENSHOKAN_ADDRESS $GAME_TOKEN_ADDRESS $GAME_CORE_ADDRESS $BEASTS_NFT_ADDRESS $PAYMENT_TOKEN $REWARD_TOKEN $GOLDEN_PASS $TICKET_RECEIVER_ADDRESS $SETTINGS_ID $COST_TO_PLAY $COST_HIGH"
BEAST_MODE_ADDR=$(deploy_contract "beast_mode" "$CLASS_BEAST_MODE" "$BEAST_MODE_CALLDATA")
echo ""

echo "============================================="
echo " Deployment Complete"
echo "============================================="

cat <<EOF
{
  "beast_mode": "$BEAST_MODE_ADDR"
}
EOF
