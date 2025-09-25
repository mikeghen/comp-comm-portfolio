## Summary (What, Who, How)
- **What the system does:** CompComm Portfolio accepts USDC contributions, issues a Management Token (MT) as proof of participation, lets contributors pay for AI agent interactions and collaboratively edit an on-chain investment policy, and escrows pooled assets in a time-locked vault that can trade, deploy to Compound v3 markets, and ultimately redeem back to MT holders in WETH.【F:contracts/src/MessageManager.sol†L12-L156】【F:contracts/src/PolicyManager.sol†L9-L208】【F:contracts/src/VaultManager.sol†L16-L357】
- **Who uses it:**
  1. MT holders / contributors (pay for agent messages, redeem WETH).【F:contracts/src/MessageManager.sol†L112-L146】【F:contracts/src/VaultManager.sol†L291-L307】
  2. Policy editors (any address able to pay fees to modify the policy prompt).【F:contracts/src/PolicyManager.sol†L88-L131】 
  3. Protocol owner (Ownable2Step owner) and designated agent executing trades and DeFi actions.【F:contracts/src/VaultManager.sol†L108-L214】【F:contracts/src/VaultManager.sol†L333-L357】
  4. Dev wallet receiving revenue share from message payments and policy edits.【F:contracts/src/MessageManager.sol†L137-L145】【F:contracts/src/PolicyManager.sol†L109-L130】
- **How at a high level:** A LangGraph/AgentKit backend brokers signed instructions from users, relays them to the on-chain managers, and the VaultManager coordinates swaps through Uniswap v3 and lending via Compound v3, while AccessControl-guarded roles enforce minting/burning of MT and Ownable2Step gates privileged vault configuration. The audit scope is frozen at tag `audit-freeze-20250924` on commit `1c253fab12be7e19a54697aa3f990a8b527632b9` in this repository.【F:README.md†L1-L97】【F:contracts/src/ManagementToken.sol†L13-L114】【F:contracts/src/VaultManager.sol†L16-L357】

## Architecture Overview
- **Module map:**

Contract | Responsibility | Key external funcs | Critical invariants
-- | -- | -- | --
ManagementToken | ERC20 governance/redemption token with mint/burn/pause roles.【F:contracts/src/ManagementToken.sol†L9-L114】 | `mint`, `burnFrom`, `pause`, `unpause` | Mint/burn restricted to roles; paused transfers block `_update` calls.【F:contracts/src/ManagementToken.sol†L26-L113】
MessageManager | Pay-per-message escrow, MT rewards, replay-protected EIP-712 flow.【F:contracts/src/MessageManager.sol†L12-L156】 | `payForMessageWithSig`, `markMessageProcessed` | Digests unique; signature must match payer; USDC fee fixed.【F:contracts/src/MessageManager.sol†L120-L156】
PolicyManager | Token-gated collaborative prompt editing with proportional pricing.【F:contracts/src/PolicyManager.sol†L9-L208】 | `editPrompt`, `getPrompt`, `previewEditCost` | Range bounds, length equality, fee/mint ratios constant.【F:contracts/src/PolicyManager.sol†L88-L208】
VaultManager | Timelocked vault executing swaps, lending, reward claims, and final WETH redemption.【F:contracts/src/VaultManager.sol†L16-L357】 | `exactInputSingle`, `supply`, `withdraw`, `claimComp`, `redeemWETH`, admin setters | Only allowlisted assets/markets; phase gating on redemption & swaps.【F:contracts/src/VaultManager.sol†L170-L357】

- **Entry points:**
  - ManagementToken: `mint`, `burnFrom`, `pause`, `unpause` (role-gated issuance/burn and pause controls).【F:contracts/src/ManagementToken.sol†L59-L113】
  - MessageManager: `payForMessageWithSig` (USDC payment + MT mint); `markMessageProcessed` (agent acknowledgement).【F:contracts/src/MessageManager.sol†L112-L156】
  - PolicyManager: `editPrompt`, `getPrompt`, `getPromptSlice`, `previewEditCost` (policy lifecycle).【F:contracts/src/PolicyManager.sol†L88-L171】
  - VaultManager: `exactInputSingle`, `supply`, `withdraw`, `claimComp`, `redeemWETH`, `setAllowedAsset`, `setAllowedComet`, `setAssetComet`, `setAgent`, `pause`, `unpause` (portfolio management).【F:contracts/src/VaultManager.sol†L170-L357】
- **Data flows (high level):**
  1. User USDC flows from payer/editor to the respective manager contracts, which mint MT to the user and dev wallet.【F:contracts/src/MessageManager.sol†L134-L145】【F:contracts/src/PolicyManager.sol†L109-L130】
  2. VaultManager swaps allowlisted assets via Uniswap v3 and supplies/withdraws them from configured Compound v3 markets, always retaining custody.【F:contracts/src/VaultManager.sol†L170-L237】
  3. Vault lifecycle transitions from LOCKED → CONSOLIDATION → REDEMPTION based on timelock and asset consolidation, culminating in WETH redemption proportional to MT supply.【F:contracts/src/VaultManager.sol†L255-L308】

## Actors, Roles & Privileges
- **Roles:**

Role | Capabilities
-- | --
DEFAULT_ADMIN (ManagementToken, MessageManager, PolicyManager, VaultManager) | Grant/revoke roles, pause MT (if PAUSER role delegated), administer vault allowlists.【F:contracts/src/ManagementToken.sol†L51-L104】【F:contracts/src/MessageManager.sol†L108-L156】【F:contracts/src/PolicyManager.sol†L69-L208】【F:contracts/src/VaultManager.sol†L108-L357】
MINTER_ROLE (ManagementToken) | Mint MT; assigned to MessageManager & PolicyManager for rewards.【F:contracts/src/ManagementToken.sol†L26-L68】
BURNER_ROLE (ManagementToken) | Burn MT during vault redemption; granted to VaultManager.【F:contracts/src/ManagementToken.sol†L29-L90】【F:contracts/test/VaultManager.t.sol†L513-L543】
PAUSER_ROLE (ManagementToken) | Pause/unpause MT transfers if emergency control delegated.【F:contracts/src/ManagementToken.sol†L32-L113】
MessageManager.AGENT_ROLE | Mark messages processed (backend agent).【F:contracts/src/MessageManager.sol†L31-L156】
PolicyManager (no custom roles beyond admin) | Prompt editing open to any payer; admin retains DEFAULT_ADMIN for role management.【F:contracts/src/PolicyManager.sol†L69-L86】
VaultManager.AGENT_ROLE | Execute swaps, supply/withdraw, claimComp alongside owner.【F:contracts/src/VaultManager.sol†L108-L237】
Owner (Ownable2Step) | Configure allowlists, agent, pause state, and overall vault governance.【F:contracts/src/VaultManager.sol†L313-L355】
Dev wallet | Receives 20% MT rewards from payments/edits.【F:contracts/src/MessageManager.sol†L137-L145】【F:contracts/src/PolicyManager.sol†L109-L130】

- **Access control design:** ManagementToken, MessageManager, PolicyManager use OpenZeppelin AccessControl; VaultManager combines AccessControl with Ownable2Step to gate agent actions and admin setters.【F:contracts/src/ManagementToken.sol†L13-L114】【F:contracts/src/MessageManager.sol†L12-L156】【F:contracts/src/PolicyManager.sol†L9-L208】【F:contracts/src/VaultManager.sol†L16-L357】 Timelocks rely on `LOCK_DURATION`/`UNLOCK_TIMESTAMP` to prevent early redemption.【F:contracts/src/VaultManager.sol†L40-L90】
- **Emergency controls:** ManagementToken transfers can be paused via PAUSER_ROLE; VaultManager inherits Pausable allowing owner to halt swaps, lending, and redemption (blast radius: entire vault operations).【F:contracts/src/ManagementToken.sol†L32-L113】【F:contracts/src/VaultManager.sol†L8-L357】 Message/Policy managers lack pause switches—mitigation is revoking MINTER_ROLE or pausing MT globally.

