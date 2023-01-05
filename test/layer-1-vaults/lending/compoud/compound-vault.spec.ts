import '@nomiclabs/hardhat-ethers';
import {
  TransactionReceipt,
} from '@ethersproject/providers';
import {
  matchEvent,
  waitForTx,
} from '../../../helpers/utils';
import {
  compoundLendingVaultFactory,
  abiCoder,
  WETH_ADDRESS,
  COMPTROLLER_ADDRESS,
  CETH_ADDRESS,
} from '../../../__setup.spec';

describe('CompoundVault', async () => {
  it('creates a new clone of a CompoundLendingVault', async () => {
    const data: string = abiCoder.encode(['address', 'address'], [COMPTROLLER_ADDRESS, CETH_ADDRESS]);
    const cloneAddress: string = await compoundLendingVaultFactory.computeERC4626Address(WETH_ADDRESS);
    const receipt: TransactionReceipt = await waitForTx(compoundLendingVaultFactory.createERC4626(WETH_ADDRESS, data));

    matchEvent(receipt, 'CreateERC4626', compoundLendingVaultFactory, [
      WETH_ADDRESS,
      cloneAddress
    ]);
  });
});
