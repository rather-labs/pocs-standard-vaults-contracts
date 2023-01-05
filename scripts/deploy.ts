import { ethers, network } from 'hardhat';
const FormatTypes = ethers.utils.FormatTypes;

import fs from 'fs';

import { 
  SushiStakingVault,
  SushiStakingVault__factory,
  SushiStakingVaultFactory,
  SushiStakingVaultFactory__factory,
  SushiStakingLogic__factory,
  SushiStakingLogic,
} from '../typechain-types';
import { deployContract, waitForTx } from './helpers/utils';
import { ZERO_ADDRESS } from '../test/helpers/constants';

const ROUTER_ADDRESS = '0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506';
const MINICHEF_ADDRESS = '0x0769fd68dFb93167989C6f7254cd0D766Fb2841F';

async function main() {
  const provider = ethers.provider;
  let deployer;

  if (network.name == 'hardhat' || network.name == 'localhost') {
    const accounts = await ethers.getSigners();
    deployer = accounts[0];
  } else {
    deployer = new ethers.Wallet(
      process.env.DEPLOYER_PRIVATE_KEY as string,
      provider
    );
  }

  console.log('\n\t-- Deploying SushiStakingLogic Library --');
  const sushiLogic = await deployContract(
    new SushiStakingLogic__factory(deployer).deploy()
  );
  const libs = {
    'contracts/layer-1-vaults/staking/sushi/SushiStakingLogic.sol:SushiStakingLogic': sushiLogic.address
  };

  console.log('\n\t-- Deploying SushiStakingVault Contract --');
  const sushiVaultImplementation = await deployContract(
    new SushiStakingVault__factory(
      libs,
      deployer
    ).deploy()
  );
  console.log(`Deployed at: ${sushiVaultImplementation.address}`);

  console.log('\n\t-- Deploying SushiStakingVaultFactory Contract --');
  const sushiVaultFactory = await deployContract(
    new SushiStakingVaultFactory__factory(
      deployer
    ).deploy(
      sushiVaultImplementation.address,
      ROUTER_ADDRESS,
      MINICHEF_ADDRESS
    )
  );
  console.log(`Deployed at: ${sushiVaultFactory.address}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
