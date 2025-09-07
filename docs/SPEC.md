# Comp Comm Portfolio Smart Contract Specification (v0.1)

## Purpose & Scope

The **CompComm Portfolio** is a community‑managed portfolio, executed by a trusted off‑chain **Portfolio Manager Agent** (LLM) and governed by a community‑editable **Investment Policy** (the “system prompt”) stored on‑chain. This document specifies the smart contracts required to:

1. Gate user requests (messages) behind **USDC payments**, record those requests on‑chain, and mint **Management Tokens (MT)** back to users at a fixed rate, with a **20% developer share** minted alongside.
2. Store and paid‑edit the **on‑chain Investment Policy** (Base‑Paint style substring edits).
3. Hold and operate the portfolio funds via a **Vault** that can swap on **Uniswap v3** and supply/withdraw from **Compound v3 (Comet)** for approved assets/markets.
4. Enforce a **timelock** on portfolio funds for **18 months**, followed by a consolidation-to‑WETH phase and **proportional MT‑based redemption** of the WETH balance.


## Key Roles & Addresses

* **Owner / Dev**: Contract owner; receives the **20% MT dev share** on each mint‑back event. Has admin rights.
* **Agent**: EOA/service key used by the off‑chain Portfolio Manager to execute swaps, supply/withdraw, mark messages processed, and finalize consolidation.
* **Users**: Anyone paying for messages or prompt edits (in **USDC**) and receiving **MT** minted back.
* **Treasury/Vault**: The on‑chain account (Vault contract) that custodies portfolio assets.

## Tokens & Economics

### Management Token (MT)

* Standard **ERC20**, 18 decimals.
* Mintable by authorized contracts (MINTER role). Burnable.
* Symbol/Name: `MT` / `CompComm Management Token` (tbd).
* **Mint‑back pricing (assumption)**:
  * **Messages**: Paying **10 USDC** mints **1.0 MT** to the payer **+ 0.2 MT** to the Dev (20% share).
  * **Prompt edits**: Paying **1 USDC per 10 characters changed** mints **0.1 MT per 10 chars** to the payer **+ 20%** to the Dev.
  * Equivalent: **10 USDC → 1.2 MT total minted (1.0 to user, 0.2 to Dev)**.

### Redemption

* After consolidation, holders can redeem **WETH** from the Vault **pro‑rata** to their MT burned.
* Redemption formula at call time:
  * `redeemAmountWETH = (finalWETHBalanceInVault * userBurnAmountMT) / totalSupplyMT`
* MT total supply includes Dev tokens, **Dev MT is redeemable** like any MT

## High‑Level Architecture

* **MTToken**: ERC20 with MINTER and BURNER roles.
* **Gateway**: Handles payments, message recording, prompt storage & paid edits, and MT mint‑backs.
* **Vault**: Custodies funds, integrates Uniswap v3 & Compound v3, enforces allowlists, timelock, consolidation, and redemption.

```text
Users  ──(USDC payments/edits)──>  Gateway  ──(mint MT + dev share)──>  MTToken
                                     │
                                     ├── emit MessagePaid / PromptEdited events
                                     └── Agent reads events + executes on Vault

Vault  <── Agent (exec) ──  (swaps via Uni v3, supply/withdraw via Comet, claim COMP)
  │
  ├─ Enforce timelock → consolidation to WETH → redemption by MT burn
  └─ Allowlist guardrails for assets/markets
```

## Message Payments & Processing (Gateway)

### Storage

```solidity
mapping(bytes32 => bool) public paidMessages;      // sigHash → paid
mapping(bytes32 => bool) public processedMessages; // sigHash → processed
string public prompt;                              // investment policy (ASCII)
uint256 public promptVersion;                      // increments on each edit
address public usdc;
address public mt;
address public dev;      // dev share receiver
address public agent;    // allowed to mark processed
```

### Message Payment Flow

* **payForMessageWithSig(Message m, bytes sig, string messageURI)**

  * **Price**: `MESSAGE_PRICE_USDC = 10e6` (USDC, 6 decimals).
  * Verify `sigHash = keccak256(sig)` not previously paid.
  * **(Optional but recommended)**: EIP‑712 recover signer over:

    ```
    Message {
      bytes32 messageHash; // keccak256 of off‑chain message content
      address payer;       // who receives MT mint-back
      uint256 nonce;       // user-supplied to prevent replay across messages
    }
    ```

    * Require `signer == m.payer`.
  * `transferFrom(msg.sender → this, 10 USDC)`.
  * Mark `paidMessages[sigHash] = true`.
  * **Mint MT**: `1.0 MT` to `m.payer`; `0.2 MT` to `dev`.
  * Emit `MessagePaid(sigHash, m.payer, messageURI, m.messageHash, userMint=1e18, devMint=2e17)`.

