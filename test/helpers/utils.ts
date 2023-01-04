import '@nomiclabs/hardhat-ethers';
import {
  BigNumberish,
  Bytes,
  logger,
  utils,
  BigNumber,
  Contract,
  Signer,
} from 'ethers';
import { expect } from 'chai';
import { HARDHAT_CHAINID, MAX_UINT256 } from './constants';
import {
  BytesLike,
  hexlify,
  keccak256,
  RLP,
  toUtf8Bytes,
} from 'ethers/lib/utils';
import {
  TransactionReceipt,
  TransactionResponse,
} from '@ethersproject/providers';
import hre, { ethers } from 'hardhat';
import { readFileSync } from 'fs';
import { join } from 'path';

export function computeContractAddress(
  deployerAddress: string,
  nonce: number
): string {
  const hexNonce = hexlify(nonce);
  return '0x' + keccak256(RLP.encode([deployerAddress, hexNonce])).substr(26);
}

export function getChainId(): number {
  return hre.network.config.chainId || HARDHAT_CHAINID;
}

export function getAbbreviation(handle: string) {
  let slice = handle.substr(0, 4);
  if (slice.charAt(3) == ' ') {
    slice = slice.substr(0, 3);
  }
  return slice;
}

export async function waitForTx(
  tx: Promise<TransactionResponse> | TransactionResponse,
  skipCheck = false
): Promise<TransactionReceipt> {
  if (!skipCheck) await expect(tx).to.not.be.reverted;
  return await (await tx).wait();
}

export async function resetFork(): Promise<void> {
  await hre.network.provider.request({
    method: 'hardhat_reset',
    params: [
      {
        forking: {
          jsonRpcUrl: process.env.MAINNET_RPC_URL,
          blockNumber: 12012081,
        },
      },
    ],
  });
  console.log('\t> Fork reset');

  await hre.network.provider.request({
    method: 'evm_setNextBlockTimestamp',
    params: [1614290545], // Original block timestamp + 1
  });

  console.log('\t> Timestamp reset to 1614290545');
}

export async function getTimestamp(): Promise<any> {
  const blockNumber = await hre.ethers.provider.send('eth_blockNumber', []);
  const block = await hre.ethers.provider.send('eth_getBlockByNumber', [
    blockNumber,
    false,
  ]);
  return block.timestamp;
}

export async function setNextBlockTimestamp(timestamp: number): Promise<void> {
  await hre.ethers.provider.send('evm_setNextBlockTimestamp', [timestamp]);
}

export async function mine(blocks: number): Promise<void> {
  for (let i = 0; i < blocks; i++) {
    await hre.ethers.provider.send('evm_mine', []);
  }
}

let snapshotId = '0x1';
export async function takeSnapshot() {
  snapshotId = await hre.ethers.provider.send('evm_snapshot', []);
}

export async function revertToSnapshot() {
  await hre.ethers.provider.send('evm_revert', [snapshotId]);
}

export function expectEqualArrays(
  actual: BigNumberish[],
  expected: BigNumberish[]
) {
  if (actual.length != expected.length) {
    logger.throwError(
      `${actual} length ${actual.length} does not match ${expected} length ${expect.length}`
    );
  }

  let areEquals = true;
  for (let i = 0; areEquals && i < actual.length; i++) {
    areEquals = BigNumber.from(actual[i]).eq(BigNumber.from(expected[i]));
  }

  if (!areEquals) {
    logger.throwError(`${actual} does not match ${expected}`);
  }
}

export function loadTestResourceAsUtf8String(relativePathToResouceDir: string) {
  return readFileSync(
    join('test', 'resources', relativePathToResouceDir),
    'utf8'
  );
}

export async function signWithdrawal(
  signer: Signer,
  profileId: number,
  amount: number | string,
  expiration: number,
  nonce: number
): Promise<string> {
  const msgHash = ethers.utils.solidityKeccak256(
    ['uint256', 'uint256', 'uint256', 'uint256'],
    [profileId, amount, expiration, nonce]
  );
  const msgHashBinary = ethers.utils.arrayify(msgHash);
  return await signer.signMessage(msgHashBinary);
}

export async function currentTimestamp(): Promise<number> {
  const blockNumber = await ethers.provider.getBlockNumber();
  const block = await ethers.provider.getBlock(blockNumber);
  return block.timestamp;
}