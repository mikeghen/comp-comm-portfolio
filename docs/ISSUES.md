## Severe Issues
1. Locked USDC in MessageManager and PolicyManager.Both contracts take USDC without transferring to Vault.This effectively locks the usdc as there is no withdraw method.
     line 135 in MessageManager
     line 115 in PolicyManager

## Gas Optimizations
1. The string manipulation in line 184 of the function _applyEdit on can be done  more efficiently with inline assembly
    such as https://github.com/Vectorized/solady/blob/main/src/utils/LibString.sol

2. Variable Packing (minor)
    LOCK_START LOCK_DURATION UNLOCK_TIMESTAMP could be represented as u64 rather than u256 and possibly packed into a single variable


