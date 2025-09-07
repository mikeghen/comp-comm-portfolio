# CompComm Portfolio Implementation Specification

## Overview
The CompComm Portfolio is a community-managed investment portfolio system that combines on-chain governance, payment gating, and DeFi integrations. The system enables users to pay for AI agent interactions with USDC, manages an editable investment policy stored on-chain, and operates a vault that can swap assets on Uniswap v3 and supply/withdraw from Compound v3. After an 18-month timelock, the portfolio consolidates to WETH for proportional redemption based on Management Token (MT) holdings.

## Architecture Components
1. **Pay for Messages**: Users pay 10 USDC to submit messages to the AI agent
2. **Pay for Policy Edits**: Users pay 1 USDC per 10 characters to edit the investment policy
3. **Mint Management Tokens**: Both payment types mint MT tokens (80% to user, 20% to dev)
4. **Agent Execution**: Off-chain agent reads events and executes portfolio actions
5. **Asset Management**: Vault swaps assets on Uniswap v3 and manages Compound v3 positions
6. **Timelock & Redemption**: After 18 months, assets consolidate to WETH for MT-based redemption

## Smart Contract Components

### 1. `CompCommToken` (ERC20 Management Token)
The governance and redemption token for the CompComm Portfolio system.

#### Inheritance
- `ERC20`
- `ERC20Burnable`
- `AccessControl`
- `Pausable`

#### Roles
- `MINTER_ROLE` - Can mint new tokens (granted to MessageManager and PolicyManager)
- `BURNER_ROLE` - Can burn tokens from accounts (granted to VaultManager for redemption)
- `PAUSER_ROLE` - Can pause/unpause transfers
- `DEFAULT_ADMIN_ROLE` - Admin role (contract owner)

#### Variables
- `string public constant name` - Token name: "CompComm Management Token"
- `string public constant symbol` - Token symbol: "MT"
- `uint8 public constant decimals` - Token decimals: 18

#### Methods
- **mint(address to, uint256 amount)** `onlyRole(MINTER_ROLE)`
  - Mints new MT tokens to specified address
- **burnFrom(address account, uint256 amount)** `onlyRole(BURNER_ROLE)`
  - Burns MT tokens from account (requires approval or BURNER_ROLE)
- **pause() / unpause()** `onlyRole(PAUSER_ROLE)`
  - Emergency pause functionality

### 2. `MessageManager`
Handles USDC payments for AI agent messages and MT token minting.

#### Variables
- `struct Message` - Contains messageHash (keccak256 of off-chain content), payer (who receives MT mint-back), and nonce (user nonce for replay protection)
- `mapping(bytes32 => bool) public paidMessages` - Maps sigHash to payment status
- `mapping(bytes32 => bool) public processedMessages` - Maps sigHash to processing status
- `address public usdc` - USDC token address
- `address public mtToken` - MT token address
- `address public dev` - Dev share receiver address
- `address public agent` - Agent address for marking messages processed
- `uint256 public constant MESSAGE_PRICE_USDC` - Message price: 10,000,000 (10 USDC with 6 decimals)
- `uint256 public constant MT_PER_MESSAGE_USER` - MT minted per message: 1e18 (1.0 MT with 18 decimals)
- `uint256 public constant DEV_BPS` - Dev share: 2000 (20% in basis points)

#### Methods
- **payForMessageWithSig(Message calldata m, bytes calldata sig, string calldata messageURI)**
  - Validates EIP-712 signature over Message struct
  - Transfers 10 USDC from msg.sender to contract
  - Mints 1.0 MT to payer and 0.2 MT to dev
  - Marks sigHash as paid
  - Emits `MessagePaid` event
- **markMessageProcessed(bytes32 sigHash)** `onlyRole(AGENT_ROLE)`
  - Marks message as processed by agent
  - Requires message to be paid but not yet processed
  - Emits `MessageProcessed` event

#### Events
- **MessagePaid**
  - `bytes32 indexed sigHash, address indexed payer, string messageURI, bytes32 messageHash, uint256 userMint, uint256 devMint`
- **MessageProcessed**
  - `bytes32 indexed sigHash, address indexed processor`

#### Access Control
- Uses `AccessControl` for `AGENT_ROLE`
- Only agent can mark messages as processed

### 3. `PolicyManager`
Manages the on-chain investment policy with paid editing functionality.

#### Variables
- `string public prompt` - Investment policy stored as ASCII text
- `uint256 public promptVersion` - Version counter that increments on each edit
- `address public usdc` - USDC token address
- `address public mtToken` - MT token address
- `address public dev` - Dev share receiver address
- `uint256 public constant EDIT_PRICE_PER_10_CHARS_USDC` - Edit price: 1,000,000 (1 USDC per 10 chars with 6 decimals)
- `uint256 public constant MT_PER_10CHARS_USER` - MT minted per 10 chars: 100,000,000,000,000,000 (0.1 MT with 18 decimals)
- `uint256 public constant DEV_BPS` - Dev share: 2000 (20% in basis points)

