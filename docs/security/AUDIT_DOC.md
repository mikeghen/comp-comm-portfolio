## Summary (What, Who, How)
- **What the system does:** CompComm Portfolio accepts USDC contributions, issues a Management Token (MT) as proof of participation, lets contributors pay for AI agent interactions and collaboratively edit an on-chain investment policy, and escrows pooled assets in a time-locked vault that can trade, deploy to Compound v3 markets, and ultimately redeem back to MT holders in WETH.
- **Who uses it:**
  1. MT holders / contributors (pay for agent messages, redeem WETH).
  2. Policy editors (any address able to pay fees to modify the policy prompt). 
  3. Protocol owner (Ownable2Step owner) and designated agent executing trades and DeFi actions.
  4. Dev wallet receiving revenue share from message payments and policy edits.
- **How at a high level:** A LangGraph/AgentKit backend brokers signed instructions from users, relays them to the on-chain managers, and the VaultManager coordinates swaps through Uniswap v3 and lending via Compound v3, while AccessControl-guarded roles enforce minting/burning of MT and Ownable2Step gates privileged vault configuration. The audit scope is frozen at tag `audit-freeze-20250924` on commit `1c253fab12be7e19a54697aa3f990a8b527632b9` in this repository.

## Architecture Overview
- **Module map:**

Contract | Responsibility | Key external funcs | Critical invariants
-- | -- | -- | --
ManagementToken | ERC20 governance/redemption token with mint/burn/pause roles. | `mint`, `burnFrom`, `pause`, `unpause` | Mint/burn restricted to roles; paused transfers block `_update` calls.
MessageManager | Pay-per-message escrow, MT rewards, replay-protected EIP-712 flow. | `payForMessageWithSig`, `markMessageProcessed` | Digests unique; signature must match payer; USDC fee fixed.
PolicyManager | Token-gated collaborative prompt editing with proportional pricing. | `editPrompt`, `getPrompt`, `previewEditCost` | Range bounds, length equality, fee/mint ratios constant.
VaultManager | Timelocked vault executing swaps, lending, reward claims, and final WETH redemption. | `exactInputSingle`, `supply`, `withdraw`, `claimComp`, `redeemWETH`, admin setters | Only allowlisted assets/markets; phase gating on redemption & swaps.

- **Entry points:**
  - ManagementToken: `mint`, `burnFrom`, `pause`, `unpause` (role-gated issuance/burn and pause controls).
  - MessageManager: `payForMessageWithSig` (USDC payment + MT mint); `markMessageProcessed` (agent acknowledgement).
  - PolicyManager: `editPrompt`, `getPrompt`, `getPromptSlice`, `previewEditCost` (policy lifecycle).
  - VaultManager: `exactInputSingle`, `supply`, `withdraw`, `claimComp`, `redeemWETH`, `setAllowedAsset`, `setAllowedComet`, `setAssetComet`, `setAgent`, `pause`, `unpause` (portfolio management).
- **Data flows (high level):**
  1. User USDC flows from payer/editor to the respective manager contracts, which mint MT to the user and dev wallet.
  2. VaultManager swaps allowlisted assets via Uniswap v3 and supplies/withdraws them from configured Compound v3 markets, always retaining custody.
  3. Vault lifecycle transitions from LOCKED → CONSOLIDATION → REDEMPTION based on timelock and asset consolidation, culminating in WETH redemption proportional to MT supply.

## Actors, Roles & Privileges
- **Roles:**

Role | Capabilities
-- | --
DEFAULT_ADMIN (ManagementToken, MessageManager, PolicyManager, VaultManager) | Grant/revoke roles, pause MT (if PAUSER role delegated), administer vault allowlists.
MINTER_ROLE (ManagementToken) | Mint MT; assigned to MessageManager & PolicyManager for rewards.
BURNER_ROLE (ManagementToken) | Burn MT during vault redemption; granted to VaultManager.
PAUSER_ROLE (ManagementToken) | Pause/unpause MT transfers if emergency control delegated.
MessageManager.AGENT_ROLE | Mark messages processed (backend agent).
PolicyManager (no custom roles beyond admin) | Prompt editing open to any payer; admin retains DEFAULT_ADMIN for role management.
VaultManager.AGENT_ROLE | Execute swaps, supply/withdraw, claimComp alongside owner.
Owner (Ownable2Step) | Configure allowlists, agent, pause state, and overall vault governance.
Dev wallet | Receives 20% MT rewards from payments/edits.

