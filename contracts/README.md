## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```

## Deployment Addresses

### Ethereum Sepolia
```
=== Deployment Summary ===
  chainId: 11155111
  admin: 0x6940f92719aeD29CaeD06A8A0Fa7A7290Db4f70F
  agent: 0x47933ECd70eafbc34eD0232258440f8bAd1eA828
  dev: 0x6940f92719aeD29CaeD06A8A0Fa7A7290Db4f70F
  USDC: 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238
  WETH: 0x2D5ee574e710219a521449679A4A7f2B43f046ad
  router: 0x3bFA4769FB09eefC5a80d6E87c3B9C650f7Ae48E
  cometRewards: 0x8bF5b658bdF0388E8b482ED51B14aef58f90abfD
  COMET_USDC: 0xAec1F48e02Cfb822Be958B68C7957156EB3F0b6e
  COMET_WETH: 0x2943ac1216979aD8dB76D9147F64E61adc126e96
  additionalAsset[0]: 0xA6c8D1c55951e8AC44a0EaA959Be5Fd21cc07531
  additionalAsset[1]: 0xa035b9e130F2B1AedC733eEFb1C67Ba4c503491F
  MT: 0x8D4CacB5597190Ce5e4Ac8C7cDd0EA9cB9518fC5
  PolicyManager: 0x37163AFf12B1dEF863166e8BC6041c652363c5E3
  MessageManager: 0x85D02A57cDD3f1376E1330E9564dD11f4Fa106CD
  VaultManager: 0xcA65e79DBe6aD61DAB0F1AA0473121adDAc6F97c
==========================
```