#### Methods
- **editPrompt(uint256 start, uint256 end, string calldata replacement)**
  - Validates edit range: `start <= end <= prompt.length`
  - Requires `replacement.length == end - start` (exact replacement)
  - Calculates cost: `costUnits = (replacement.length + 9) / 10` (round up)
  - Transfers `costUnits * 1e6` USDC from msg.sender
  - Mints `costUnits * 0.1e18` MT to msg.sender and 20% to dev
  - Applies edit: `prompt = prompt[0:start] + replacement + prompt[end:]`
  - Increments `promptVersion`
  - Emits `PromptEdited` event
- **getPrompt() external view returns (string memory, uint256 version)**
  - Returns current prompt and version
- **getPromptSlice(uint256 start, uint256 end) external view returns (string memory)**
  - Returns substring of prompt for gas efficiency
- **previewEditCost(uint256 changed) external pure returns (uint256 costUSDC, uint256 userMint, uint256 devMint)**
  - Calculates costs without executing

#### Events
- **PromptEdited**
  - `address indexed editor, uint256 start, uint256 end, uint256 replacementLen, uint256 changed, uint256 costUSDC, uint256 userMint, uint256 devMint, uint256 version`

### 4. `VaultManager`
Manages portfolio funds with timelock, DeFi integrations, and redemption functionality.

#### Variables
- `uint256 public immutable lockStart` - Deployment timestamp when timelock begins
- `uint256 public constant LOCK_DURATION` - Lock duration: 46,656,000 seconds (18 months)
- `uint256 public immutable unlockTimestamp` - Calculated as lockStart + LOCK_DURATION
- `mapping(address => bool) public allowedAssets` - Whitelist of allowed tokens (WETH, USDC, sUSDC, AERO)
- `mapping(address => bool) public allowedComets` - Whitelist of allowed Compound v3 markets (cUSDCv3, cWETHv3, etc.)
- `address public immutable weth` - WETH token address
- `address public immutable usdc` - USDC token address
- `address public immutable uniswapV3Router` - Uniswap v3 SwapRouter address
- `address public immutable cometRewards` - Compound v3 CometRewards address
- `address public mtToken` - MT token address
- `address public agent` - Agent address for executing operations
- `enum Phase` - Defines three phases: LOCKED, CONSOLIDATION, REDEMPTION

#### Methods

##### Uniswap v3 Integration
- **swapExactInputV3(address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOutMin, uint24 fee, uint160 sqrtPriceLimitX96)** `onlyAgentOrOwner`
  - Validates both tokens are in `allowedAssets`
  - If post-unlock, requires `tokenOut == weth` (consolidation only)
  - Executes swap via Uniswap v3 router
  - Emits `SwapExecuted` event

##### Compound v3 Integration
- **depositToComet(address comet, address asset, uint256 amount)** `onlyAgentOrOwner`
  - Validates comet and asset are allowed
  - Supplies asset to Compound v3 market
  - Emits `CometSupplied` event
- **withdrawFromComet(address comet, address asset, uint256 amount)** `onlyAgentOrOwner`
  - Withdraws asset from Compound v3 market
  - Emits `CometWithdrawn` event
- **claimComp(address comet, address to)** `onlyAgentOrOwner`
  - Claims COMP rewards from Compound v3
  - Emits `CompClaimed` event

##### Phase Management & Redemption
- **getCurrentPhase() external view returns (Phase)**
  - Returns current phase based on timestamp and consolidation status
- **isConsolidated() external view returns (bool)**
  - Checks if all non-WETH balances are zero
  - Loops through `allowedAssets` and `allowedComets` for positions
- **redeemWETH(uint256 mtAmount, address to) external**
  - Requires `getCurrentPhase() == Phase.REDEMPTION`
  - Burns MT tokens from msg.sender
  - Calculates pro-rata WETH: `(wethBalance * mtAmount) / totalSupply`
  - Transfers WETH to specified address
  - Emits `Redeemed` event

##### Admin Functions
- **setAllowedAsset(address token, bool allowed)** `onlyOwner`
- **setAllowedComet(address comet, bool allowed)** `onlyOwner`
- **setAgent(address newAgent)** `onlyOwner`
- **pause() / unpause()** `onlyOwner`
- **sweep(address token, address to)** `onlyOwner`
  - Emergency sweep with phase-based restrictions

#### Events
- **SwapExecuted**
  - `address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut`
- **CometSupplied**
  - `address comet, address asset, uint256 amount`
- **CometWithdrawn**
  - `address comet, address asset, uint256 amount`
- **CompClaimed**
  - `address comet, address to, uint256 amount`
- **Redeemed**
  - `address account, address to, uint256 mtBurned, uint256 wethOut`

#### Access Control & Security
- Uses `Ownable2Step` for owner transitions
- Uses `AccessControl` for `AGENT_ROLE`
- Uses `ReentrancyGuard` on external calls
- Uses `Pausable` for emergency stops

### 5. `CompCommPortfolio` (Main Contract)
The main contract that inherits from all manager contracts and coordinates the system.

#### Inheritance
```solidity
contract CompCommPortfolio is MessageManager, PolicyManager, VaultManager, Ownable2Step, Pausable {
    // Combines functionality from all manager contracts
}
```

