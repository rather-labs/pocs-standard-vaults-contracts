# StandardVaults Contracts

## Description

Smart contracts for the StandardVaults project, developed using the Hardhat framework.

## Installation

```bash
$ npm install
```

## Deploying on a local environment

```bash
# start hardhat node
$ npx hardhat node

# deploy NFT contract
$ npm run local:deploy

# mint an nft to the deployer's address
$ npx hardhat run scripts/mint.ts --network localhost
```

## Testing

```bash
# run unit tests
$ npm test

# run unit tests and get their coverage
$ npm run coverage
```