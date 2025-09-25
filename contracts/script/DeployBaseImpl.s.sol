// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console2 as console} from "forge-std/Script.sol";

import {ManagementToken} from "src/ManagementToken.sol";
import {PolicyManager} from "src/PolicyManager.sol";
import {MessageManager} from "src/MessageManager.sol";
import {VaultManager} from "src/VaultManager.sol";

/// @title DeployBaseImpl
/// @notice Core deployment logic for CompComm token and portfolio contracts.
/// @dev Network-specific scripts should inherit and set network addresses before calling setup/run.
contract DeployBaseImpl is Script {
  // ---- Deployed contracts ----
  ManagementToken public managementToken;
  PolicyManager public policyManager;
  MessageManager public messageManager;
  VaultManager public vaultManager;

  // ---- Configurable actors ----
  address public admin; // DEFAULT_ADMIN for access control and final vault owner
  address public agent; // operational agent role for MessageManager and VaultManager
  address public dev; // dev revenue recipient for PolicyManager and MessageManager

  // ---- Network addresses ----
  address public USDC;
  address public WETH;
  address public AERO;
  address public UNISWAP_V3_ROUTER;
  address public COMET_REWARDS;
  address public COMET_USDC;
  address public COMET_WETH;
  address public COMET_AERO;

  // ---- Misc config ----
  string public initialPrompt;

  // ---- Keys (optional when running in tests) ----
  uint256 public deployerPrivateKey; // used for deployments and initial configuration
  uint256 public adminPrivateKey; // used to accept vault ownership (Ownable2Step)

  /// @notice Initialize config from environment. Network addresses must be set by child.
  function setup() public virtual {
    // Admin/agent/dev may come from env, otherwise default to tx.origin for local/test runs
    try vm.envAddress("ADMIN_ADDRESS") returns (address _admin) {
      admin = _admin;
    } catch {
      admin = tx.origin;
    }

    try vm.envAddress("AGENT_ADDRESS") returns (address _agent) {
      agent = _agent;
    } catch {
      agent = tx.origin;
    }

    try vm.envAddress("DEV_ADDRESS") returns (address _dev) {
      dev = _dev;
    } catch {
      dev = tx.origin;
    }

    // Prompt
    try vm.envString("INITIAL_PROMPT") returns (string memory p) {
      initialPrompt = p;
    } catch {
      initialPrompt = "Initial investment policy";
    }

    // Keys are optional in tests
    try vm.envUint("DEPLOYER_PRIVATE_KEY") returns (uint256 _dpk) {
      deployerPrivateKey = _dpk;
    } catch {}

    try vm.envUint("ADMIN_PRIVATE_KEY") returns (uint256 _apk) {
      adminPrivateKey = _apk;
    } catch {}

    _validateNetworkAddresses();
  }

  /// @notice Perform the deployment and initial configuration.
  function run() public virtual {
    require(USDC != address(0) && WETH != address(0), "Deploy: token addrs not set");
    require(UNISWAP_V3_ROUTER != address(0), "Deploy: router not set");
    require(COMET_REWARDS != address(0), "Deploy: comet rewards not set");
    require(admin != address(0) && agent != address(0) && dev != address(0), "Deploy: actors");

    bool useBroadcast = deployerPrivateKey != 0;
    if (useBroadcast) vm.startBroadcast(deployerPrivateKey);

    // ---- Deploy token ----
    console.log("Deploying ManagementToken...");
    managementToken = new ManagementToken(admin);
    console.log("ManagementToken:", address(managementToken));

    // ---- Deploy policy manager ----
    console.log("Deploying PolicyManager...");
    policyManager = new PolicyManager(USDC, address(managementToken), dev, initialPrompt);
    console.log("PolicyManager:", address(policyManager));

    // Grant admin in PolicyManager to configured admin, revoke deployer if different
    policyManager.grantRole(policyManager.DEFAULT_ADMIN_ROLE(), admin);
    if (admin != msg.sender) {
      // When broadcasting, msg.sender is the EOA deployer
      try policyManager.revokeRole(policyManager.DEFAULT_ADMIN_ROLE(), msg.sender) {} catch {}
    }

    // ---- Deploy message manager ----
    console.log("Deploying MessageManager...");
    messageManager = new MessageManager(USDC, address(managementToken), dev, agent, admin);
    console.log("MessageManager:", address(messageManager));

    // ---- Deploy vault manager ----
    console.log("Deploying VaultManager...");
    vaultManager = new VaultManager(
      USDC, WETH, address(managementToken), UNISWAP_V3_ROUTER, COMET_REWARDS, agent
    );
    console.log("VaultManager:", address(vaultManager));

    // ---- Configure vault allowlists and comets ----
    // Allow a basic set used in integration tests; these no-ops if zero.
    if (AERO != address(0)) vaultManager.setAllowedAsset(AERO, true);
    vaultManager.setAllowedAsset(USDC, true);
    vaultManager.setAllowedAsset(WETH, true);

    if (COMET_USDC != address(0)) vaultManager.setAllowedComet(COMET_USDC, true);
    if (COMET_WETH != address(0)) vaultManager.setAllowedComet(COMET_WETH, true);
    if (COMET_AERO != address(0)) vaultManager.setAllowedComet(COMET_AERO, true);

    if (COMET_USDC != address(0)) vaultManager.setAssetComet(USDC, COMET_USDC);
    if (COMET_WETH != address(0)) vaultManager.setAssetComet(WETH, COMET_WETH);
    if (AERO != address(0) && COMET_AERO != address(0)) {
      vaultManager.setAssetComet(AERO, COMET_AERO);
    }

    // ---- Transfer ownership of vault to admin (Ownable2Step) ----
    vaultManager.transferOwnership(admin);

    if (useBroadcast) vm.stopBroadcast();

    // ---- Admin actions: grant token roles and accept ownership ----
    if (adminPrivateKey != 0) {
      vm.startBroadcast(adminPrivateKey);
      // Token roles (admin is DEFAULT_ADMIN on token)
      managementToken.grantRole(managementToken.MINTER_ROLE(), address(policyManager));
      managementToken.grantRole(managementToken.MINTER_ROLE(), address(messageManager));
      managementToken.grantRole(managementToken.BURNER_ROLE(), address(vaultManager));
      managementToken.grantRole(managementToken.PAUSER_ROLE(), admin);

      // Accept vault ownership as admin
      try vaultManager.acceptOwnership() {
        console.log("Vault ownership accepted by admin");
      } catch {
        console.log("Vault ownership acceptance failed or already accepted");
      }
      vm.stopBroadcast();
    } else {
      console.log("Admin key not provided; vault pendingOwner set to admin");
    }

    _logSummary();
  }

  function _validateNetworkAddresses() internal view {
    require(USDC != address(0), "Deploy: USDC not set");
    require(WETH != address(0), "Deploy: WETH not set");
    require(UNISWAP_V3_ROUTER != address(0), "Deploy: router not set");
    require(COMET_REWARDS != address(0), "Deploy: cometRewards not set");
    // Comets and AERO can be optional
  }

  function _logSummary() internal view {
    console.log("\n=== Deployment Summary ===");
    console.log("chainId:", block.chainid);
    console.log("admin:", admin);
    console.log("agent:", agent);
    console.log("dev:", dev);
    console.log("USDC:", USDC);
    console.log("WETH:", WETH);
    console.log("AERO:", AERO);
    console.log("router:", UNISWAP_V3_ROUTER);
    console.log("cometRewards:", COMET_REWARDS);
    console.log("MT:", address(managementToken));
    console.log("PolicyManager:", address(policyManager));
    console.log("MessageManager:", address(messageManager));
    console.log("VaultManager:", address(vaultManager));
    console.log("==========================\n");
  }
}
