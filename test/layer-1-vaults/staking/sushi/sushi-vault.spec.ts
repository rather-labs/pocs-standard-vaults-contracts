import { ethers } from 'hardhat';
import '@nomiclabs/hardhat-ethers';
import { mine } from '@nomicfoundation/hardhat-network-helpers';
import {
  TransactionReceipt,
} from '@ethersproject/providers';
import { expect } from 'chai';
import {
  matchEvent,
  waitForTx,
  setStorageAt
} from '../../../../helpers/utils';
import {
  sushiVaultFactory,
  abiCoder,
  userOne,
  userTwo,
  USDC_ADDRESS,
  WETH_ADDRESS,
  POOL_ID_USDC_WETH,
  deployerAddress,
  wethToken,
  userOneAddress,
  userTwoAddress,
  WETH_BALANCE_SLOT,
} from '../../../__setup.spec';
import { SushiStakingVault } from '../../../../typechain-types';
import SUSHI_VAULT_ABI from '../../../../artifacts/contracts/layer-1-vaults/staking/sushi/SushiStakingVault.sol/SushiStakingVault.json';
import { MAX_UINT256 } from '../../../../helpers/constants';
import { parseEther } from 'ethers/lib/utils';
import { BigNumber } from 'ethers';

let sushiClone: SushiStakingVault;
let blocks: number;

describe('SushiVault', async () => {
  it('creates a new clone of a SushiStakingVault and checks creation Event and correct owner', async () => {
    const data: string = abiCoder.encode(['address', 'uint'], [USDC_ADDRESS, POOL_ID_USDC_WETH]);
    const cloneAddress: string = await sushiVaultFactory.computeERC4626Address(WETH_ADDRESS, data);
    const receipt: TransactionReceipt = await waitForTx(sushiVaultFactory.createERC4626(WETH_ADDRESS, data));

    matchEvent(receipt, 'CreateERC4626', sushiVaultFactory, [
      WETH_ADDRESS,
      cloneAddress
    ]);

    sushiClone = new ethers.Contract(cloneAddress, JSON.stringify(SUSHI_VAULT_ABI.abi), userOne) as SushiStakingVault;
    const cloneOwner: string = await sushiClone.owner();

    expect(
      cloneOwner, `Address of clone owner (${cloneOwner}) doesn't match with deployer (${deployerAddress})`
    ).to.be.equal(deployerAddress);
  });

  it('user one invests in vault', async () => {
    // Adding WETH balance to userOne
    const balanceSlotIndex: string = ethers.utils.solidityKeccak256(
      ['uint256', 'uint256'],
      [userOneAddress, WETH_BALANCE_SLOT] // key, slot
    );
    const expectedBalance: BigNumber = parseEther('10');
    await setStorageAt(
      WETH_ADDRESS,
      balanceSlotIndex,
      expectedBalance
    );
    const wethBalanceUserOne: BigNumber = await wethToken.balanceOf(userOneAddress);

    await wethToken.connect(userOne).approve(sushiClone.address, MAX_UINT256);
    const userOnePreviewShares: BigNumber = await sushiClone.previewDeposit(wethBalanceUserOne);
    await waitForTx(sushiClone.connect(userOne).deposit(wethBalanceUserOne, userOneAddress));

    const userOneShares: BigNumber = await sushiClone.balanceOf(userOneAddress);
    expect(
      userOneShares, `User expected to get around ${userOnePreviewShares} but got ${userOneShares}.`
    ).to.be.approximately(userOnePreviewShares, userOnePreviewShares.mul(10).div(100));

    console.log(`User One invested ${wethBalanceUserOne} WETH`);
  });

  it('user two invests in vault', async () => {
    // Adding WETH balance to userTwo
    const balanceSlotIndex: string = ethers.utils.solidityKeccak256(
      ['uint256', 'uint256'],
      [userTwoAddress, WETH_BALANCE_SLOT] // key, slot
    );
    const expectedBalance: BigNumber = parseEther('10');
    await setStorageAt(
      WETH_ADDRESS,
      balanceSlotIndex,
      expectedBalance
    );
    const wethBalanceUserTwo: BigNumber = await wethToken.balanceOf(userTwoAddress);

    await wethToken.connect(userTwo).approve(sushiClone.address, MAX_UINT256);
    const userTwoPreviewShares: BigNumber = await sushiClone.previewDeposit(wethBalanceUserTwo);
    await waitForTx(sushiClone.connect(userTwo).deposit(wethBalanceUserTwo, userTwoAddress));

    const userTwoShares: BigNumber = await sushiClone.balanceOf(userTwoAddress);
    expect(
      userTwoShares, `User expected to get around ${userTwoPreviewShares} but got ${userTwoShares}.`
    ).to.be.approximately(userTwoPreviewShares, userTwoPreviewShares.mul(10).div(100));
  });

  it('user one withdraws from vault after blocks minted', async () => {
    blocks = 15_770_000; // About a year goes by
    await mine(blocks);
    const userOneShares: BigNumber = await sushiClone.balanceOf(userOneAddress);
    const userOnePreviewWithdraw: BigNumber = await sushiClone.previewRedeem(userOneShares);

    await waitForTx(sushiClone.approve(sushiClone.address, MAX_UINT256));
    await waitForTx(sushiClone.connect(userOne).redeem(userOneShares, userOneAddress, userOneAddress));
    const userOneWithdrawnAssets: BigNumber = await wethToken.balanceOf(userOneAddress);
    expect(
      userOneWithdrawnAssets, `User expected to get around ${userOnePreviewWithdraw} WETH but got ${userOneWithdrawnAssets} WETH`
    ).to.be.approximately(userOnePreviewWithdraw, userOnePreviewWithdraw.mul(10).div(100));

    console.log(`After ${blocks} blocks, User One withdrew ${userOneWithdrawnAssets} WETH`);
  });
});