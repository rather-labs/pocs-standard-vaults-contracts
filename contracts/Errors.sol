// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.17;

error InvalidAddress();

error ERC4626Factory__VaultExistsAlready(address vault);

error LendingBaseVault__NotShareholder(address who);

error CompoundERC4626__MarketNotListed(address cToken);
error CompoundERC4626__CompoundError(uint256 errorCode);
error CompoundERC4626__InvalidPrice(int256 price, address priceFeed);
error CompoundERC4626Factory__CTokenNonexistent();

error SushiStakingVaultFactory__InvalidPoolID();
