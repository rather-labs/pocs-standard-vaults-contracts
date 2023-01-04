import { AbiCoder } from '@ethersproject/abi';
import { parseEther } from '@ethersproject/units';
import '@nomiclabs/hardhat-ethers';
import { expect } from 'chai';
import { Signer } from 'ethers';
import { ethers } from 'hardhat';
import { ZERO_ADDRESS } from './helpers/constants';
import { revertToSnapshot, takeSnapshot } from './helpers/utils';
import {
  SushiStakingVault,
  SushiStakingVault__factory,
  SushiStakingVaultFactory,
  SushiStakingVaultFactory__factory,
} from '../typechain-types';

export const USDC_ADDRESS = '0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174';
export const WETH_ADDRESS = '0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619';
export const ROUTER_ADDRESS = '0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506';
export const MINICHEF_ADDRESS = '0x0769fd68dFb93167989C6f7254cd0D766Fb2841F';

export let accounts: Signer[];
export let deployer: Signer;
export let user: Signer;
export let deployerAddress: string;
export let userAddress: string;
export let abiCoder: AbiCoder;

// SushiStakingVault
export let sushiVaultImplementation: SushiStakingVault;
export let sushiVaultFactory: SushiStakingVaultFactory;

export function makeSuiteCleanRoom(name: string, tests: () => void) {
  describe(name, () => {
    beforeEach(async () => {
      await takeSnapshot();
    });
    tests();
    afterEach(async () => {
      await revertToSnapshot();
    });
  });
}

before(async () => {
  abiCoder = ethers.utils.defaultAbiCoder;
  accounts = await ethers.getSigners();
  deployer = accounts[0];
  user = accounts[1];

  deployerAddress = await deployer.getAddress();
  userAddress = await user.getAddress();

  // Deploying SushiVault and Factory
  sushiVaultImplementation = await new SushiStakingVault__factory(deployer).deploy(
    ZERO_ADDRESS,
    ZERO_ADDRESS,
    ZERO_ADDRESS,
    ZERO_ADDRESS,
    ZERO_ADDRESS,
    ZERO_ADDRESS,
    0
  );
  sushiVaultFactory = await new SushiStakingVaultFactory__factory(deployer).deploy(
    sushiVaultImplementation.address,
    ROUTER_ADDRESS,
    MINICHEF_ADDRESS
  );
});
