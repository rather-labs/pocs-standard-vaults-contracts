import { ethers, network } from 'hardhat';
const FormatTypes = ethers.utils.FormatTypes;

import fs from 'fs';

import { deployContract } from './helpers/utils';
import { CompoundLendingVaultFactory__factory } from '../typechain-types/factories/contracts/layer-1-vaults/lending/compound/CompoundLendingVaultFactory__factory';

const COMPTROLLER_ADDRESS = '0x05Df6C772A563FfB37fD3E04C1A279Fb30228621';
const CETH_ADDRESS = '0x64078a6189Bf45f80091c6Ff2fCEe1B15Ac8dbde';

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

  console.log('\n\t-- Deploying NFT Contract --');
  const compoundFactory = await deployContract(
    new CompoundLendingVaultFactory__factory(deployer).deploy(COMPTROLLER_ADDRESS, CETH_ADDRESS, deployer.address) // We initialy set the allowed minter to the deployer
  );
  const compoundFactoryData = {
    address: compoundFactory.address,
    abi: JSON.parse(compoundFactory.interface.format(FormatTypes.json) as string),
  };
  fs.writeFileSync(__dirname + '/../json_contracts/meatstick.json', JSON.stringify(compoundFactoryData));
  console.log(compoundFactoryData.address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