## User Flows (Primary Workflows)
1. **Message payment & MT reward**
   - **User story:** As an MT holder, I authorize a signed message payment so the AI agent will process my request and I receive MT rewards.【F:contracts/src/MessageManager.sol†L112-L156】
   - **Preconditions:** Payer holds/approves 10 USDC; MessageManager has MINTER_ROLE on MT; digest unused.【F:contracts/src/MessageManager.sol†L120-L145】
   - **Happy path steps:** (1) User signs EIP-712 payload; (2) user or relayer calls `payForMessageWithSig`; (3) contract validates signature, collects USDC, mints MT to user and dev, marks digest paid, emits event.【F:contracts/src/MessageManager.sol†L120-L145】
   - **Alternates / edge cases:** Invalid signature or reused digest reverts; insufficient allowance/balance reverts via USDC; agent later calls `markMessageProcessed` to prevent duplicate handling.【F:contracts/src/MessageManager.sol†L127-L156】【F:contracts/test/MessageManager.t.sol†L188-L232】
   - **On-chain ↔ off-chain:** Off-chain backend prepares typed data, optionally relays call; on-chain verifies signature.
   - **Linked diagram:** [`./diagrams/pay-for-message.md`](./diagrams/pay-for-message.md)
   - **Linked tests:** `MessageManager.t.sol::PayForMessageWithSig::test_PaysWithValidSignature_FromPayerDirectly`, `::test_PaysWithValidSignature_ViaRelayer`, `::test_RevertIf_ReplayedSameDigestWithDifferentSignatureEncodings`.【F:contracts/test/MessageManager.t.sol†L135-L232】

2. **Policy prompt edit**
   - **User story:** As a community editor, I pay the proportional fee to replace a slice of the policy prompt and earn MT rewards.【F:contracts/src/PolicyManager.sol†L88-L131】
   - **Preconditions:** Selected range exists; replacement length matches; editor approved sufficient USDC; PolicyManager has MINTER_ROLE.【F:contracts/src/PolicyManager.sol†L99-L130】
   - **Happy path steps:** (1) Editor computes replacement string; (2) approves PolicyManager; (3) calls `editPrompt`; (4) contract validates range/length, calculates unit count, pulls USDC, mints MT to editor and dev, applies edit, increments version, emits event.【F:contracts/src/PolicyManager.sol†L99-L130】
   - **Alternates / edge cases:** Mismatched lengths or out-of-bounds ranges revert; insufficient USDC reverts during transfer; editors can preview cost off-chain via `previewEditCost`.【F:contracts/src/PolicyManager.sol†L101-L171】【F:contracts/test/PolicyManager.t.sol†L185-L318】
   - **On-chain ↔ off-chain:** Editors may rely on UI/backend to compute changed units before submission.
   - **Linked diagram:** [`./diagrams/edit-policy.md`](./diagrams/edit-policy.md)
   - **Linked tests:** `PolicyManager.t.sol::EditPrompt::testFuzz_EditsPromptWithValidRange`, `::testFuzz_AppliesEditCorrectly`, `::testFuzz_RevertIf_InvalidReplacementLength`.【F:contracts/test/PolicyManager.t.sol†L167-L360】

