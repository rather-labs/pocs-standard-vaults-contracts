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
  CETH_ADDRESS,
  USDC_ADDRESS,
} from '../../../__setup.spec';

const BORROW_RATE = 700;
const ASSET_PRICE_FEED_ADDRESS = '0xF9680D99D6C9589e2a93a78A04A279e509205945';
const BORROW_ASSET_PRICE_FEED_ADDRESS = '0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7';

describe('CompoundVault', async () => {
  it('creates a new clone of a CompoundLendingVault', async () => {
    const data: string = abiCoder.encode(['address', 'uint256', 'address', 'address', 'address'], [USDC_ADDRESS, BORROW_RATE, CETH_ADDRESS, ASSET_PRICE_FEED_ADDRESS, BORROW_ASSET_PRICE_FEED_ADDRESS]);

    const cloneAddress: string = await compoundLendingVaultFactory.computeERC4626Address(USDC_ADDRESS, data);
    const receipt: TransactionReceipt = await waitForTx(compoundLendingVaultFactory.createERC4626(USDC_ADDRESS, data));

    matchEvent(receipt, 'CreateERC4626', compoundLendingVaultFactory, [
      USDC_ADDRESS,
      cloneAddress
    ]);
  });
});
