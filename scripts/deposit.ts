import { ethers } from 'hardhat';
import { defaultAbiCoder, parseUnits } from 'ethers/lib/utils';
import { TransactionReceipt } from '@ethersproject/abstract-provider';

import { DeltaNeutralVaultFactory, DeltaNeutralVaultFactory__factory, DeltaNeutralVault__factory } from '../typechain-types';

import contractAddresses from '../addresses.json';
import { waitForTx } from '../helpers/utils';

// ERC20 tokens
const USDC_ADDRESS = '0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174';
const WETH_ADDRESS = '0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619';
// Sushi-like protocol
const POOL_ID_USDC_WETH = 1;
// Compound-like protocol
const CWETH_ADDRESS = '0x7ef18d0a9C3Fb1A716FF6c3ED0Edf52a2427F716';
const CUSDC_ADDRESS = '0x73CF8c5D14Aa0EbC89f18272A568319F5BAB6cBD';
// Chainlink
const ASSET_PRICE_FEED_ADDRESS = '0xF9680D99D6C9589e2a93a78A04A279e509205945';
const BORROW_ASSET_PRICE_FEED_ADDRESS = '0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7';

// Gas handling
const gasLimit = undefined;
const gasPrice = parseUnits('70', 'gwei');

async function main() {
  const user = new ethers.Wallet(
    process.env.USER_PRIVATE_KEY as string,
    ethers.provider
  );

  const lendingVaultData: string = defaultAbiCoder.encode(
    ['address', 'address', 'address', 'address', 'address'],
    [CUSDC_ADDRESS, CWETH_ADDRESS, ASSET_PRICE_FEED_ADDRESS, BORROW_ASSET_PRICE_FEED_ADDRESS, user.address]
  );

  const stakingVaultData: string = defaultAbiCoder.encode(
    ['address', 'uint'],
    [USDC_ADDRESS, POOL_ID_USDC_WETH]
  );

  const deltaNeutralVaultData: string = defaultAbiCoder.encode(
    [
      'address', 'address', 'bytes', // Lending Vault
      'address', 'address', 'bytes' // Staking Vault
    ],
    [
      contractAddresses['CompoundLendingVaultFactory'], USDC_ADDRESS, lendingVaultData, // Lending Vault
      contractAddresses['SushiStakingVaultFactory'], WETH_ADDRESS, stakingVaultData // Staking Vault
    ]
  );

  const deltaNeutralFactory = DeltaNeutralVaultFactory__factory.connect(contractAddresses['DeltaNeutralVaultFactory'], user);
  const vaultAddress = await deltaNeutralFactory.computeERC4626Address(USDC_ADDRESS, deltaNeutralVaultData);

  const deltaNeutralVault = DeltaNeutralVault__factory.connect(vaultAddress, user);
  const tx = await deltaNeutralVault.deposit(
    parseUnits('2', 'mwei'),
    user.address,
    {
      gasLimit,
      gasPrice
    }
  );

  const receipt: TransactionReceipt = await tx.wait();

  console.log(receipt.logs);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });