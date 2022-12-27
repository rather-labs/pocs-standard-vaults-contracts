import { ethers } from 'hardhat';

import { Meatstick__factory } from '../typechain-types';
import { deployWithVerify } from './helpers/utils';

async function main() {
  const provider = ethers.provider;
  const deployer = new ethers.Wallet(
    process.env.DEPLOYER_PRIVATE_KEY as string,
    provider
  );

  const contractFilePath = 'contracts/Meatstick.sol:Meatstick';

  console.log('\n\t-- Deploying Meatstick NFT and verifying --');
  const nftContract = await deployWithVerify(
    new Meatstick__factory(deployer).deploy(),
    [],
    contractFilePath
  );
  
  console.log(nftContract.address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