- **Access control design:** ManagementToken, MessageManager, PolicyManager use OpenZeppelin AccessControl; VaultManager combines AccessControl with Ownable2Step to gate agent actions and admin setters. Timelocks rely on `LOCK_DURATION`/`UNLOCK_TIMESTAMP` to prevent early redemption.
- **Emergency controls:** ManagementToken transfers can be paused via PAUSER_ROLE; VaultManager inherits Pausable allowing owner to halt swaps, lending, and redemption (blast radius: entire vault operations). Message/Policy managers lack pause switches—mitigation is revoking MINTER_ROLE or pausing MT globally.

## User Flows (Primary Workflows)
1. **Message payment & MT reward**
   - **User story:** As an MT holder, I authorize a signed message payment so the AI agent will process my request and I receive MT rewards.
   - **Preconditions:** Payer holds/approves 10 USDC; MessageManager has MINTER_ROLE on MT; digest unused; agent has AGENT_ROLE.
   - **Happy path steps:** (1) User signs EIP-712 payload; (2) user calls `payForMessageWithSig`; (3) contract validates signature, collects USDC, mints MT to user and dev, marks digest paid, emits MessagePaid event; (4) agent listens for event, reads message content, validates request; (5) agent executes vault actions based on message; (6) agent calls `markMessageProcessed` to complete the flow.
   - **Alternates / edge cases:** Invalid signature or reused digest reverts; insufficient allowance/balance reverts via USDC; agent processing failures don't affect payment completion; duplicate processing prevented by `markMessageProcessed`.
   - **On-chain ↔ off-chain:** Off-chain backend prepares typed data; agent monitors events and determines vault actions; all signature verification on-chain.
   - **Linked diagram:** [`./diagrams/pay-for-message.md`](./diagrams/pay-for-message.md)
   - **Linked tests:** `MessageManager.t.sol::PayForMessageWithSig::test_PaysWithValidSignature_FromPayerDirectly`, `::test_PaysWithValidSignature_ViaRelayer`, `::test_RevertIf_ReplayedSameDigestWithDifferentSignatureEncodings`.

2. **Policy prompt edit**
   - **User story:** As a community editor, I pay the proportional fee to replace a slice of the policy prompt and earn MT rewards.
   - **Preconditions:** Selected range exists; replacement length matches; editor approved sufficient USDC; PolicyManager has MINTER_ROLE.
   - **Happy path steps:** (1) Editor computes replacement string; (2) approves PolicyManager; (3) calls `editPrompt`; (4) contract validates range/length, calculates unit count, pulls USDC, mints MT to editor and dev, applies edit, increments version, emits event.
   - **Alternates / edge cases:** Mismatched lengths or out-of-bounds ranges revert; insufficient USDC reverts during transfer; editors can preview cost off-chain via `previewEditCost`.
   - **On-chain ↔ off-chain:** Editors may rely on UI/backend to compute changed units before submission.
   - **Linked diagram:** [`./diagrams/edit-policy.md`](./diagrams/edit-policy.md)
   - **Linked tests:** `PolicyManager.t.sol::EditPrompt::testFuzz_EditsPromptWithValidRange`, `::testFuzz_AppliesEditCorrectly`, `::testFuzz_RevertIf_InvalidReplacementLength`.

