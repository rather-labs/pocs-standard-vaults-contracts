import { ethers } from 'hardhat';
import { CompoundLendingVaultFactory__factory } from '../typechain-types/factories/contracts/layer-1-vaults/lending/compound/CompoundLendingVaultFactory__factory';

import { deployWithVerify } from './helpers/utils';

const COMPTROLLER_ADDRESS = '0x6F809eABA306dAaf5892a33C77d323b33b7a7Fd5';
const CETH_ADDRESS = '0x6F809eABA306dAaf5892a33C77d323b33b7a7Fd5';

async function main() {
  const provider = ethers.provider;
  const deployer = new ethers.Wallet(
    process.env.DEPLOYER_PRIVATE_KEY as string,
    provider
  );

  const contractFilePath = 'contracts/layer-1-vaults/lending/compound/CompoundLendingVaultFactory.sol:CompoundLendingVaultFactory';

  console.log('\n\t-- Deploying CompoundLendingVaultFactory and verifying --');
  const nftContract = await deployWithVerify(
    new CompoundLendingVaultFactory__factory(deployer).deploy(COMPTROLLER_ADDRESS, CETH_ADDRESS, deployer.address),
    [COMPTROLLER_ADDRESS, CETH_ADDRESS, deployer.address],
    contractFilePath
  );

  console.log(nftContract.address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