3. **Vault active management (trade + lend)**
   - **User story:** As the designated agent, I rebalance vault assets via Uniswap v3 and deploy capital into Compound v3 while respecting allowlists and phase restrictions.【F:contracts/src/VaultManager.sol†L170-L237】
   - **Preconditions:** Asset/comet allowlists populated by owner; vault holds funds; caller has AGENT_ROLE/ownership; vault not paused.【F:contracts/src/VaultManager.sol†L108-L237】【F:contracts/src/VaultManager.sol†L313-L357】
   - **Happy path steps:** (1) Owner configures `setAllowedAsset`, `setAllowedComet`, `setAssetComet`, and `setAgent`; (2) agent calls `exactInputSingle` for allowlisted pairs; (3) agent supplies withdrawn balances to configured Comets; (4) optionally withdraws or claims COMP.【F:contracts/src/VaultManager.sol†L170-L253】【F:contracts/src/VaultManager.sol†L313-L347】
   - **Alternates / edge cases:** Unauthorized callers revert; post-unlock swaps must end in WETH; zero amounts or disallowed assets/comets revert; paused state blocks operations.【F:contracts/src/VaultManager.sol†L170-L237】【F:contracts/test/VaultManager.t.sol†L200-L368】
   - **On-chain ↔ off-chain:** Off-chain keepers determine optimal swaps/market moves, pass calldata via backend.
   - **Linked diagram:** [`./diagrams/vault-investment.md`](./diagrams/vault-investment.md)
   - **Linked tests:** `VaultManager.t.sol::SwapExactInputV3::test_SwapsInLockedPhase`, `::test_RevertIf_PostUnlock_SwapNotToWETH`; `VaultManager.t.sol::Supply::test_DepositsAssetToComet`; `Compound.t.sol::SupplyWithdrawUSDC::testFork_Supply_USDC`.【F:contracts/test/VaultManager.t.sol†L200-L344】【F:contracts/test/integration/Compound.t.sol†L10-L139】

4. **MT redemption for WETH**
   - **User story:** As an MT holder, I burn my tokens after the vault unlocks and consolidates to receive proportional WETH.【F:contracts/src/VaultManager.sol†L291-L307】
   - **Preconditions:** Vault in REDEMPTION phase (timelock expired and only WETH/liquidity positions closed); holder approved MT allowance; vault has BURNER_ROLE on MT.【F:contracts/src/VaultManager.sol†L255-L307】【F:contracts/test/VaultManager.t.sol†L503-L559】
   - **Happy path steps:** (1) Vault consolidates to WETH and transitions to REDEMPTION; (2) holder approves MT; (3) calls `redeemWETH`; (4) vault calculates pro-rata share, burns MT, transfers WETH, emits event.【F:contracts/src/VaultManager.sol†L255-L307】
   - **Alternates / edge cases:** Calling before consolidation or with zero amount reverts; invalid destination address rejected; paused vault halts redemption.【F:contracts/src/VaultManager.sol†L291-L307】【F:contracts/test/VaultManager.t.sol†L503-L559】
   - **On-chain ↔ off-chain:** Frontend/backend coordinates phase checks and displays redemption quotes.
   - **Linked diagram:** [`./diagrams/redeem-weth.md`](./diagrams/redeem-weth.md)
   - **Linked tests:** `VaultManager.t.sol::RedeemWETH::test_RedeemsProRataWETHInRedemptionPhase`; `Lifecycle.t.sol::testFork_FullLifecycle_USDC_to_AERO_Comet_to_WETH_and_Redeem`.【F:contracts/test/VaultManager.t.sol†L503-L559】【F:contracts/test/integration/Lifecycle.t.sol†L84-L143】

## State, Invariants & Properties
- **Key state variables:**
  - MessageManager: `paidMessages`, `processedMessages`, immutable addresses, pricing constants.【F:contracts/src/MessageManager.sol†L41-L145】
  - PolicyManager: `prompt`, `promptVersion`, immutable token/dev addresses, pricing constants.【F:contracts/src/PolicyManager.sol†L19-L171】
  - VaultManager: allowlists (`allowedAssets`, `allowedComets`, `assetToComet`), lifecycle timestamps, `agent`, `mtToken`.【F:contracts/src/VaultManager.sol†L40-L347】

- **Invariants (must always hold):**

