// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.17;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC4626Factory} from "../../base/ERC4626Factory.sol";
import {DeltaNeutralVault, IDeltaNeutralVault, VaultParams} from "./DeltaNeutralVault.sol";
import "../../Errors.sol";

/// @title DeltaNeutralVaultFactory
/// @author ffarall, LucaCevasco
/// @notice Factory for creating DeltaNeutralVault contracts
contract DeltaNeutralVaultFactory is Ownable, ERC4626Factory {
    /// -----------------------------------------------------------------------
    /// Immutable params
    /// -----------------------------------------------------------------------

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

    constructor(address implementation_) {
        implementation = implementation_;
    }

    /// -----------------------------------------------------------------------
    /// ERC4626 overrides
    /// -----------------------------------------------------------------------

    function _initialize(ERC4626 vault, ERC20 asset, bytes memory data) internal virtual override {
        if (address(asset) == address(0)) revert InvalidAddress();

        (
            address lendingFactory, address lendingAsset, bytes memory lendingData,
            address stakingFactory, address stakingAsset, bytes memory stakingData
        ) = abi.decode(
            data, 
            (
                address, address, bytes, // Lending Vault
                address, address, bytes, // Staking Vault
            )
        );

        // Getting and pair
        IDeltaNeutralVault(address(vault)).initialize(
            VaultParams(lendingFactory, lendingAsset, lendingData),
            VaultParams(stakingFactory, stakingAsset, stakingData),
            msg.sender
        );
    }
}
