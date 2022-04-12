# ERC20 Staking Reward Distribution

In the ERC20 token staking, When the staking token is same with the reward token, we can implement [step-staking](https://github.com/sushiswap/sushiswap/blob/master/contracts/SushiBar.sol)
This staking is the case when the staking token is different with reward token.

## Usage

### Installation

Install node packages

```console
$ yarn install
```

### Build

Build the smart contracts

```console
$ yarn compile
```

### Test

Run unit tests

```console
$ yarn test
```

### TypeChain

Compile the smart contracts and generate TypeChain artifacts:

```console
$ yarn typechain
```

### Lint Solidity

Lint the Solidity code:

```console
$ yarn lint:sol
```

### Lint TypeScript

Lint the TypeScript code:

```console
$ yarn lint:ts
```

### Coverage

Generate the code coverage report:

```console
$ yarn coverage
```

### Report Gas

See the gas usage per unit test and averate gas per method call:

```console
$ REPORT_GAS=true yarn test
```

### Clean

Delete the smart contract artifacts, the coverage reports and the Hardhat cache:

```console
$ yarn clean
```
