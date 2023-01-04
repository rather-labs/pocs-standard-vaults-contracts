import '@nomiclabs/hardhat-ethers';
import {
  TransactionReceipt,
  TransactionResponse,
} from '@ethersproject/providers';
import { expect } from 'chai';
import { MAX_UINT256, ZERO_ADDRESS } from '../../../helpers/constants';
import {
  getAbbreviation,
  getTimestamp,
  matchEvent,
  waitForTx,
} from '../../../helpers/utils';
import {
  sushiVaultImplementation,
  sushiVaultFactory,
  makeSuiteCleanRoom,
  userAddress,
  abiCoder,
  user,
  USDC_ADDRESS,
  WETH_ADDRESS,
  POOL_ID_USDC_WETH,
} from '../../../__setup.spec';

describe('SushiVault', async () => { 
  it('creates a new clone of a SushiStakingVault', async () => {
    const data: string = abiCoder.encode(['address', 'uint'], [USDC_ADDRESS, POOL_ID_USDC_WETH]);
    const cloneAddress: string = await sushiVaultFactory.computeERC4626Address(WETH_ADDRESS);
    const receipt: TransactionReceipt = await waitForTx(sushiVaultFactory.createERC4626(WETH_ADDRESS, data));

    matchEvent(receipt, 'CreateERC4626', sushiVaultFactory, [
      WETH_ADDRESS,
      cloneAddress
    ]);
  });
});
