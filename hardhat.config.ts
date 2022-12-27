import '@nomicfoundation/hardhat-toolbox';
import '@nomiclabs/hardhat-etherscan';
import 'hardhat-spdx-license-identifier';
import { HardhatUserConfig } from 'hardhat/config';
import dotenv from 'dotenv';
import glob from 'glob';
import path from 'path';

import { accounts } from './helpers/test-wallets';
import { eNetwork } from './helpers/types';
import { HARDHATEVM_CHAINID } from './helpers/hardhat-constants';
import { NETWORKS_RPC_URL } from './helper-hardhat-config';
dotenv.config({ path: '../.env' });

if (!process.env.SKIP_LOAD) {
  glob.sync('./tasks/**/*.ts').forEach((file) => {
    require(path.resolve(file));
  });
}

const DEFAULT_BLOCK_GAS_LIMIT = 12450000;

const FORKING = process.env.FORKING === 'true';
const MAINNET_FORK = process.env.MAINNET_FORK === 'true';
const HARDHAT_FORK_BLOCK_NUMBER = process.env.HARDHAT_FORK_BLOCK_NUMBER || false;

const TRACK_GAS = process.env.TRACK_GAS === 'true';
const BLOCK_EXPLORER_KEY = process.env.BLOCK_EXPLORER_KEY || '';

const getCommonNetworkConfig = (networkName: eNetwork) => ({
  url: NETWORKS_RPC_URL[networkName] ?? '',
});

const networkFork = MAINNET_FORK
  ? {
    enabled: FORKING,
    url: NETWORKS_RPC_URL['mainnet'],
    blockNumber: HARDHAT_FORK_BLOCK_NUMBER ? parseInt(HARDHAT_FORK_BLOCK_NUMBER) : undefined,
  }
  : {
    enabled: FORKING,
    url: NETWORKS_RPC_URL['testnet'],
    blockNumber: HARDHAT_FORK_BLOCK_NUMBER ? parseInt(HARDHAT_FORK_BLOCK_NUMBER) : undefined,
  };

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: '0.8.17',
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
            details: {
              yul: true,
            },
          },
        },
      },
    ],
  },
  defaultNetwork: 'hardhat',
  networks: {
    main: getCommonNetworkConfig(eNetwork.mainnet),
    testnet: getCommonNetworkConfig(eNetwork.testnet),
    hardhat: {
      blockGasLimit: DEFAULT_BLOCK_GAS_LIMIT,
      gas: DEFAULT_BLOCK_GAS_LIMIT,
      chainId: HARDHATEVM_CHAINID,
      throwOnTransactionFailures: true,
      throwOnCallFailures: true,
      accounts: accounts.map(({ secretKey, balance }: { secretKey: string; balance: string }) => ({
        privateKey: secretKey,
        balance,
      })),
      forking: networkFork,
    },
  },
  gasReporter: {
    enabled: TRACK_GAS,
  },
  spdxLicenseIdentifier: {
    overwrite: false,
    runOnCompile: false,
  },
  etherscan: {
    apiKey: BLOCK_EXPLORER_KEY,
  },
};

export default config;