Invariant | Justification / mechanism | Test or assertion references
-- | -- | --
EIP-712 digest cannot be reused for payment | `paidMessages[digest]` toggled before external calls; replay reverts.【F:contracts/src/MessageManager.sol†L124-L145】 | `MessageManager.t.sol::PayForMessageWithSig::test_RevertIf_ReplayedSameDigestWithDifferentSignatureEncodings`.【F:contracts/test/MessageManager.t.sol†L206-L232】
Policy edits must replace same-length slices and stay in-bounds | Range/length checks prior to transfer/edit; reverts otherwise.【F:contracts/src/PolicyManager.sol†L99-L123】 | `PolicyManager.t.sol::EditPrompt::testFuzz_RevertIf_InvalidEditRange`, `::testFuzz_RevertIf_InvalidReplacementLength`.【F:contracts/test/PolicyManager.t.sol†L231-L274】
Vault operations limited to allowlisted assets/comets and authorized callers | Guards on `allowedAssets`, `allowedComets`, and `onlyAgentOrOwner`.【F:contracts/src/VaultManager.sol†L108-L237】 | `VaultManager.t.sol::SwapExactInputV3::testFuzz_RevertIf_TokenNotAllowed`, `Supply::testFuzz_RevertIf_AssetNotAllowed`, `::test_RevertIf_CallerNotAgentOrOwner`.【F:contracts/test/VaultManager.t.sol†L220-L344】
Post-unlock swaps must consolidate to WETH before redemption | Swaps not ending in WETH revert post-unlock; redemption checks `getCurrentPhase()`.【F:contracts/src/VaultManager.sol†L190-L308】 | `VaultManager.t.sol::SwapExactInputV3::test_RevertIf_PostUnlock_SwapNotToWETH`; `Lifecycle.t.sol::testFork_FullLifecycle...` demonstrates consolidation before redemption.【F:contracts/test/VaultManager.t.sol†L226-L240】【F:contracts/test/integration/Lifecycle.t.sol†L84-L143】
Redemption outputs proportional WETH and burns MT | Calculation uses total supply prior to burn; MT burn via BURNER_ROLE.【F:contracts/src/VaultManager.sol†L291-L307】 | `VaultManager.t.sol::RedeemWETH::test_RedeemsProRataWETHInRedemptionPhase`.【F:contracts/test/VaultManager.t.sol†L523-L544】

- **Property checks / fuzzing:** Fuzz suites cover signature tampering, prompt bounds, allowlist enforcement, and range calculations via `testFuzz_*` functions under Foundry default profile (see `foundry.toml`).【F:contracts/test/MessageManager.t.sol†L188-L272】【F:contracts/test/PolicyManager.t.sol†L185-L360】【F:contracts/test/VaultManager.t.sol†L220-L380】【F:contracts/foundry.toml†L1-L31】

## Economic & External Assumptions
- **Token assumptions:** USDC treated as 6-decimal non-rebasing asset; MT uses 18 decimals; WETH as canonical wrapped ether; assumption of non-fee-on-transfer tokens (SafeERC20 handles allowances).【F:contracts/src/MessageManager.sol†L56-L145】【F:contracts/src/PolicyManager.sol†L34-L130】【F:contracts/src/VaultManager.sol†L49-L357】 Tests assume stable decimals (e.g., 1e6).【F:contracts/test/VaultManager.t.sol†L200-L344】
- **Oracle assumptions:** No on-chain price oracle; swaps rely on live Uniswap v3 pools; Compound positions rely on Comet internal oracle. Risk: price manipulation or slippage if agent misconfigures `amountOutMinimum` (currently pass-through).【F:contracts/src/VaultManager.sol†L170-L205】【F:contracts/test/integration/Uniswap.t.sol†L10-L125】
- **Liquidity/MEV/DoS assumptions:** Agent responsible for routing with appropriate fee tiers; `amountOutMinimum` must be set to tolerate slippage; `LOCK_DURATION` expects that consolidation is feasible post-unlock without front-running risk; `redeemWETH` relies on WETH liquidity within vault only, so DoS possible if MT supply zero or WETH drained by admin (out of scope).【F:contracts/src/VaultManager.sol†L170-L307】【F:contracts/test/integration/Lifecycle.t.sol†L84-L143】

