import { ethers } from 'hardhat';
import '@nomiclabs/hardhat-ethers';
import {
  TransactionReceipt,
} from '@ethersproject/providers';
import { expect } from 'chai';
import {
  matchEvent,
  waitForTx,
  mine,
  setStorageAt
} from '../helpers/utils';
import {
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
  deltaNeutralVaultFactory,
  CUSDC_ADDRESS,
  CWETH_ADDRESS,
  ASSET_PRICE_FEED_ADDRESS,
  BORROW_ASSET_PRICE_FEED_ADDRESS,
  compoundLendingVaultFactory,
  sushiVaultFactory,
  usdcToken,
  USDC_BALANCE_SLOT,
} from '../__setup.spec';
import { DeltaNeutralVault, SushiStakingVault } from '../../typechain-types';
import DELTA_NEUTRAL_VAULT_ABI from '../../artifacts/contracts/layer-2-vaults/delta-neutral/DeltaNeutralVault.sol/DeltaNeutralVault.json';
import { MAX_UINT256 } from '../helpers/constants';
import { parseEther, parseUnits } from 'ethers/lib/utils';
import { BigNumber } from 'ethers';

let deltaNeutralClone: DeltaNeutralVault;

describe.only('DeltaNeutralVault', async () => {
  it('creates a new clone of a DeltaNeutralVault and checks creation Event and correct owner', async () => {
    // Setting up parameters for underlying layer 1 vaults (we only)
    const lendingVaultData: string = abiCoder.encode(
      ['address', 'address', 'address', 'address', 'address'],
      [CUSDC_ADDRESS, CWETH_ADDRESS, ASSET_PRICE_FEED_ADDRESS, BORROW_ASSET_PRICE_FEED_ADDRESS, deployerAddress]
    );
    const stakingVaultData: string = abiCoder.encode(
      ['address', 'uint'],
      [USDC_ADDRESS, POOL_ID_USDC_WETH]
    );
    const deltaNeutralVaultData: string = abiCoder.encode(
      [
        'address', 'address', 'bytes', // Lending Vault
        'address', 'address', 'bytes' // Staking Vault
      ],
      [
        compoundLendingVaultFactory.address, USDC_ADDRESS, lendingVaultData, // Lending Vault
        sushiVaultFactory.address, WETH_ADDRESS, stakingVaultData // Staking Vault
      ]
    );

    // Deploying clone
    const cloneAddress: string = await deltaNeutralVaultFactory.computeERC4626Address(WETH_ADDRESS, deltaNeutralVaultData);
    const receipt: TransactionReceipt = await waitForTx(deltaNeutralVaultFactory.createERC4626(WETH_ADDRESS, deltaNeutralVaultData));

    matchEvent(receipt, 'CreateERC4626', deltaNeutralVaultFactory, [
      WETH_ADDRESS,
      cloneAddress
    ]);

    deltaNeutralClone = new ethers.Contract(cloneAddress, JSON.stringify(DELTA_NEUTRAL_VAULT_ABI.abi), userOne) as DeltaNeutralVault;
    const cloneOwner: string = await deltaNeutralClone.owner();

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

    // Depositing in Delta Neutral vault
    await usdcToken.connect(userOne).approve(deltaNeutralClone.address, MAX_UINT256);
    const userOnePreviewShares: BigNumber = await deltaNeutralClone.previewDeposit(usdcBalanceUserOne);
    // await deltaNeutralClone.connect(userOne).deposit(usdcBalanceUserOne, userOneAddress, {
    //   gasLimit: 2_000_000
    // });
    await waitForTx(deltaNeutralClone.connect(userOne).deposit(usdcBalanceUserOne, userOneAddress));

    const userOneShares: BigNumber = await deltaNeutralClone.balanceOf(userOneAddress);
    expect(
      userOneShares, `User expected to get around ${userOnePreviewShares} but got ${userOneShares}.`
    ).to.be.approximately(userOnePreviewShares, userOnePreviewShares.mul(10).div(100));

    console.log(`User One invested ${usdcBalanceUserOne} USDC`);
  });

  //   it('user two invests in vault', async () => {
  //     // Swapping some WETH
  //     const WNATIVE: string = await sushiRouter.WETH();
  //     const amountsOutQuote = await sushiRouter.getAmountsOut(parseEther('100'), [WNATIVE, WETH_ADDRESS]);
  //     const minAmountOut: BigNumber = amountsOutQuote[amountsOutQuote.length - 1].mul(95).div(100);

  //     await sushiRouter.connect(userTwo).swapExactETHForTokens(
  //       minAmountOut,
  //       [WNATIVE, WETH_ADDRESS],
  //       userTwoAddress,
  //       (await ethers.provider.getBlock('latest')).timestamp + 300,
  //       {
  //         value: parseEther('100000')
  //       }
  //     );

  //     const wethBalanceUserTwo: BigNumber = await wethToken.balanceOf(userTwoAddress);

  //     expect(
  //       wethBalanceUserTwo, 'User WETH balance is lower than 10 WETH'
  //     ).to.be.greaterThan(parseEther('10'));

  //     await wethToken.connect(userTwo).approve(sushiClone.address, MAX_UINT256);
  //     const userTwoPreviewShares: BigNumber = await sushiClone.previewDeposit(wethBalanceUserTwo);
  //     await waitForTx(sushiClone.connect(userTwo).deposit(wethBalanceUserTwo, userTwoAddress));

  //     const userTwoShares: BigNumber = await sushiClone.balanceOf(userTwoAddress);
  //     expect(
  //       userTwoShares, `User expected to get around ${userTwoPreviewShares} but got ${userTwoShares}.`
  //     ).to.be.approximately(userTwoPreviewShares, userTwoPreviewShares.mul(10).div(100));
  //   });

  //   it('user one withdraws from vault after blocks minted', async () => {
  //     const blocks = 100;
  //     await mine(blocks);
  //     const userOneShares: BigNumber = await sushiClone.balanceOf(userOneAddress);
  //     const userOnePreviewWithdraw: BigNumber = await sushiClone.previewRedeem(userOneShares);

  //     await waitForTx(sushiClone.approve(sushiClone.address, MAX_UINT256));
  //     await waitForTx(sushiClone.connect(userOne).redeem(userOneShares, userOneAddress, userOneAddress));
  //     const userOneWithdrawnAssets: BigNumber = await wethToken.balanceOf(userOneAddress);
  //     expect(
  //       userOneWithdrawnAssets, `User expected to get around ${userOnePreviewWithdraw} WETH but got ${userOneWithdrawnAssets} WETH`
  //     ).to.be.approximately(userOnePreviewWithdraw, userOnePreviewWithdraw.mul(10).div(100));

//     console.log(`After ${blocks} blocks, User One withdrew ${userOneWithdrawnAssets} WETH`);
//   });
});
