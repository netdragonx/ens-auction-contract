#!/bin/bash

. .env.local
if [ -z "$ADDRESS_DEPLOYER" ]; then
    echo "Missing ADDRESS_DEPLOYER"
    exit 1
fi

forge script script/DeployAllAnvil.s.sol:DeployAnvilScript \
    -vvvv \
    --fork-url http://localhost:8545 \
    --optimize \
    --optimizer-runs 1000 \
    --gas-estimate-multiplier 200 \
    --sender $ADDRESS_DEPLOYER \
    --interactives 1 \
    --broadcast

exit 0