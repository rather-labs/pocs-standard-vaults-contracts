import { BigNumber, ethers } from 'ethers';
import '@nomiclabs/hardhat-ethers';
import { TransactionReceipt } from '@ethersproject/providers';
import { expect } from 'chai';

import {
  matchEvent,
  mine,
  setStorageAt,
  waitForTx,
} from '../../../helpers/utils';
import { MAX_UINT256 } from '../../../helpers/constants';

import {
  compoundLendingVaultFactory,
  abiCoder,
  CWETH_ADDRESS,
  USDC_ADDRESS,
  USDC_BALANCE_SLOT,
  userOne,
  deployerAddress,
  wethToken,
  userOneAddress,
  usdcToken,
  CUSDC_ADDRESS,
  userTwoAddress,
  userTwo,
  cWethToken,
  WETH_ADDRESS,
  WETH_BALANCE_SLOT,
} from '../../../__setup.spec';
import COMPOUND_CLONE from '../../../../artifacts/contracts/layer-1-vaults/lending/compound/CompoundLendingVault.sol/CompoundLendingVault.json';
import { CompoundLendingVault } from '../../../../typechain-types/contracts/layer-1-vaults/lending/compound/CompoundLendingVault';
import { parseUnits } from 'ethers/lib/utils';

const ASSET_PRICE_FEED_ADDRESS = '0xF9680D99D6C9589e2a93a78A04A279e509205945';
const BORROW_ASSET_PRICE_FEED_ADDRESS = '0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7';

let compoundClone: CompoundLendingVault;

describe('CompoundVault', async () => {
  it('creates a new clone of a CompoundLendingVault and checks creation Event and correct owner', async () => {
    const data: string = abiCoder.encode(['address', 'address', 'address', 'address', 'address'], [CUSDC_ADDRESS, CWETH_ADDRESS, ASSET_PRICE_FEED_ADDRESS, BORROW_ASSET_PRICE_FEED_ADDRESS, deployerAddress]);

    const cloneAddress: string = await compoundLendingVaultFactory.computeERC4626Address(USDC_ADDRESS, data);
    const receipt: TransactionReceipt = await waitForTx(compoundLendingVaultFactory.createERC4626(USDC_ADDRESS, data));

    matchEvent(receipt, 'CreateERC4626', compoundLendingVaultFactory, [
      USDC_ADDRESS,
      cloneAddress
    ]);

    compoundClone = new ethers.Contract(cloneAddress, JSON.stringify(COMPOUND_CLONE.abi), userOne) as CompoundLendingVault;
    const cloneOwner: string = await compoundClone.owner();

    expect(
      cloneOwner, `Address of clone owner (${cloneOwner}) doesn't match with deployer (${deployerAddress})`
    ).to.be.equal(deployerAddress);
  });

  it('user one invests in vault', async () => {
    // Adding USDC balance to userOne
    const balanceSlotIndex: string = ethers.utils.solidityKeccak256(
      ['uint256', 'uint256'],
      [userOneAddress, USDC_BALANCE_SLOT] // key, slot
    );
    const expectedBalance: BigNumber = parseUnits('1000', 6);
    await setStorageAt(
      USDC_ADDRESS,
      balanceSlotIndex,
      expectedBalance
    );
    const usdcBalanceUserOne: BigNumber = await usdcToken.balanceOf(userOneAddress);

    expect(
      usdcBalanceUserOne, `User expected to have ${expectedBalance} USDC but got ${usdcBalanceUserOne} USDC.`
    ).to.be.equal(expectedBalance);

    // Depositing in Compound vault
    await usdcToken.connect(userOne).approve(compoundClone.address, MAX_UINT256);
    const userOnePreviewShares: BigNumber = await compoundClone.previewDeposit(usdcBalanceUserOne);
    await waitForTx(compoundClone.connect(userOne).deposit(usdcBalanceUserOne, userOneAddress));

    const userOneShares: BigNumber = await compoundClone.balanceOf(userOneAddress);
    expect(
      userOneShares, `User expected to get around ${userOnePreviewShares} but got ${userOneShares}.`
    ).to.be.approximately(userOnePreviewShares, userOnePreviewShares.mul(10).div(100));

    console.log(`User One invested ${usdcBalanceUserOne} USDC`);
  });

  it('user two invests in vault', async () => {
    // Adding USDC balance to userTwo
    const balanceSlotIndex: string = ethers.utils.solidityKeccak256(
      ['uint256', 'uint256'],
      [userTwoAddress, USDC_BALANCE_SLOT] // key, slot
    );
    const expectedBalance: BigNumber = parseUnits('4500', 6);
    await setStorageAt(
      USDC_ADDRESS,
      balanceSlotIndex,
      expectedBalance
    );
    const usdcBalanceUserTwo: BigNumber = await usdcToken.balanceOf(userTwoAddress);

    expect(
      usdcBalanceUserTwo, `User expected to have ${expectedBalance} USDC but got ${usdcBalanceUserTwo} USDC.`
    ).to.be.equal(expectedBalance);

    // Depositing in Compound vault
    await usdcToken.connect(userTwo).approve(compoundClone.address, MAX_UINT256);
    const userTwoPreviewShares: BigNumber = await compoundClone.previewDeposit(usdcBalanceUserTwo);
    await waitForTx(compoundClone.connect(userTwo).deposit(usdcBalanceUserTwo, userTwoAddress));

    const userTwoShares: BigNumber = await compoundClone.balanceOf(userTwoAddress);
    expect(
      userTwoShares, `User expected to get around ${userTwoPreviewShares} but got ${userTwoShares}.`
    ).to.be.approximately(userTwoPreviewShares, userTwoPreviewShares.mul(10).div(100));

    console.log(`User Two invested ${usdcBalanceUserTwo} USDC`);
  });

  it('user one withdraws from vault after blocks minted', async () => {
    // Time passes, debt accumulates and rewards for supplying accrues
    const blocks = 1000;
    await mine(blocks);
    
    // Checking debt accrued
    const vaultDebt: BigNumber = await cWethToken.borrowBalanceCurrent(compoundClone.address);
    const wethBorrowRate: BigNumber = await cWethToken.borrowRatePerBlock();
    const vaultWethBalance: BigNumber = await wethToken.balanceOf(compoundClone.address);
    const expectedOutstandingDebt: BigNumber = vaultWethBalance.mul(wethBorrowRate.mul(blocks)).div('1000000000000000000');
    const expectedDebt: BigNumber = expectedOutstandingDebt.add(vaultWethBalance);
    expect(
      vaultDebt, `Vault debt is ${vaultDebt} WETH and WETH balance is ${vaultWethBalance} WETH.`
    ).to.be.equal(expectedDebt);

    // Adding WETH balance to vault so that it can repay debt
    const balanceSlotIndex: string = ethers.utils.solidityKeccak256(
      ['uint256', 'uint256'],
      [userOneAddress, WETH_BALANCE_SLOT] // key, slot
    );
    await setStorageAt(
      WETH_ADDRESS,
      balanceSlotIndex,
      expectedOutstandingDebt
    );
    await wethToken.connect(userOne).transfer(compoundClone.address, expectedOutstandingDebt);
    const vaultNewWethBalance: BigNumber = await wethToken.balanceOf(compoundClone.address);

    expect(
      vaultNewWethBalance, `Vault expected to have ${expectedDebt} WETH but got ${vaultNewWethBalance} USDC.`
    ).to.be.equal(expectedDebt);

    // Redeem shares
    const userOneShares: BigNumber = await compoundClone.balanceOf(userOneAddress);
    const userOnePreviewWithdraw: BigNumber = await compoundClone.previewRedeem(userOneShares);

    await waitForTx(compoundClone.approve(compoundClone.address, MAX_UINT256));
    await waitForTx(compoundClone.connect(userOne).redeem(userOneShares, userOneAddress, userOneAddress));
    const userOneWithdrawnAssets: BigNumber = await usdcToken.balanceOf(userOneAddress);
    expect(
      userOneWithdrawnAssets, `User expected to get around ${userOnePreviewWithdraw} USDC but got ${userOneWithdrawnAssets} USDC.`
    ).to.be.approximately(userOnePreviewWithdraw, userOnePreviewWithdraw.mul(10).div(100));

    console.log(`After ${blocks} blocks, User One withdrew ${userOneWithdrawnAssets} USDC`);
  });
});