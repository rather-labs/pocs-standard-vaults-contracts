// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.17;

error LendingBaseVault__NotShareholder(address who);
error StakingBaseVault_NotShareholder(address who);

error CompoundERC4626__CompoundError(uint256 errorCode);
error InvalidAddress();
error SushiStakingVaultFactory__InvalidPoolID();