## Upgradeability & Initialization
- **Pattern:** None; all contracts are deployed as non-proxied implementations (no upgrade hooks). Constructors set immutable addresses and roles.【F:contracts/src/ManagementToken.sol†L51-L68】【F:contracts/src/MessageManager.sol†L90-L110】【F:contracts/src/PolicyManager.sol†L69-L86】【F:contracts/src/VaultManager.sol†L115-L149】
- **Initialization path:** Deploy ManagementToken with admin; deploy MessageManager/PolicyManager with required addresses; grant MINTER_ROLE; deploy VaultManager with ownable owner & optional agent; configure allowlists. Deployment script `Deploy.s.sol` covers MT + PolicyManager setup.【F:contracts/script/Deploy.s.sol†L12-L86】
- **Migration & upgrade safety checks:** Role grants should be double-checked post-deploy; revocation of agent/owner requires Ownable2Step transfer; no timelock contract beyond hardcoded `LOCK_DURATION`. Recommend external governance to wrap owner privileges.

## Parameters & Admin Procedures
- **Config surface:**

Parameter | Location | Units / default | Safe range guidance
-- | -- | -- | --
`MESSAGE_PRICE_USDC` | MessageManager | 10 USDC (1e7) | Match fiat pricing policy; ensure payer affordability.【F:contracts/src/MessageManager.sol†L56-L145】
`MT_PER_MESSAGE_USER`, `DEV_BPS` | MessageManager | 1 MT reward, 20% dev share | Changing requires redeploy; ensure dev share acceptable.【F:contracts/src/MessageManager.sol†L59-L145】
`EDIT_PRICE_PER_10_CHARS_USDC`, `MT_PER_10CHARS_USER`, `DEV_BPS` | PolicyManager | 1 USDC per 10 chars, 0.1 MT reward, 20% dev | Re-deploy to change; consider text length economics.【F:contracts/src/PolicyManager.sol†L34-L130】
`LOCK_DURATION` | VaultManager | 18 months | Hardcoded; redeploy to alter.【F:contracts/src/VaultManager.sol†L40-L90】
Allowlist mappings (`setAllowedAsset`, `setAllowedComet`, `setAssetComet`) | VaultManager | Addresses | Restrict to vetted tokens/markets; ensure Comet/asset pairs consistent.【F:contracts/src/VaultManager.sol†L313-L340】
Agent assignment (`setAgent`) | VaultManager | Address | Grant to trusted automation account; revoke when rotating keys.【F:contracts/src/VaultManager.sol†L342-L347】
Pause switches | ManagementToken & VaultManager | Boolean | Use to halt MT transfers or vault ops during incidents.【F:contracts/src/ManagementToken.sol†L92-L113】【F:contracts/src/VaultManager.sol†L350-L355】

- **Authorized actors and processes:**
  - Vault owner (recommended multisig) invokes allowlist/agent setters and pause controls; consider time-delayed governance externally.【F:contracts/src/VaultManager.sol†L313-L355】
  - ManagementToken admin delegates MINTER/BURNER/PAUSER roles; ensure revocation path defined.【F:contracts/src/ManagementToken.sol†L26-L113】
  - Dev wallet is immutable; any change requires redeploy.
- **Runbooks:**
  - **Pause vault:** Owner calls `pause()`; resume with `unpause()` once incident resolved.【F:contracts/src/VaultManager.sol†L350-L355】
  - **Rotate agent:** Owner calls `setAgent(newAgent)`; revokes old role automatically.【F:contracts/src/VaultManager.sol†L342-L347】
  - **Recover from compromised MT minter:** Admin revokes MINTER_ROLE from affected manager and/or pauses MT; redeploy new manager if needed.【F:contracts/src/ManagementToken.sol†L26-L113】

## External Integrations
- **Addresses / versions:** Base mainnet integrations validated in fork tests using canonical addresses: USDC `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913`, WETH `0x4200…0006`, AERO `0x940181…98631`, Uniswap V3 router `0x262666…e481`, Compound Comets (`USDC`: `0xb125E6…2F`, `WETH`: `0x46e6b2…70bf`, `AERO`: `0x784efe…cE89`), CometRewards `0x123964802e6ABabBE1Bc9547D72Ef1B69B00A6b1`, COMP token `0x9e1028F5F1D5eDE59748FFceE5532509976840E0`.【F:contracts/test/integration/Uniswap.t.sol†L10-L115】【F:contracts/test/integration/Compound.t.sol†L10-L139】
- **Failure assumptions & mitigations:**
  - Uniswap swaps may fail for pools without liquidity—agent should handle revert and attempt alternate fee tiers as in tests.【F:contracts/test/integration/Uniswap.t.sol†L56-L83】
  - Compound supply/withdraw relies on Comet accrual; if Comet pauses or accrues dust, `_isConsolidatedInternal` may require manual sweeps; monitor for stuck balances.【F:contracts/src/VaultManager.sol†L272-L288】【F:contracts/test/integration/Lifecycle.t.sol†L84-L143】
  - `claimComp` assumes CometRewards live; failure leaves rewards unclaimed but funds intact.【F:contracts/src/VaultManager.sol†L239-L252】

