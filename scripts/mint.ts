import { ethers } from 'hardhat';
import { waitForTx } from './helpers/utils';
import meatMinterJson from '../json_contracts/meatminter.json';

async function main() {

  const accounts = await ethers.getSigners();
  const deployer = accounts[0];
  const meatMinter = await ethers.getContractAt('MeatMinter', meatMinterJson.address, deployer);

  console.log('Minting NFT...');
  const transactionResponse = meatMinter.safeMint(deployer.address, 'appendUri');
  await waitForTx(transactionResponse);
  console.log(`NFT minted to ${deployer.address}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });