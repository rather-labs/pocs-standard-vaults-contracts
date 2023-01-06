// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.17;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import {ICERC20} from "../../../interfaces/ICERC20.sol";
import {CompoundLendingVault} from "./CompoundLendingVault.sol";
import {IComptroller} from "../../../interfaces/IComptroller.sol";
import {ERC4626Factory} from "../../../base/ERC4626Factory.sol";
import {ICompoundLendingVault} from './ICompoundLendingVault.sol';

import "../../../Errors.sol";

/// @title CompoundLendingVaultFactory
/// @author ffarall, LucaCevasco
/// @notice Factory for creating CompoundERC4626 contracts
contract CompoundLendingVaultFactory is Ownable, ERC4626Factory {
    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------

    /// @notice Thrown when trying to deploy an CompoundERC4626 vault using an asset without a cToken
    error CompoundERC4626Factory__CTokenNonexistent();

    /// -----------------------------------------------------------------------
    /// Immutable params
    /// -----------------------------------------------------------------------

    /// @notice The Compound comptroller contract
    IComptroller public immutable comptroller;

    /// @notice The Compound cEther address
    address internal immutable _cEtherAddress;

    /// -----------------------------------------------------------------------
    /// Storage variables
    /// -----------------------------------------------------------------------

    /// @notice Maps underlying asset to the corresponding cToken
    mapping(ERC20 => ICERC20) public underlyingToCToken;

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

    constructor(address implementation_, IComptroller comptroller_, address cEtherAddress_) {
        implementation = implementation_;
        comptroller = comptroller_;
        _cEtherAddress = cEtherAddress_;

        // initialize underlyingToCToken
        ICERC20[] memory allCTokens = comptroller_.getAlliTokens();
        uint256 numCTokens = allCTokens.length;
        ICERC20 cToken;
        for (uint256 i; i < numCTokens;) {
            cToken = allCTokens[i];
            if (address(cToken) != cEtherAddress_) {
                underlyingToCToken[cToken.underlying()] = cToken;
            }

            unchecked {
                ++i;
            }
        }
    }

    /// -----------------------------------------------------------------------
    /// ERC4626 overrides
    /// -----------------------------------------------------------------------

    function _initialize(ERC4626 vault, ERC20 asset, bytes memory data) internal virtual override {
        if (address(asset) == address(0)) revert InvalidAddress();

        (address cEtherAddress_, uint256 borrowRate, uint256 asset2borrowAssetRate, ICERC20 asset2Borrow) = abi.decode(data, (address, uint256, uint256, ICERC20));
        if (address(cEtherAddress_) == address(0)) revert InvalidAddress();

        ICompoundLendingVault(address(vault)).initialize(
          asset, ICERC20(cEtherAddress_), comptroller, borrowRate, asset2borrowAssetRate, asset2Borrow
        );
    }

     function createERC4626(ERC20 asset, bytes calldata data) external virtual override returns (ERC4626 vault) {
      // decode only last param
        
        (ICERC20 asset2Borrow) = abi.decode(data, (ICERC20));

        bytes32 salt = keccak256(
            abi.encodePacked(
                implementation,
                asset,
                asset2Borrow
            )
        );
        vault = ERC4626(Clones.cloneDeterministic(implementation, salt));

        _initialize(vault, asset, data);

        emit CreateERC4626(asset, vault);
    }

    /// @notice Computes the address of the ERC4626 vault corresponding to an asset. Returns
    /// a valid result regardless of whether the vault has already been deployed.
    /// @param asset The base asset used by the vault
    /// @return vault The vault corresponding to the asset
    function computeERC4626Address(ERC20 asset, bytes calldata data) external view virtual override returns (ERC4626 vault) {
      (ICERC20 asset2Borrow) = abi.decode(data, (ICERC20));

        vault = ERC4626(
            _computeCreate2Address(
                keccak256(
                    abi.encodePacked(
                        implementation,
                        asset,
                        asset2Borrow
                    )
                )
            )
        );
    }
    
    /// -----------------------------------------------------------------------
    /// External functions
    /// -----------------------------------------------------------------------

    /// @notice Updates the underlyingToCToken mapping in order to support newly added cTokens
    /// @dev This is needed because Compound doesn't have an onchain registry of cTokens corresponding to underlying assets.
    /// @param newCTokenIndices The indices of the new cTokens to register in the comptroller.allMarkets array
    function updateUnderlyingToCToken(uint256[] calldata newCTokenIndices) external {
        uint256 numCTokens = newCTokenIndices.length;
        ICERC20 cToken;
        uint256 index;
        for (uint256 i; i < numCTokens;) {
            index = newCTokenIndices[i];
            cToken = comptroller.allMarkets(index);
            if (address(cToken) != _cEtherAddress) {
                underlyingToCToken[cToken.underlying()] = cToken;
            }

            unchecked {
                ++i;
            }
        }
    }
}
