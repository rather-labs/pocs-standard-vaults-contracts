import { AbiCoder } from '@ethersproject/abi';
import { parseEther } from '@ethersproject/units';
import '@nomiclabs/hardhat-ethers';
import { expect } from 'chai';
import { Signer } from 'ethers';
import { ethers } from 'hardhat';
import { ZERO_ADDRESS } from './helpers/constants';
import { revertToSnapshot, takeSnapshot } from './helpers/utils';
import { CompoundLendingVault } from '../typechain-types/contracts/layer-1-vaults/lending/compound/CompoundLendingVault';
import { CompoundLendingVaultFactory } from '../typechain-types/contracts/layer-1-vaults/lending/compound/CompoundLendingVaultFactory';
import {
  SushiStakingVault,
  SushiStakingVault__factory,
  SushiStakingVaultFactory,
  SushiStakingVaultFactory__factory,
  SushiStakingLogic__factory,
  SushiStakingLogic,
  CompoundLendingVault__factory,
  CompoundLendingVaultFactory__factory,
  IUniswapV2Router02,
} from '../typechain-types';
import { ERC20 } from '../typechain-types/@openzeppelin/contracts/token/ERC20';
import ERC20_ABI from '../artifacts/@openzeppelin/contracts/token/ERC20/ERC20.sol/ERC20.json';
import UNISWAP_ROUTER_ABI from '../artifacts/contracts/interfaces/IUniswapV2Router02.sol/IUniswapV2Router02.json';

export const USDC_ADDRESS = '0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174';
export const WETH_ADDRESS = '0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619';
export const POOL_ID_USDC_WETH = 1;
export const ROUTER_ADDRESS = '0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506';
export const MINICHEF_ADDRESS = '0x0769fd68dFb93167989C6f7254cd0D766Fb2841F';
export const FACTORY_ADDRESS = '0xc35DADB65012eC5796536bD9864eD8773aBc74C4';

export const COMPTROLLER_ADDRESS = '0x52eaCd19E38D501D006D2023C813d7E37F025f37';
export const CETH_ADDRESS = '0x52eaCd19E38D501D006D2023C813d7E37F025f37';

export let accounts: Signer[];
export let deployer: Signer;
export let userOne: Signer;
export let userTwo: Signer;
export let deployerAddress: string;
export let userOneAddress: string;
export let userTwoAddress: string;
export let abiCoder: AbiCoder;

// Useful existing contracts
export let wethToken: ERC20;
export let usdcToken: ERC20;
export let sushiRouter: IUniswapV2Router02;

// SushiStakingVault
export let sushiLogic: SushiStakingLogic;
export let sushiVaultImplementation: SushiStakingVault;
export let sushiVaultFactory: SushiStakingVaultFactory;

// CompoundLendingVault
export let compoundLendingVaultImplementation: CompoundLendingVault;
export let compoundLendingVaultFactory: CompoundLendingVaultFactory;

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
  userOne = accounts[1];
  userTwo = accounts[2];

  deployerAddress = await deployer.getAddress();
  userOneAddress = await userOne.getAddress();
  userTwoAddress = await userTwo.getAddress();

  // Getting existing contracts
  wethToken = new ethers.Contract(WETH_ADDRESS, JSON.stringify(ERC20_ABI.abi), userOne) as ERC20;
  usdcToken = new ethers.Contract(USDC_ADDRESS, JSON.stringify(ERC20_ABI.abi), userOne) as ERC20;
  sushiRouter = new ethers.Contract(ROUTER_ADDRESS, JSON.stringify(UNISWAP_ROUTER_ABI.abi), userOne) as IUniswapV2Router02;

  // Deploying SushiStakingLogic library
  sushiLogic = await new SushiStakingLogic__factory(deployer).deploy();
  const libs = {
    'contracts/layer-1-vaults/staking/sushi/SushiStakingLogic.sol:SushiStakingLogic': sushiLogic.address
  };

  // Deploying SushiVault and Factory contracts
  sushiVaultImplementation = await new SushiStakingVault__factory(
    libs,
    deployer
  ).deploy();

  sushiVaultFactory = await new SushiStakingVaultFactory__factory(
    deployer
  ).deploy(
    sushiVaultImplementation.address,
    ROUTER_ADDRESS,
    MINICHEF_ADDRESS
  );

  // Deploying CompoundLendingVault and Factory contracts
  compoundLendingVaultImplementation = await new CompoundLendingVault__factory(
    deployer
  ).deploy();

  compoundLendingVaultFactory = await new CompoundLendingVaultFactory__factory(deployer)
    .deploy(compoundLendingVaultImplementation.address, COMPTROLLER_ADDRESS, CETH_ADDRESS);

});