3. **Vault active management (trade + lend)**
   - **User story:** As the designated agent, I rebalance vault assets via Uniswap v3 and deploy capital into Compound v3 while respecting allowlists and phase restrictions.
   - **Preconditions:** Asset/comet allowlists populated by owner; vault holds funds; caller has AGENT_ROLE/ownership; vault not paused.
   - **Happy path steps:** (1) Owner configures vault setup: `setAllowedAsset`, `setAllowedComet`, `setAssetComet`, and `setAgent`; (2) agent executes portfolio management: calls `exactInputSingle` via Uniswap V3 for allowlisted token swaps; (3) agent calls `supply` to deploy assets to configured Compound v3 markets; (4) agent calls `withdraw` to retrieve assets from markets; (5) agent calls `claimComp` to harvest COMP rewards.
   - **Alternates / edge cases:** Unauthorized callers revert; post-unlock swaps must end in WETH; zero amounts or disallowed assets/comets revert; paused state blocks operations; failed swaps/lending operations revert without affecting other operations.
   - **On-chain ↔ off-chain:** Off-chain agent determines optimal portfolio moves based on market conditions and user messages; all execution happens on-chain through VaultManager.
   - **Linked diagram:** [`./diagrams/vault-investment.md`](./diagrams/vault-investment.md)
   - **Linked tests:** `VaultManager.t.sol::SwapExactInputV3::test_SwapsInLockedPhase`, `::test_RevertIf_PostUnlock_SwapNotToWETH`; `VaultManager.t.sol::Supply::test_DepositsAssetToComet`; `Compound.t.sol::SupplyWithdrawUSDC::testFork_Supply_USDC`.

4. **MT redemption for WETH**
   - **User story:** As an MT holder, I burn my tokens after the vault unlocks and consolidates to receive proportional WETH.
   - **Preconditions:** Vault in REDEMPTION phase (timelock expired and only WETH/liquidity positions closed); holder approved MT allowance; vault has BURNER_ROLE on MT.
   - **Happy path steps:** (1) Vault consolidates to WETH and transitions to REDEMPTION; (2) holder approves MT; (3) calls `redeemWETH`; (4) vault calculates pro-rata share, burns MT, transfers WETH, emits event.
   - **Alternates / edge cases:** Calling before consolidation or with zero amount reverts; invalid destination address rejected; paused vault halts redemption.
   - **On-chain ↔ off-chain:** Frontend/backend coordinates phase checks and displays redemption quotes.
   - **Linked diagram:** [`./diagrams/redeem-weth.md`](./diagrams/redeem-weth.md)
   - **Linked tests:** `VaultManager.t.sol::RedeemWETH::test_RedeemsProRataWETHInRedemptionPhase`; `Lifecycle.t.sol::testFork_FullLifecycle_USDC_to_AERO_Comet_to_WETH_and_Redeem`.

## State, Invariants & Properties
- **Key state variables:**
  - MessageManager: `paidMessages`, `processedMessages`, immutable addresses, pricing constants.
  - PolicyManager: `prompt`, `promptVersion`, immutable token/dev addresses, pricing constants.
  - VaultManager: allowlists (`allowedAssets`, `allowedComets`, `assetToComet`), lifecycle timestamps, `agent`, `mtToken`.

- **Invariants (must always hold):**

Invariant | Justification / mechanism | Test or assertion references
-- | -- | --
EIP-712 digest cannot be reused for payment | `paidMessages[digest]` toggled before external calls; replay reverts. | `MessageManager.t.sol::PayForMessageWithSig::test_RevertIf_ReplayedSameDigestWithDifferentSignatureEncodings`.
Policy edits must replace same-length slices and stay in-bounds | Range/length checks prior to transfer/edit; reverts otherwise. | `PolicyManager.t.sol::EditPrompt::testFuzz_RevertIf_InvalidEditRange`, `::testFuzz_RevertIf_InvalidReplacementLength`.
Vault operations limited to allowlisted assets/comets and authorized callers | Guards on `allowedAssets`, `allowedComets`, and `onlyAgentOrOwner`. | `VaultManager.t.sol::SwapExactInputV3::testFuzz_RevertIf_TokenNotAllowed`, `Supply::testFuzz_RevertIf_AssetNotAllowed`, `::test_RevertIf_CallerNotAgentOrOwner`.
Post-unlock swaps must consolidate to WETH before redemption | Swaps not ending in WETH revert post-unlock; redemption checks `getCurrentPhase()`. | `VaultManager.t.sol::SwapExactInputV3::test_RevertIf_PostUnlock_SwapNotToWETH`; `Lifecycle.t.sol::testFork_FullLifecycle...` demonstrates consolidation before redemption.
Redemption outputs proportional WETH and burns MT | Calculation uses total supply prior to burn; MT burn via BURNER_ROLE. | `VaultManager.t.sol::RedeemWETH::test_RedeemsProRataWETHInRedemptionPhase`.

