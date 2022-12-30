// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

/// @title ERC4626Factory
/// @author ffarall, LucaCevasco
/// @notice Abstract base contract for deploying ERC4626 wrappers
/// @dev Uses CREATE2 deterministic deployment, so there can only be a single
/// vault for each asset.
contract ERC4626Factory {

    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------

    /// @notice Emitted when a new ERC4626 vault has been created
    /// @param asset The base asset used by the vault
    /// @param vault The vault that was created
    event CreateERC4626(IERC20 indexed asset, IERC4626 vault);

    /// -----------------------------------------------------------------------
    /// Storage variables
    /// -----------------------------------------------------------------------

    /// @notice Address of the implementation used for the clones
    address public implementation;

    /// -----------------------------------------------------------------------
    /// External functions
    /// -----------------------------------------------------------------------

    /// @notice Creates an ERC4626 vault for an asset
    /// @dev Uses CREATE2 deterministic deployment, so there can only be a single
    /// vault for each asset. Will revert if a vault has already been deployed for the asset.
    /// @param asset The base asset used by the vault
    /// @return vault The vault that was created
    function createERC4626(IERC20 asset) external virtual returns (IERC4626 vault) {
        // TODO check address is not yet used and deploy
    }

    /// @notice Computes the address of the ERC4626 vault corresponding to an asset. Returns
    /// a valid result regardless of whether the vault has already been deployed.
    /// @param asset The base asset used by the vault
    /// @return vault The vault corresponding to the asset
    function computeERC4626Address(IERC20 asset) external view virtual returns (IERC4626 vault) {
        // TODO hash asset and pass it as bytecodeHash
    }

    /// -----------------------------------------------------------------------
    /// Internal functions
    /// -----------------------------------------------------------------------

    /// @notice Computes the address of a contract deployed by this factory using CREATE2, given
    /// the bytecode hash of the contract. Can also be used to predict addresses of contracts yet to
    /// be deployed.
    /// @param bytecodeHash The keccak256 hash of the creation code of the contract being deployed concatenated
    /// with the ABI-encoded constructor arguments.
    /// @return The address of the deployed contract
    function _computeCreate2Address(bytes32 bytecodeHash) internal view virtual returns (address) {
        return Clones.predictDeterministicAddress(implementation, bytecodeHash, address(this));
    }
}
