import { ethers, network } from 'hardhat';
const FormatTypes = ethers.utils.FormatTypes;

import fs from 'fs';

import { Meatstick__factory, MeatMinter__factory } from '../typechain-types';
import { deployContract, waitForTx } from './helpers/utils';

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
  const meatstickContract = await deployContract(
    new Meatstick__factory(deployer).deploy(deployer.address) // We initialy set the allowed minter to the deployer
  );
  const meatstickData = {
    address: meatstickContract.address,
    abi: JSON.parse(meatstickContract.interface.format(FormatTypes.json) as string),
  };
  fs.writeFileSync(__dirname + '/../json_contracts/meatstick.json', JSON.stringify(meatstickData));
  console.log(meatstickContract.address);

  console.log('\n\t-- Deploying Allowed Minter Contract --');
  const meatminterContract = await deployContract(
    new MeatMinter__factory(deployer).deploy(meatstickContract.address)
  );
  const meatminterData = {
    address: meatminterContract.address,
    abi: JSON.parse(meatminterContract.interface.format(FormatTypes.json) as string),
  };
  fs.writeFileSync(__dirname + '/../json_contracts/meatminter.json', JSON.stringify(meatminterData));
  console.log(meatminterContract.address);

  console.log('\n\t-- Changing Meatstick allowed minter to MeatMinter contract --');
  const transactionResponse = meatstickContract.changeMinter(meatminterContract.address); // Then we update the minter
  await waitForTx(transactionResponse);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
