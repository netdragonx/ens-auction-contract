#!/bin/bash

testnet() {
    . .env.testnet.local
    local script=$1

    if [ -z "$ADDRESS_DEPLOYER" ]; then
        echo "Missing ADDRESS_DEPLOYER"
        exit 1
    fi

    if [ -z "$ALCHEMY_API_KEY" ]; then
        echo "Missing ALCHEMY_API_KEY"
        exit 1
    fi

    local RPC_URL="https://eth-sepolia.g.alchemy.com/v2/$ALCHEMY_API_KEY"

    forge script "$script" \
        -vvvv \
        --rpc-url "$RPC_URL" \
        --optimize \
        --optimizer-runs 1000 \
        --gas-estimate-multiplier 150 \
        --chain sepolia \
        --verify \
        --legacy \
        --sender "$ADDRESS_DEPLOYER" \
        --interactives 1 \
        --broadcast
}

case $1 in
    all)
        testnet script/DeployAllTestnet.s.sol:DeployTestnetScript
        ;;
    auctions)
        testnet script/EnsAuctions/DeployTestnet.s.sol:DeployEnsAuctionsTestnetScript
        ;;
    fee-calculator)
        testnet script/DynamicFeeCalculator/Deploy.s.sol:DeployDynamicFeeCalculatorScript
        ;;
    drops)
        testnet script/EnsAuctionDrops/Deploy.s.sol:DeployEnsAuctionDropsScript
        ;;
    airdrop)
        testnet script/EnsAuctionDrops/Airdrop.s.sol:AirdropScript
        ;;
    *)
        echo "Usage: $0 {all|auctions|fee-calculator|drops|airdrop}"
        exit 1
esac

exit 0
