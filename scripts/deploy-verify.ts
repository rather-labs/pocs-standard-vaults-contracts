import fs from 'fs';
import { ethers } from 'hardhat';
import { parseUnits } from 'ethers/lib/utils';
import { CompoundLendingVaultFactory__factory } from '../typechain-types/factories/contracts/layer-1-vaults/lending/compound/CompoundLendingVaultFactory__factory';

import { deployWithVerify } from './helpers/utils';
import { CompoundLendingVault__factory, DeltaNeutralVaultFactory__factory, DeltaNeutralVault__factory, SushiStakingLogic__factory, SushiStakingVaultFactory__factory, SushiStakingVault__factory } from '../typechain-types';

// Sushi addresses
const ROUTER_ADDRESS = '0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506';
const MINICHEF_ADDRESS = '0x0769fd68dFb93167989C6f7254cd0D766Fb2841F';

// Compound like addresses
const COMPTROLLER_ADDRESS = '0x20CA53E2395FA571798623F1cFBD11Fe2C114c24';
const CWETH_ADDRESS = '0x7ef18d0a9C3Fb1A716FF6c3ED0Edf52a2427F716';

async function main() {
  const provider = ethers.provider;
  const deployer = new ethers.Wallet(
    process.env.DEPLOYER_PRIVATE_KEY as string,
    provider
  );

  // Deploying SushiStakingVault and Factory contracts
  const sushiLogicContractFilePath = 'contracts/layer-1-vaults/staking/sushi/SushiStakingLogic.sol:SushiStakingLogic';
  const sushiLogic = await deployWithVerify(
    new SushiStakingLogic__factory(deployer).deploy(
      { gasPrice: parseUnits('60', 9) }
    ),
    [],
    sushiLogicContractFilePath
  );

  const libs = {
    'contracts/layer-1-vaults/staking/sushi/SushiStakingLogic.sol:SushiStakingLogic': sushiLogic.address
  };

  const sushiVaultContractFilePath = 'contracts/layer-1-vaults/staking/sushi/SushiStakingVault.sol:SushiStakingVault';
  const sushiStakingVaultImplementation = await deployWithVerify(
    new SushiStakingVault__factory(
      libs,
      deployer
    ).deploy(
      { gasPrice: parseUnits('60', 9) }
    ),
    [],
    sushiVaultContractFilePath
  );

  const sushiVaultFactoryContractFilePath = 'contracts/layer-1-vaults/staking/sushi/SushiStakingVaultFactory.sol:SushiStakingVaultFactory';
  const sushiStakingVaultFactory = await deployWithVerify(
    new SushiStakingVaultFactory__factory(
      deployer
    ).deploy(
      sushiStakingVaultImplementation.address,
      ROUTER_ADDRESS,
      MINICHEF_ADDRESS,
      { gasPrice: parseUnits('60', 9) }
    ),
    [
      sushiStakingVaultImplementation.address,
      ROUTER_ADDRESS,
      MINICHEF_ADDRESS
    ],
    sushiVaultFactoryContractFilePath
  );

  console.log(`--- SushiStakingVault implementation deployed in address: ${sushiStakingVaultImplementation.address}`);
  console.log(`--- SushiStakingFactory deployed in address: ${sushiStakingVaultFactory.address}`);

  // Deploying CompoundLendingVault and Factory contracts
  const compoundVaultContractFilePath = 'contracts/layer-1-vaults/lending/compound/CompoundLendingVault.sol:CompoundLendingVault';
  const compoundLendingVaultImplementation = await deployWithVerify(
    new CompoundLendingVault__factory(deployer).deploy(
      { gasPrice: parseUnits('60', 9) }
    ),
    [],
    compoundVaultContractFilePath
  );

  const compoundVaultFactoryContractFilePath = 'contracts/layer-1-vaults/lending/compound/CompoundLendingVaultFactory.sol:CompoundLendingVaultFactory';
  const compoundLendingVaultFactory = await deployWithVerify(
    new CompoundLendingVaultFactory__factory(deployer).deploy(
      compoundLendingVaultImplementation.address,
      COMPTROLLER_ADDRESS,
      CWETH_ADDRESS,
      { gasPrice: parseUnits('60', 9) }
    ),
    [compoundLendingVaultImplementation.address, COMPTROLLER_ADDRESS, CWETH_ADDRESS],
    compoundVaultFactoryContractFilePath
  );

  console.log(`--- CompoundStakingVault implementation deployed in address: ${compoundLendingVaultImplementation.address}`);
  console.log(`--- CompoundStakingVault factory deployed in address: ${compoundLendingVaultFactory.address}`);

  // Deploying DeltaNeutralVault and Factory contracts
  const deltaNeutralVaultContractFilePath = 'contracts/layer-2-vaults/delta-neutral/DeltaNeutralVault.sol:DeltaNeutralVault';
  const deltaNeutralVaultImplementation = await deployWithVerify(
    new DeltaNeutralVault__factory(deployer).deploy(
      { gasPrice: parseUnits('60', 9) }
    ),
    [],
    deltaNeutralVaultContractFilePath
  );

  const deltaNeutralVaultFactoryContractFilePath = 'contracts/layer-2-vaults/delta-neutral/DeltaNeutralVaultFactory.sol:DeltaNeutralVaultFactory';
  const deltaNeutralVaultFactory = await deployWithVerify(
    new DeltaNeutralVaultFactory__factory(deployer).deploy(
      deltaNeutralVaultImplementation.address,
      { gasPrice: parseUnits('60', 9) }
    ),
    [deltaNeutralVaultImplementation.address],
    deltaNeutralVaultFactoryContractFilePath
  );

  console.log(`--- DeltaNeutralVault implementation deployed in address: ${deltaNeutralVaultImplementation.address}`);
  console.log(`--- DeltaNeutralVault factory deployed in address: ${deltaNeutralVaultFactory.address}`);

  // Save addresses of all contracts
  const addrs = {
    'SushiStakingLogic': sushiLogic.address,
    'SushiStakingVaultImplementation': sushiStakingVaultImplementation.address,
    'SushiStakingVaultFactory': sushiStakingVaultFactory.address,
    'CompoundLendingVaultImplementation': compoundLendingVaultImplementation.address,
    'CompoundLendingVaultFactory': compoundLendingVaultFactory.address,
    'DeltaNeutralVaultImplementation': deltaNeutralVaultImplementation.address,
    'DeltaNeutralVaultFactory': deltaNeutralVaultFactory.address
  };

  const json = JSON.stringify(addrs, null, 2);
  fs.writeFileSync('addresses.json', json, 'utf-8');

}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