- **Property checks / fuzzing:** Fuzz suites cover signature tampering, prompt bounds, allowlist enforcement, and range calculations via `testFuzz_*` functions under Foundry default profile (see `foundry.toml`).

## Economic & External Assumptions
- **Token assumptions:** USDC treated as 6-decimal non-rebasing asset; MT uses 18 decimals; WETH as canonical wrapped ether; assumption of non-fee-on-transfer tokens (SafeERC20 handles allowances). Tests assume stable decimals (e.g., 1e6).
- **Oracle assumptions:** No on-chain price oracle; swaps rely on live Uniswap v3 pools; Compound positions rely on Comet internal oracle. Risk: price manipulation or slippage if agent misconfigures `amountOutMinimum` (currently pass-through).
- **Liquidity/MEV/DoS assumptions:** Agent responsible for routing with appropriate fee tiers; `amountOutMinimum` must be set to tolerate slippage; `LOCK_DURATION` expects that consolidation is feasible post-unlock without front-running risk; `redeemWETH` relies on WETH liquidity within vault only, so DoS possible if MT supply zero or WETH drained by admin (out of scope).

## Upgradeability & Initialization
- **Pattern:** None; all contracts are deployed as non-proxied implementations (no upgrade hooks). Constructors set immutable addresses and roles.
- **Initialization path:** Deploy ManagementToken with admin; deploy MessageManager/PolicyManager with required addresses; grant MINTER_ROLE; deploy VaultManager with ownable owner & optional agent; configure allowlists. Deployment script `Deploy.s.sol` covers MT + PolicyManager setup.
- **Migration & upgrade safety checks:** Role grants should be double-checked post-deploy; revocation of agent/owner requires Ownable2Step transfer; no timelock contract beyond hardcoded `LOCK_DURATION`. Recommend external governance to wrap owner privileges.

## Parameters & Admin Procedures
- **Config surface:**

Parameter | Location | Units / default | Safe range guidance
-- | -- | -- | --
`MESSAGE_PRICE_USDC` | MessageManager | 10 USDC (1e7) | Match fiat pricing policy; ensure payer affordability.
`MT_PER_MESSAGE_USER`, `DEV_BPS` | MessageManager | 1 MT reward, 20% dev share | Changing requires redeploy; ensure dev share acceptable.
`EDIT_PRICE_PER_10_CHARS_USDC`, `MT_PER_10CHARS_USER`, `DEV_BPS` | PolicyManager | 1 USDC per 10 chars, 0.1 MT reward, 20% dev | Re-deploy to change; consider text length economics.
`LOCK_DURATION` | VaultManager | 18 months | Hardcoded; redeploy to alter.
Allowlist mappings (`setAllowedAsset`, `setAllowedComet`, `setAssetComet`) | VaultManager | Addresses | Restrict to vetted tokens/markets; ensure Comet/asset pairs consistent.
Agent assignment (`setAgent`) | VaultManager | Address | Grant to trusted automation account; revoke when rotating keys.
Pause switches | ManagementToken & VaultManager | Boolean | Use to halt MT transfers or vault ops during incidents.

- **Authorized actors and processes:**
  - Vault owner (recommended multisig) invokes allowlist/agent setters and pause controls; consider time-delayed governance externally.
  - ManagementToken admin delegates MINTER/BURNER/PAUSER roles; ensure revocation path defined.
  - Dev wallet is immutable; any change requires redeploy.
- **Runbooks:**
  - **Pause vault:** Owner calls `pause()`; resume with `unpause()` once incident resolved.
  - **Rotate agent:** Owner calls `setAgent(newAgent)`; revokes old role automatically.
  - **Recover from compromised MT minter:** Admin revokes MINTER_ROLE from affected manager and/or pauses MT; redeploy new manager if needed.

