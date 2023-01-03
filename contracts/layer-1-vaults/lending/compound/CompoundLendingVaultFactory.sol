// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.17;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

import {ICERC20} from "../../../interfaces/ICERC20.sol";
import {CompoundLendingVault} from "./CompoundLendingVault.sol";
import {IComptroller} from "../../../interfaces/IComptroller.sol";
import {ERC4626Factory} from "../../../base/ERC4626Factory.sol";

/// @title CompoundLendingVaultFactory
/// @author ffarall, LucaCevasco
/// @notice Factory for creating CompoundERC4626 contracts
contract CompoundLendingVaultFactory is ERC4626Factory {
    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------

    /// @notice Thrown when trying to deploy an CompoundERC4626 vault using an asset without a cToken
    error CompoundERC4626Factory__CTokenNonexistent();

    /// -----------------------------------------------------------------------
    /// Immutable params
    /// -----------------------------------------------------------------------

    /// @notice The address that will receive the liquidity mining rewards (if any)
    address public immutable rewardRecipient;

    /// @notice The Compound comptroller contract
    IComptroller public immutable comptroller;

    /// @notice The Compound cEther address
    address internal immutable cEtherAddress;

    /// -----------------------------------------------------------------------
    /// Storage variables
    /// -----------------------------------------------------------------------

    /// @notice Maps underlying asset to the corresponding cToken
    mapping(ERC20 => ICERC20) public underlyingToCToken;

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

    constructor(IComptroller comptroller_, address cEtherAddress_, address rewardRecipient_) {
        comptroller = comptroller_;
        cEtherAddress = cEtherAddress_;
        rewardRecipient = rewardRecipient_;

        // initialize underlyingToCToken
        ICERC20[] memory allCTokens = comptroller_.getAllMarkets();
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
    /// External functions
    /// -----------------------------------------------------------------------

    /// @inheritdoc ERC4626Factory
    function createERC4626(ERC20 asset) external virtual override returns (ERC4626 vault) {
        ICERC20 cToken = underlyingToCToken[asset];
        if (address(cToken) == address(0)) {
            revert CompoundERC4626Factory__CTokenNonexistent();
        }

        vault = new CompoundLendingVault{salt: bytes32(0)}(asset, cToken, rewardRecipient, comptroller);

        emit CreateERC4626(asset, vault);
    }

    /// @inheritdoc ERC4626Factory
    function computeERC4626Address(ERC20 asset) external view virtual override returns (ERC4626 vault) {
        vault = ERC4626(
            _computeCreate2Address(
                keccak256(
                    abi.encodePacked(
                        // Deployment bytecode:
                        type(CompoundLendingVault).creationCode,
                        // Constructor arguments:
                        abi.encode(asset, underlyingToCToken[asset], rewardRecipient, comptroller)
                    )
                )
            )
        );
    }

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
            if (address(cToken) != cEtherAddress) {
                underlyingToCToken[cToken.underlying()] = cToken;
            }

            unchecked {
                ++i;
            }
        }
    }
}
