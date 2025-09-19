#!/bin/bash

# Deployment validation script for CompComm Portfolio

set -e

echo "🔍 Validating CompComm Portfolio deployment setup..."

# Check if we're in the contracts directory
if [ ! -f "foundry.toml" ]; then
    echo "❌ Please run this script from the contracts directory"
    exit 1
fi

echo "✅ Found foundry.toml"

# Check for required Solidity files
required_files=(
    "src/CompCommPortfolio.sol"
    "src/ManagementToken.sol" 
    "src/MessageManager.sol"
    "src/PolicyManager.sol"
    "src/VaultManager.sol"
    "script/DeployBaseImpl.s.sol"
    "script/BaseNetworkDeploy.s.sol"
    "test/integration/BaseDeployment.t.sol"
)

for file in "${required_files[@]}"; do
    if [ -f "$file" ]; then
        echo "✅ Found $file"
    else
        echo "❌ Missing $file"
        exit 1
    fi
done

# Check environment variables for deployment
echo ""
echo "🔧 Checking environment variables..."

required_env_vars=(
    "ADMIN_ADDRESS"
    "DEV_ADDRESS"
    "AGENT_ADDRESS"
    "INITIAL_PROMPT"
)

missing_vars=()
for var in "${required_env_vars[@]}"; do
    if [ -z "${!var}" ]; then
        missing_vars+=("$var")
        echo "⚠️  Missing $var"
    else
        echo "✅ Found $var"
    fi
done

if [ ${#missing_vars[@]} -gt 0 ]; then
    echo ""
    echo "❌ Missing required environment variables:"
    printf '%s\n' "${missing_vars[@]}"
    echo ""
    echo "Please set them before deploying:"
    echo "export ADMIN_ADDRESS=\"0x...\""
    echo "export DEV_ADDRESS=\"0x...\""
    echo "export AGENT_ADDRESS=\"0x...\""
    echo "export INITIAL_PROMPT=\"Your investment policy here\""
    echo ""
    echo "Optionally set DEPLOYER_PRIVATE_KEY (defaults to anvil test key)"
    exit 1
fi

# Check Foundry installation
echo ""
echo "🔨 Checking Foundry installation..."
if command -v forge &> /dev/null; then
    echo "✅ Foundry is installed"
    forge --version
else
    echo "❌ Foundry is not installed"
    echo "Install from: https://book.getfoundry.sh/getting-started/installation"
    exit 1
fi

# Attempt to compile contracts
echo ""
echo "🏗️  Attempting to compile contracts..."
if forge build > /dev/null 2>&1; then
    echo "✅ Contracts compile successfully"
else
    echo "❌ Compilation failed. Run 'forge build' for details"
    exit 1
fi

# Run basic tests
echo ""
echo "🧪 Running integration tests..."
if forge test --match-contract BaseDeploymentIntegrationTest > /dev/null 2>&1; then
    echo "✅ Integration tests pass"
else
    echo "⚠️  Integration tests failed. Run 'forge test --match-contract BaseDeploymentIntegrationTest -vvv' for details"
fi

echo ""
echo "🎉 Deployment setup validation complete!"
echo ""
echo "To deploy to Base mainnet:"
echo "forge script script/BaseNetworkDeploy.s.sol:BaseNetworkDeploy --rpc-url \$BASE_RPC_URL --broadcast --verify"
echo ""
echo "To deploy locally for testing:"
echo "anvil & # Start local node"
echo "forge script script/BaseNetworkDeploy.s.sol:BaseNetworkDeploy --rpc-url http://localhost:8545 --broadcast"