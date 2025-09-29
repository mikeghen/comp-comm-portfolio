# Compound Community Portfolio (CompComm)

This is a community‑managed portfolio that doesn’t use token voting. Instead, it pilots a Pay‑to‑Govern (P2G) model where anyone can pay to send messages (proposals) or pay to edit the on‑chain policy that guides an AI agent to perform the execution (or not execution depending on the policy). Those payments go straight into the portfolio, and contributors receive a Management Token (MT) that redeems pro‑rata for WETH from the portfolio at its terminal state.

## Overview
This is a template for developers looking to build an assistant that can interact with the Compound Finance on the blockchain. It consists of a backend server and a frontend client that can be run locally or deployed to the cloud. 

### Preview
![Compound Assistant Preview](./preview.png)

## System Architecture
![System Architecture](./docs/images/compcomm_arch.png)

## Code Architecture
```mermaid
flowchart TB
    User(User) --> FrontendApp
    
    subgraph "Frontend"
        FrontendApp[Compound Assistant App]
    end
    
    subgraph "Backend"
        BackendAPI[Compound Assistant API]
        PrivateKey[Private Key]
    end
    
    subgraph "Ethereum"
        MessageManager[MessageManager]
        PolicyManager[PolicyManager]
        VaultManager[VaultManager]
        CompoundFinance[Compound V3]
        UniswapV3[Uniswap V3]
    end
    

    FrontendApp -- "WebSocket" --> BackendAPI
    FrontendApp -- "Pay for Messages" --> MessageManager
    FrontendApp -- "Pay for Policy Edits" --> PolicyManager
    FrontendApp -- "Read Holdings" --> VaultManager
    BackendAPI -- "Listen for Events" --> MessageManager
    BackendAPI -- "Portfolio Management" --> VaultManager
    VaultManager -- "DeFi Operations" --> CompoundFinance
    VaultManager -- "DeFi Operations" --> UniswapV3
    MessageManager -- "Revenue" --> VaultManager
    PolicyManager -- "Revenue" --> VaultManager
    PrivateKey --> BackendAPI
    PolicyManager -- "Read Prompt" --> BackendAPI
    
    classDef user fill:#fae5d3,stroke:#d35400,stroke-width:2px,color:black
    classDef frontend fill:#d5f5e3,stroke:#196f3d,stroke-width:2px,color:black
    classDef backend fill:#d5f5e3,stroke:#196f3d,stroke-width:2px,color:black
    classDef contracts fill:#e3f2fd,stroke:#1976d2,stroke-width:2px,color:black
    classDef compoundfinance fill:#c8e6c9,stroke:#2e7d32,stroke-width:2px,color:black
    classDef uniswappv3 fill:#ffb6c1,stroke:#ff69b4,stroke-width:2px,color:black
    classDef privatekey fill:#f7dc6f,stroke:#b7950b,stroke-width:2px,color:black
    
    class User user
    class FrontendApp frontend
    class BackendAPI backend
    class MessageManager,PolicyManager,VaultManager contracts
    class PrivateKey privatekey
    class CompoundFinance compoundfinance
    class UniswapV3 uniswappv3
```

You can find a sample agent prompt in the `backend/compound_assistant/config/agent.yaml` file.

## Requirements
- Python 3.10+
- Poetry for package management and tooling
  - [Poetry Installation Instructions](https://python-poetry.org/docs/#installation)
- [OpenAI API Key](https://platform.openai.com/docs/quickstart#create-and-export-an-api-key)
- Private Key for the EVM account you want the assistant to use
- Node.js 18+ and npm for the frontend

Additionally, Docker Compose can be used to run the application in a containerized environment, without these dependencies.

## Running the Compound Assistant
### From Shell

The application consists of a backend server and a frontend client that need to be run in separate terminal windows:

#### Shell 1: Backend Setup
```bash
cd backend
cp .env.example .env  # Create and edit with your credentials
poetry install
poetry run python server.py
```

#### Shell 2: Frontend Setup
```bash
cd frontend
npm install
npm start
```

The frontend will be available at http://localhost:3000, and it will connect to the backend running on http://localhost:8000.

Connect your wallet using the button in the navigation bar to start interacting with the assistant. 

### From Docker

```bash
docker compose up
```

This will start the backend server and the frontend client. The frontend will be available at http://localhost:3000, and it will connect to the backend running on http://localhost:8000.

# Funded by Compound Grants Program
Compound Assistant is funded by the Compound Grants Program. Learn more about the Grant on Questbook [here](https://new.questbook.app/dashboard/?role=builder&chainId=10&proposalId=678c218180bdbe26619c3ae8&grantId=66f29bb58868f5130abc054d). For support, please reach out the owner of this repository: @mikeghen.

# Disclaimer
This is an experimental project and is not audited. Use at your own risk.