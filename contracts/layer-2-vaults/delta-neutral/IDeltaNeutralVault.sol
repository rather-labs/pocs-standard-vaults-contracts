// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.17;

import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626, IERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

import {ERC4626Factory} from "../../base/ERC4626Factory.sol";

/// -----------------------------------------------------------------------
/// Structs for params of contract
/// -----------------------------------------------------------------------

struct VaultParams {
    ERC4626Factory factory;
    ERC20 asset;
    bytes data;
}

interface IDeltaNeutralVault {
    function initialize(
        VaultParams memory lendingVaultParams,
        VaultParams memory stakingVaultParams,
        address deployer
    ) external;
}