## Build, Test & Reproduction
- **Environment prerequisites:** Linux/macOS with Git; Foundry (forge/cast) pinned to solc 0.8.28; Node.js 18+ and npm for frontend; Python 3.10+ with Poetry for backend (per README).【F:contracts/foundry.toml†L1-L31】【F:README.md†L55-L83】 A Base mainnet RPC (HTTPS) is required for fork tests.
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
  - Copy `backend/.env.example` to configure backend if needed for integration testing the assistant UI.【F:README.md†L70-L83】
  - For fork tests set `export FOUNDRY_PROFILE=default` (or `ci` for longer fuzzing) and provide RPC alias: `export FOUNDRY_RPC_URL_base_mainnet=https://<your-base-rpc>`; optionally set `export BASE_BLOCK_NUMBER=<block>` to pin forks.【F:contracts/test/integration/Uniswap.t.sol†L28-L35】【F:contracts/test/integration/Compound.t.sol†L34-L41】
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
  Backend/frontend stacks can be started separately if auditors wish to exercise signing flows (optional, see README).【F:README.md†L70-L95】
- **Coverage / fuzzing:** Foundry fuzz targets embedded via `testFuzz_*`; to reduce iterations set `FOUNDRY_PROFILE=lite`. No dedicated coverage artifacts committed.【F:contracts/foundry.toml†L16-L29】

## Known Issues & Areas of Concern
- PolicyManager uses naive byte loops for string edits (`_applyEdit`), which is gas-inefficient but functional; potential DoS if extremely large prompts are used—consider slicing via libraries.【F:contracts/src/PolicyManager.sol†L180-L207】
- Comments flagged with `@note` indicate uncertainty about pricing rounding; verify economic assumptions before production (e.g., rounding up changed units).【F:contracts/src/PolicyManager.sol†L104-L108】
- VaultManager lacks explicit sweep/withdraw function for non-allowlisted tokens despite `VaultManager__SweepRestricted` error declared but unused; plan manual governance procedure for accidental token deposits.【F:contracts/src/VaultManager.sol†L24-L30】【F:contracts/src/VaultManager.sol†L313-L355】
- No automated enforcement ensures dev wallet rotation; if compromised, redeployment required (documented operational risk).【F:contracts/src/MessageManager.sol†L90-L145】【F:contracts/src/PolicyManager.sol†L69-L130】

## Appendix
- **Glossary:**
  - **MT:** CompComm Management Token, ERC20 with burn/mint controls.【F:contracts/src/ManagementToken.sol†L9-L114】
  - **Comet:** Compound v3 market contract (`IComet`) for supplying collateral/earning yield.【F:contracts/src/interfaces/IComet.sol†L1-L8】
  - **Agent:** Off-chain automation address granted AGENT_ROLE to operate the vault and mark processed messages.【F:contracts/src/MessageManager.sol†L31-L156】【F:contracts/src/VaultManager.sol†L108-L347】
  - **Consolidation:** Post-unlock phase ensuring only WETH holdings and no outstanding Comet balances before redemption.【F:contracts/src/VaultManager.sol†L255-L308】

- **Diagrams:**
  - [Message payment](./diagrams/pay-for-message.md)
  - [Policy edit](./diagrams/edit-policy.md)
  - [Vault investment lifecycle](./diagrams/vault-investment.md)
  - [MT redemption](./diagrams/redeem-weth.md)
  - Test mapping CSV: [test-matrix](./test-matrix.csv)