#### Constructor Parameters
```solidity
constructor(
    address _usdc,
    address _weth,
    address _mtToken,
    address _uniswapV3Router,
    address _cometRewards,
    address _dev,
    address _agent,
    string memory _initialPrompt
) {
    // Initialize all manager contracts
    // Set up initial allowlists
    // Configure roles and permissions
}
```

#### Initialization Functions
- **initializeAllowlists()**
  - Sets up initial allowed assets (WETH, USDC, sUSDC, AERO)
  - Sets up initial allowed Comets (cUSDCv3, cWETHv3, cAEROv3, sSUSDv3)
- **setupRoles()**
  - Grants `MINTER_ROLE` to MessageManager and PolicyManager
  - Grants `BURNER_ROLE` to VaultManager
  - Grants `AGENT_ROLE` to agent address

## Interface Dependencies

### External Contracts
```solidity
interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }
    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

interface IComet {
    function supply(address asset, uint amount) external;
    function withdraw(address asset, uint amount) external;
    function balanceOf(address account) external view returns (uint256);
}

interface ICometRewards {
    function claimTo(address comet, address to, bool shouldAccrue) external returns (uint256);
}
```

## Security Considerations

### Access Control
- **Role-Based Permissions**: Uses OpenZeppelin's AccessControl for granular permissions
- **Two-Step Ownership**: Uses Ownable2Step to prevent accidental ownership transfers
- **Agent Role**: Restricts critical functions to authorized agent address

### Reentrancy Protection
- **ReentrancyGuard**: Applied to all functions that make external calls
- **Checks-Effects-Interactions**: Follows pattern in all state-changing functions

### Economic Security
- **Fixed Pricing**: Uses hardcoded USDC prices to avoid oracle manipulation
- **Dev Share**: 20% dev share on all MT minting provides aligned incentives
- **Timelock**: 18-month lock prevents premature fund access

### Upgrade Safety
- **Non-Upgradeable**: Core contracts are non-upgradeable to maximize trust
- **Immutable References**: Critical addresses are immutable where possible

### Centralization Risks
- **Agent Overridability**
  - Agent uses a private key and could bypass paying for messages or editing the prompt.
  - Same issue exsist for manaing the funds in the vault.
  - Still can't withdraw funds from the vault, bc of the timelock.
  - Make this clear to the users, users would see on chain if the agent did this since no message would exist.

## Deployment Configuration

### Constructor Parameters
```solidity
// Base Mainnet Addresses
USDC: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913
WETH: 0x4200000000000000000000000000000000000006
UniswapV3Router: 0x2626664c2603336E57B271c5C0b26F421741e481
CometRewards: 0x123... // Base Compound v3 rewards contract

// Initial Allowlists
Assets: [WETH, USDC, sUSDC, AERO]
Comets: [cUSDCv3, cWETHv3, cAEROv3, sSUSDv3]
```

### Deployment Steps
1. Deploy `CompCommToken` with proper roles
2. Deploy `CompCommPortfolio` with all parameters
3. Grant `MINTER_ROLE` and `BURNER_ROLE` to portfolio contract
4. Configure initial allowlists
5. Set up agent and dev addresses
6. Initialize with starting prompt

## Testing Requirements

### Unit Tests
- **Token Minting**: Verify correct MT amounts minted for messages and edits
- **Payment Validation**: Test EIP-712 signature verification and replay protection
- **Prompt Editing**: Test string manipulation, cost calculation, and version tracking
- **Swap Execution**: Mock Uniswap v3 interactions and validate swap logic
- **Compound Integration**: Mock Comet interactions for supply/withdraw/claim
- **Phase Transitions**: Test timelock phases and consolidation logic
- **Redemption Math**: Verify pro-rata WETH calculation and MT burning

### Integration Tests
- **End-to-End Flow**: Test complete user journey from payment to redemption
- **Agent Operations**: Test agent message processing and vault operations
- **Emergency Scenarios**: Test pause functionality and emergency sweeps
- **Edge Cases**: Test boundary conditions for edits, swaps, and redemptions

### Security Tests
- **Access Control**: Verify only authorized addresses can call restricted functions
- **Reentrancy**: Test protection against reentrancy attacks
- **Integer Overflow**: Test edge cases for large numbers and calculations
- **Front-Running**: Consider MEV protection for time-sensitive operations

## Gas Optimization

### Storage Optimization
- Pack structs to minimize storage slots
- Use immutable for constants and deployment-time values
- Optimize mapping access patterns

### Function Optimization
- Use `external` vs `public` appropriately
- Minimize redundant storage reads
- Batch operations where possible
- Use events for off-chain indexing instead of storage

## Monitoring & Events

### Critical Events
- `MessagePaid` - Track user payments and MT minting
- `PromptEdited` - Monitor policy changes and community governance
- `SwapExecuted` - Track portfolio rebalancing activities
- `Redeemed` - Monitor token redemptions and vault drawdowns

### Off-Chain Integration
- Agent monitors `MessagePaid` events to process user requests
- Frontend tracks `PromptEdited` events to display current policy
- Analytics dashboard aggregates swap and position data
- Governance interface displays MT holder distribution
