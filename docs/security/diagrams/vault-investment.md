```mermaid
flowchart TD
    subgraph Actors
        Owner[Owner Multisig]
        Agent[Designated Agent]
    end
    subgraph Vault[VaultManager]
        VA[Allowed Assets]
        VC[Allowed Comets]
        Router[Uniswap V3 Router]
        Comet[Compound v3 Comet]
    end
    subgraph Tokens
        USDC[USDC]
        WETH[WETH]
        Alt[Other Allowlisted Asset]
    end

    Owner -->|setAllowedAsset / setAllowedComet| VA
    Owner -->|setAssetComet| VC
    Owner -->|setAgent| Agent
    Agent -->|exactInputSingle| Router
    Router -->|tokenOut| Vault
    Agent -->|supply(asset)| Comet
    Comet -->|position tokens| Vault
    Comet -->|withdraw(asset)| Vault
    Vault -->|claimComp| Owner

    VA --> Vault
    VC --> Vault
```