## External Integrations
- **Addresses / versions:** Base mainnet integrations validated in fork tests using canonical addresses: USDC `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913`, WETH `0x4200…0006`, AERO `0x940181…98631`, Uniswap V3 router `0x262666…e481`, Compound Comets (`USDC`: `0xb125E6…2F`, `WETH`: `0x46e6b2…70bf`, `AERO`: `0x784efe…cE89`), CometRewards `0x123964802e6ABabBE1Bc9547D72Ef1B69B00A6b1`, COMP token `0x9e1028F5F1D5eDE59748FFceE5532509976840E0`.
- **Failure assumptions & mitigations:**
  - Uniswap swaps may fail for pools without liquidity—agent should handle revert and attempt alternate fee tiers as in tests.
  - Compound supply/withdraw relies on Comet accrual; if Comet pauses or accrues dust, `_isConsolidatedInternal` may require manual sweeps; monitor for stuck balances.
  - `claimComp` assumes CometRewards live; failure leaves rewards unclaimed but funds intact.

## Build, Test & Reproduction
- **Environment prerequisites:** Linux/macOS with Git; Foundry (forge/cast) pinned to solc 0.8.28; Node.js 18+ and npm for frontend; Python 3.10+ with Poetry for backend (per README). A Base mainnet RPC (HTTPS) is required for fork tests.
- **Clean-machine setup:**
  ```bash
  # Tooling
  curl -L https://foundry.paradigm.xyz | bash
  source ~/.foundry/bin/foundryup
  foundryup --version # ensure latest; forge --version should report solc 0.8.28

  # Clone scoped repo at freeze tag
  git clone https://github.com/<org>/comp-comm-portfolio.git
  cd comp-comm-portfolio
  git checkout audit-freeze-20250924
  ```
- **Environment variables:**
  - Copy `backend/.env.example` to configure backend if needed for integration testing the assistant UI.
  - For fork tests set `export FOUNDRY_PROFILE=default` (or `ci` for longer fuzzing) and provide RPC alias: `export FOUNDRY_RPC_URL_base_mainnet=https://<your-base-rpc>`; optionally set `export BASE_BLOCK_NUMBER=<block>` to pin forks.
- **Build:**
  ```bash
  cd contracts
  forge build
  ```
- **Tests:**
  ```bash
  # Unit & fuzz tests (default profile)
  forge test

  # CI-equivalent with heavier fuzzing
  FOUNDRY_PROFILE=ci forge test

  # Run specific fork test (requires Base RPC)
  forge test --match-path test/integration/Lifecycle.t.sol --match-test testFork_FullLifecycle_USDC_to_AERO_Comet_to_WETH_and_Redeem
  ```
  Backend/frontend stacks can be started separately if auditors wish to exercise signing flows (optional, see README).
- **Coverage / fuzzing:** Foundry fuzz targets embedded via `testFuzz_*`; to reduce iterations set `FOUNDRY_PROFILE=lite`. No dedicated coverage artifacts committed.

## Known Issues & Areas of Concern
- PolicyManager uses naive byte loops for string edits (`_applyEdit`), which is gas-inefficient but functional; potential DoS if extremely large prompts are used—consider slicing via libraries.
- Comments flagged with `@note` indicate uncertainty about pricing rounding; verify economic assumptions before production (e.g., rounding up changed units).
- VaultManager lacks explicit sweep/withdraw function for non-allowlisted tokens despite `VaultManager__SweepRestricted` error declared but unused; plan manual governance procedure for accidental token deposits.
- No automated enforcement ensures dev wallet rotation; if compromised, redeployment required (documented operational risk).