* **markMessageProcessed(bytes32 sigHash)**

  * `onlyAgent`.
  * Require `paidMessages[sigHash] == true` and `processedMessages[sigHash] == false`.
  * Set `processedMessages[sigHash] = true`.
  * Emit `MessageProcessed(sigHash, msg.sender)`.

### Errors (Gateway)

* `AlreadyPaid()`
* `NotPaid()`
* `AlreadyProcessed()`
* `InvalidSignature()`

## On‑Chain Investment Policy (Prompt) & Paid Edits (Gateway)

### Edit Semantics

* Function: `editPrompt(uint256 start, uint256 end, string calldata replacement)`

  * Preconditions:
    * `start <= end` and indices within current prompt length.
    * `replacement.length == end - start`
    * Prompt is assumed **ASCII** (cost computed using `bytes` length).
  * **Changed characters**: `changed = replacement.length`.
  * **Price**: `costUnits = ceil(changed / 10)`; `costUSDC = costUnits * 1e6`.
  * Payment: `transferFrom(msg.sender → this, costUSDC)`.
  * **Mint MT**: `userMint = costUnits * 0.1e18`; `devMint = userMint * 20%`.
  * Apply in‑place edit: `newPrompt = prompt[0:start] + replacement + prompt[end:]`.
  * `promptVersion++`.
  * Emit `PromptEdited(msg.sender, start, end, replacement.length, changed, costUSDC, userMint, devMint, promptVersion)`.

### Read Helpers

* `getPrompt()` returns `(string memory, uint256 version)`.
* `getPromptSlice(uint256 start, uint256 end)` gas‑efficient slice view (best‑effort; optional).
* `previewEditCost(uint256 changed)` returns `(costUSDC, userMint, devMint)`.

### Errors

* `InvalidRange()`

## Vault — Funds, Timelock, Consolidation & Redemption

### Storage & Config

```solidity
uint256 public lockStart;                  // set at deploy
uint256 public constant LOCK_DURATION = 18 months;
uint256 public unlockTimestamp = lockStart + LOCK_DURATION;

mapping(address => bool) public allowedAssets;     // e.g., WETH, USDC, SUSD, AERO (configurable)
mapping(address => bool) public allowedComets;     // e.g., cUSDCv3, cWETHv3, cAEROv3, sSUSDv3 (configurable)

address public weth;                       // WETH token
address public usdc;                       // USDC token
address public uniswapV3Router;            // ISwapRouter
address public cometRewards;               // ICometRewards (for COMP)
address public agent;                      // executor
address public owner;                      // admin
```

### Timelock Phases

* **Phase 0 — Lock (0 → 18 months)**: normal operations allowed (swaps among allowed assets; Comet supply/withdraw to allowed markets).
* **Phase 1 — Consolidation (≥ 18 months, while non-WETH balances > 0)**:

  * **Swaps are only allowed if `tokenOut == WETH`**, to consolidate portfolio to WETH.
* **Phase 2 — Redemption (≥ 18 months, when all non-WETH balances == 0)**:

  * All non‑WETH asset balances and Comet positions must be zero (checked dynamically).
  * Users burn MT to redeem WETH pro‑rata.

### Uniswap v3 Swaps (onlyAgent or Owner)

* `swapExactInputV3(tokenIn, tokenOut, amountIn, amountOutMin, uint24 fee, uint160 sqrtPriceLimitX96)`

  * Require `allowedAssets[tokenIn] && allowedAssets[tokenOut]`.
  * If `block.timestamp >= unlockTimestamp`, require `tokenOut == weth`.
  * Approve router for `amountIn`.
  * Execute **exactInputSingle**.
  * Emit `SwapExecuted(tokenIn, tokenOut, amountIn, amountOut)`.

> Slippage is controlled off‑chain via `amountOutMin` by the Agent.

### Compound v3 (Comet) Integration (onlyAgent or Owner)

Minimal interfaces used:

* `IComet(comet).supply(asset, amount)`
* `IComet(comet).withdraw(asset, amount)`
* `ICometRewards(claimTo(comet, recipient, shouldAccrue))`

Functions:

* `depositToComet(address comet, address asset, uint256 amount)`

  * Require `allowedComets[comet] == true` and `allowedAssets[asset] == true`.
  * Approve asset to Comet; call `supply`.
  * Emit `CometSupplied(comet, asset, amount)`.

* `withdrawFromComet(address comet, address asset, uint256 amount)`

  * Require allowlists.
  * Call `withdraw`.
  * Emit `CometWithdrawn(comet, asset, amount)`.

