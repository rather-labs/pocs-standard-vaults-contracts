// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.17;

/// -----------------------------------------------------------------------
/// Internal errors
/// -----------------------------------------------------------------------

error LendingBaseVault__NotShareholder(address who);
error StakingBaseVault_NotShareholder(address who);
 
/// -----------------------------------------------------------------------
/// External errors
/// -----------------------------------------------------------------------

error CompoundERC4626__CompoundError(uint256 errorCode);