## Appendix
- **Glossary:**
  - **MT:** CompComm Management Token, ERC20 with burn/mint controls.
  - **Comet:** Compound v3 market contract (`IComet`) for supplying collateral/earning yield.
  - **Agent:** Off-chain automation address granted AGENT_ROLE to operate the vault and mark processed messages.
  - **Policy Prompt:** On-chain text representing the investment strategy (i.e., agent system prompt), editable through paid character-based edits.
  - **Message Payment:** USDC payment system allowing users to pay for AI agent interactions while earning MT rewards.
  - **Vault Manager Phases:** LOCKED, CONSOLIDATION, REDEMPTION.
    - **LOCKED:** Initial vault phase where timelock prevents redemption but allows full trading/lending activities.
    - **CONSOLIDATION:** Post-unlock phase where the vault must liquidate all positions into WETH before redemption.
    - **REDEMPTION:** Final phase where MT holders can burn tokens to receive proportional WETH.
  - **Pro-rata:** Proportional distribution; MT holders receive WETH proportional to their token holdings during redemption.
  - **Basis Points (BPS):** Unit of measure equal to 0.01%; used for dev share calculations (e.g., 2000 BPS = 20%).
  - **Dev Wallet:** Immutable address receiving 20% of all MT rewards from message payments and policy edits, either a multisig or Governor Bravo controlled OZ Timelock contracts


- **Diagrams:**
  - [Message payment](./diagrams/pay-for-message.md)
  - [Policy edit](./diagrams/edit-policy.md)
  - [Vault investment lifecycle](./diagrams/vault-investment.md)
  - [MT redemption](./diagrams/redeem-weth.md)

- **Test matrix:** Generated with `scopelint spec`, last run `2025-09-25`:
```
Contract Specification: ManagementToken
├── constructor
│   ├──  Sets Correct Name And Symbol
│   ├──  Sets Correct Decimals
│   ├──  Sets Admin Role
│   ├──  Initial Supply Is Zero
│   ├──  Grants Default Admin Role To Admin
│   ├──  Sets Admin To Arbitrary Address
│   └──  Revert If: Admin Is Zero Address
├── mint
│   ├──  Mints Tokens To Address
│   ├──  Emits Tokens Minted Event
│   ├──  Emits Transfer Event
│   ├──  Revert If: Caller Does Not Have Minter Role
│   ├──  Revert If: To Address Is Zero
│   └──  Admin Can Grant Minter Role And Mint
├── burnFrom
│   ├──  Burns Tokens From Account With Sufficient Balance
│   ├──  Emits Tokens Burned Event
│   ├──  Emits Transfer Event
│   ├──  Burns From Account With Approval
│   ├──  Burns From Self Without Approval
│   ├──  Revert If: Caller Does Not Have Burner Role
│   ├──  Revert If: Account Is Zero Address
│   ├──  Revert If: Insufficient Balance
│   └──  Revert If: Insufficient Allowance
├── pause
│   ├──  Pauses Token
│   ├──  Emits Transfers Paused Event
│   ├──  Emits Paused Event
│   ├──  Revert If: Caller Does Not Have Pauser Role
│   └──  Admin Can Grant Pauser Role And Pause
├── unpause
│   ├──  Unpauses Token
│   ├──  Emits Transfers Unpaused Event
│   ├──  Emits Unpaused Event
│   ├──  Revert If: Caller Does Not Have Pauser Role
│   └──  Admin Can Grant Pauser Role And Unpause
└── _update

Contract Specification: PolicyManager
├── constructor
│   ├──  Sets Configuration Parameters
│   ├──  Sets Configuration Parameters To Arbitrary Values
│   ├──  Revert If: Usdc Address Is Zero
│   ├──  Revert If: Mt Token Address Is Zero
│   └──  Revert If: Dev Address Is Zero
├── editPrompt
│   ├──  Edits Prompt With Valid Range
│   ├──  Emits Prompt Edited Event
│   ├──  Revert If: Invalid Edit Range
│   ├──  Revert If: Invalid Replacement Length
│   ├──  Revert If: Insufficient U S D C Balance
│   ├──  Applies Edit Correctly
│   ├──  Edits Prompt With Zero Range Length
│   └──  Edits Prompt With Exact Cost Calculation
├── getPrompt
│   ├──  Returns Current Prompt And Version
│   └──  Returns Updated Prompt After Edit
├── getPromptSlice
│   ├──  Returns Correct Slice
│   ├──  Returns Empty Slice For Zero Range
│   ├──  Returns Full Prompt Slice
│   └──  Revert If: Invalid Slice Range
├── previewEditCost
│   ├──  Calculates Correct Costs
│   ├──  Calculates Costs For Specific Values
│   └──  Calculates Costs For Multiple Units
├── _mintMT
└── _applyEdit

Contract Specification: MessageManager
├── constructor
│   ├──  Sets Configuration Parameters
│   ├──  Grants Roles
│   ├──  Revert If: Usdc Zero Address
│   ├──  Revert If: Mt Token Zero Address
│   ├──  Revert If: Dev Zero Address
│   ├──  Revert If: Agent Zero Address
│   └──  Revert If: Admin Zero Address
├── payForMessageWithSig
│   ├──  Pays With Valid Signature: From Payer Directly
│   ├──  Pays With Valid Signature: Via Relayer
│   ├──  Revert If: Invalid Signature
│   ├──  Revert If: Replayed Same Digest With Different Signature Encodings
│   ├──  Revert If: Tampered Message After Signing
│   └──  Allows New Signature With Different Nonce
├── markMessageProcessed
│   ├──  Marks Processed When Paid
│   ├──  Revert If: Called By Non Agent
│   ├──  Revert If: Not Paid
│   └──  Revert If: Already Processed
└── exposed_DOMAIN_SEPARATOR

Contract Specification: VaultManager
├── onlyAgentOrOwner
├── constructor
│   ├──  Sets Configuration Parameters
│   ├──  Revert If: Zero Address: U S D C
│   ├──  Revert If: Zero Address: W E T H
│   ├──  Revert If: Zero Address: Router
│   └──  Revert If: Zero Address: Comet Rewards
├── exactInputSingle
├── supply
│   ├──  Revert If: Amount Zero
│   ├──  Revert If: Comet Not Allowed Or Unset
│   ├──  Deposits Asset To Comet
│   ├──  Emits Comet Supplied Event
│   ├──  Revert If: Asset Not Allowed
│   ├──  Revert If: Caller Not Agent Or Owner
│   └──  Agent Can Supply
├── _approveIfNeeded
├── withdraw
│   ├──  Revert If: Amount Zero
│   ├──  Revert If: Comet Not Allowed Or Unset
│   ├──  Revert If: Asset Not Allowed
│   ├──  Withdraws Asset From Comet
│   ├──  Emits Comet Withdrawn Event
│   ├──  Agent Can Withdraw
│   └──  Revert If: Caller Not Agent Or Owner: Withdraw
├── claimComp
│   ├──  Revert If: Invalid To Address
│   ├──  Claims Rewards
│   ├──  Emits Comp Claimed Event
│   ├──  Revert If: Comet Not Allowed
│   ├──  Agent Can Claim Rewards
│   └──  Revert If: Caller Not Agent Or Owner: Claim Comp
├── getCurrentPhase
│   ├──  Returns Locked Before Unlock
│   ├──  Returns Consolidation Post Unlock With Non Weth Balance
│   ├──  Returns Redemption Post Unlock When Consolidated
│   └──  Returns Consolidation Post Unlock With Open Comet Position
├── isConsolidated
├── _isConsolidatedInternal
├── redeemWETH
│   ├──  Revert If: Amount Zero
│   ├──  Revert If: Invalid To Address
│   ├──  Redeems Pro Rata W E T H In Redemption Phase
│   ├──  Emits Redeemed Event
│   └──  Revert If: Not In Redemption Phase
├── setAllowedAsset
│   ├──  Revert If: Token Zero Address
│   ├──  Sets Allowed Asset
│   └──  Emits Allowed Asset Set Event
├── setAllowedComet
│   ├──  Revert If: Comet Zero Address
│   ├──  Sets Allowed Comet
│   └──  Emits Allowed Comet Set Event
├── setAssetComet
│   ├──  Revert If: Asset Not Allow Listed
│   ├──  Revert If: Comet Not Allow Listed
│   ├──  Sets Asset Comet
│   ├──  Revert If: Asset Is Zero
│   ├──  Revert If: Comet Is Zero
│   └──  Emits Asset Comet Set Event
├── setAgent
│   ├──  Revert If: New Agent Zero
│   ├──  Updates Agent Role
│   └──  Emits Agent Set Event
├── pause
│   ├──  Pauses And Blocks Swap
│   └──  Unpauses And Allows Swap
└── unpause
```
