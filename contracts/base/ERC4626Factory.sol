// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.17;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

/// @title ERC4626Factory
/// @author ffarall, LucaCevasco
/// @notice Abstract base contract for deploying ERC4626 wrappers
/// @dev Uses CREATE2 deterministic deployment, so there can only be a single
/// vault for each asset.
abstract contract ERC4626Factory {

    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------

    /// @notice Emitted when a new ERC4626 vault has been created
    /// @param asset The base asset used by the vault
    /// @param vault The vault that was created
    event CreateERC4626(ERC20 indexed asset, ERC4626 vault);

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
    function createERC4626(IERC20 asset) external virtual returns (IERC4626 vault);

    /// @notice Computes the address of the ERC4626 vault corresponding to an asset. Returns
    /// a valid result regardless of whether the vault has already been deployed.
    /// @param asset The base asset used by the vault
    /// @return vault The vault corresponding to the asset
    function computeERC4626Address(IERC20 asset) external view virtual returns (IERC4626 vault) {
        vault = IERC4626(
            _computeCreate2Address(
                keccak256(
                    abi.encodePacked(
                        implementation,
                        asset
                    )
                )
            )
        );
    }

    /// -----------------------------------------------------------------------
    /// Internal functions
    /// -----------------------------------------------------------------------

    /// @notice Determines whether a vault is already deployed or not.
    /// @param bytecodeHash The keccak256 hash of the creation code of the contract being deployed concatenated
    /// with the ABI-encoded constructor arguments.
    /// @return exists true if vault exists, false otherwise.
    function _vaultExists(bytes32 bytecodeHash) internal view returns (bool exists) {
        address vault = _computeCreate2Address(bytecodeHash);
        uint32 size;
        assembly {
            size := extcodesize(vault)
        }
        return (size > 0);
    }

    /// @notice Computes the address of a contract deployed by this factory using CREATE2, given
    /// the bytecode hash of the contract. Can also be used to predict addresses of contracts yet to
    /// be deployed.
    /// @param bytecodeHash The keccak256 hash of the creation code of the contract being deployed concatenated
    /// with the ABI-encoded constructor arguments.
    /// @return vault The address of the deployed contract
    function _computeCreate2Address(bytes32 bytecodeHash) internal view virtual returns (address vault) {
        return Clones.predictDeterministicAddress(implementation, bytecodeHash, address(this));
    }
}