* `claimComp(address comet, address to)`

  * Call `ICometRewards.claimTo(comet, to, true)`.
  * Emit `CompClaimed(comet, to, amount)` (amount read pre/post if needed).

### Consolidation & Redemption

* `isConsolidated()` (view function)

  * Returns `true` if all non-WETH allowed asset balances == 0 and all Comet positions == 0.
  * Loops through all allowed assets (except WETH) and checks `balanceOf(address(this))`.
  * Loops through all allowed Comets and checks relevant asset positions.

* `redeemWETH(uint256 mtAmount, address to)` (any user)

  * Require `block.timestamp >= unlockTimestamp`.
  * Require `isConsolidated() == true`.
  * `MTToken.burnFrom(msg.sender, mtAmount)` (user must approve Vault as burner/spender).
  * Compute pro‑rata and `transfer WETH(to, amount)`.
  * Emit `Redeemed(msg.sender, to, mtAmount, amount)`.

### Admin Utilities

* `setAllowedAsset(address token, bool allowed)` (onlyOwner)
* `setAllowedComet(address comet, bool allowed)` (onlyOwner)
* `setAgent(address)` (onlyOwner)
* `pause()/unpause()` (Pausable; onlyOwner)
* `sweep(address token, address to)` (onlyOwner)

  * **Guardrails**: During Phase 1 (post‑unlock while `isConsolidated() == false`), sweeping non‑WETH is disallowed. During Phase 2, only dust WETH can be swept after full redemption (optional).

### Errors (Vault)

* `TimelockActive()`
* `OnlyWETHAllowedPostUnlock()`
* `ConsolidationIncomplete()`
* `NotAllowed()` / `InvalidToken()` / `InvalidComet()`

## Access Control, Safety & Upgradeability

* Use **Ownable2Step** (Owner) and **AccessControl** for `AGENT_ROLE`.
* Use **ReentrancyGuard** where tokens are transferred.
* **Pausable** on Vault and Gateway for emergency halt.
* **Non‑upgradeable** recommended for Vault (custodies funds). Gateway & MT can be non‑upgradeable for simplicity; if you need upgradability, use UUPS with strict admin controls.
* All external calls (Uniswap/Comet) must check return values and use safe ERC20 operations.

## Events (Non‑exhaustive)

**Gateway**

* `MessagePaid(bytes32 sigHash, address payer, string uri, bytes32 messageHash, uint256 userMint, uint256 devMint)`
* `MessageProcessed(bytes32 sigHash, address processor)`
* `PromptEdited(address editor, uint256 start, uint256 end, uint256 replacementLen, uint256 changed, uint256 costUSDC, uint256 userMint, uint256 devMint, uint256 version)`

**Vault**

* `SwapExecuted(address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut)`
* `CometSupplied(address comet, address asset, uint256 amount)`
* `CometWithdrawn(address comet, address asset, uint256 amount)`
* `CompClaimed(address comet, address to, uint256 amount)` (amount optional)
* `Redeemed(address account, address to, uint256 mtBurned, uint256 wethOut)`

**MT**

* Standard ERC20 `Transfer`/`Approval`.

## Function Signatures (Suggested)

### MTToken (ERC20)

* `constructor(string name, string symbol)`
* `function grantRole(bytes32 role, address account) external onlyOwner`
* `function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE)`
* `function burnFrom(address account, uint256 amount) external`

### Gateway

```solidity
struct Message { bytes32 messageHash; address payer; uint256 nonce; }

function payForMessageWithSig(Message calldata m, bytes calldata sig, string calldata messageURI) external;
function markMessageProcessed(bytes32 sigHash) external onlyRole(AGENT_ROLE);
function editPrompt(uint256 start, uint256 end, string calldata replacement) external;
function getPrompt() external view returns (string memory, uint256 version);
function previewEditCost(uint256 changed) external pure returns (uint256 costUSDC, uint256 userMint, uint256 devMint);

// Admin
function setAgent(address) external onlyOwner;
function setDev(address) external onlyOwner;
function setUSDC(address) external onlyOwner;
function setMT(address) external onlyOwner;
```

### Vault

```solidity
function swapExactInputV3(
  address tokenIn,
  address tokenOut,
  uint256 amountIn,
  uint256 amountOutMin,
  uint24 fee,
  uint160 sqrtPriceLimitX96
) external onlyAgentOrOwner nonReentrant;

function depositToComet(address comet, address asset, uint256 amount) external onlyAgentOrOwner nonReentrant;
function withdrawFromComet(address comet, address asset, uint256 amount) external onlyAgentOrOwner nonReentrant;
function claimComp(address comet, address to) external onlyAgentOrOwner;

function isConsolidated() external view returns (bool);
function redeemWETH(uint256 mtAmount, address to) external nonReentrant;

// Admin
function setAllowedAsset(address token, bool allowed) external onlyOwner;
function setAllowedComet(address comet, bool allowed) external onlyOwner;
function setAgent(address) external onlyOwner;
function pause() external onlyOwner; function unpause() external onlyOwner;
function sweep(address token, address to) external onlyOwner;
```

## Testing & Acceptance Criteria

**Gateway**

* Paying 10 USDC mints exactly `1.0 MT` to payer and `0.2 MT` to Dev; `paidMessages[sigHash]` true and event emitted.
* Duplicate payment with same `sigHash` reverts `AlreadyPaid()`.
* `markMessageProcessed` only callable by Agent; cannot process unpaid or already processed.
* Prompt edit pricing: for input `(start, end, replacement)`, cost uses `changed = max(end-start, len(replacement))`; rounding up per 10 chars; mints `0.1 MT * costUnits` to payer and `+20%` to Dev.
* Prompt version increments and content matches expected string after edits, including edge cases (insert at start/end, delete range, replace longer/shorter).

**Vault**

* During lock period: swaps among allowed tokens succeed; post‑unlock pre‑consolidation: only `tokenOut == WETH` allowed; otherwise revert `OnlyWETHAllowedPostUnlock()`.
* Comet supply/withdraw and rewards claim work against mocked interfaces.
* `finalizeConsolidation` reverts if any non‑WETH balances > 0; sets `consolidated = true` otherwise.
* `redeemWETH` burns MT and pays exact pro‑rata WETH. Rounding behavior documented (favoring the Vault by 1 wei; final user may sweep remainder via final redemption).

**Permissions & Safety**

* Pausable halts external entry points.
* Reentrancy checks around token transfers and external calls.
* Allowlist enforcement for tokens and Comets.

## Parameters & Constants

### Pricing (USDC 6‑decimals; MT 18‑decimals)

* `MESSAGE_PRICE_USDC = 10_000_000` (10 USDC)
* `EDIT_PRICE_PER_10_CHARS_USDC = 1_000_000` (1 USDC)
* `MT_PER_MESSAGE_USER = 1_000_000_000_000_000_000` (1.0 MT)
* `MT_PER_10CHARS_USER = 100_000_000_000_000_000` (0.1 MT)
* `DEV_BPS = 2000` (20%)

### Time

* `LOCK_DURATION = 18 months`
* `lockStart = block.timestamp` in Vault constructor

### Misc

* `ASCII_ONLY_PROMPT = true` (costing uses `bytes` length)
* Rounding up helper for `costUnits = (changed + 9) / 10`

## Security Considerations

* **Mint surfaces**: MT has multiple minters (Gateway, external distributor). Restrict via roles and emit clear events.
* **Prompt size growth**: Editing stores full string; consider soft cap or gas‑bounded chunks if growth becomes an issue.
* **Signature replay**: `sigHash` + `paidMessages` prevents double‑pay on‑chain; off‑chain must also validate `Message.nonce` and bind `payer`.
* **Oracle‑free design**: No price oracles; consolidation rule post‑unlock simplifies redemption logic.
* **Upgrade risk**: Keep Vault non‑upgradeable to minimize custody risk.

## Deployment & Configuration Checklist

1. Deploy **MTToken**; grant `MINTER_ROLE` to Gateway and the existing monthly distributor (if used).
2. Deploy **Gateway** with `USDC`, `MT`, `Dev`, `Agent`, initial `prompt`.
3. Deploy **Vault** with `USDC`, `WETH`, `UniswapV3Router`, `CometRewards`, `Owner`, `Agent`.
4. Configure **allowlists** for tokens (WETH, USDC, sUSDC?, AERO) and Comets (cUSDCv3, cWETHv3, cAEROv3, sSUSDv3). Use Base addresses in prod; Sepolia/Base‑Sepolia in tests.
5. Wire front‑end/Agent:

   * Pay message: call `payForMessageWithSig` with EIP‑712 sig, `messageURI` (IPFS/Arweave).
   * Listen `MessagePaid` → verify off‑chain → execute portfolio action on Vault → call `markMessageProcessed`.
   * Before each conversation, read the on‑chain `prompt`.
   * For edits, call `editPrompt` and re‑load policy.

## Open Items / Assumptions

* **MT price**: Implemented as **10 USDC → 1 MT (user) + 0.2 MT (dev)** per examples; update the Pricing section if a different rate is desired.
* **Non‑WETH dust**: Define a maximum dust threshold allowed at consolidation, or strictly require zero.
* **Dev redemption**: Dev MT is redeemable under the same rules (current assumption).
* **Asset symbols** (`sUSDC?`, `AERO`): Confirm exact token addresses on Base and Base Sepolia.