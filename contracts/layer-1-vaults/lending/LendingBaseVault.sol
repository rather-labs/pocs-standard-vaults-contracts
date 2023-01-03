// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import "../../Errors.sol";

/// @title LendingBaseVault
/// @author ffarall, LucaCevasco
/// @notice Abstract base contract for vaults using decentarlised lending protocols
/// @dev Adds borrowing interface to ERC4626 lending protocols vaults
abstract contract LendingBaseVault is IERC4626 {

    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------

    /// @notice Emitted when a shareholder borrows tokens form underlying protocol
    /// @param asset The asset borrowed
    /// @param borrower The address requesting the borrow position
    event Borrow(IERC20 indexed asset, address borrower);

    /// -----------------------------------------------------------------------
    /// Modifiers
    /// -----------------------------------------------------------------------

    /// @notice Reverts if caller is not a shareholder of this vault
    modifier onlyShareholder() {
        if (this.balanceOf(msg.sender) == 0) revert LendingBaseVault__NotShareholder({
            who: msg.sender
        });
        _;
    }

    /// -----------------------------------------------------------------------
    /// Storage variables
    /// -----------------------------------------------------------------------

    /// -----------------------------------------------------------------------
    /// External functions
    /// -----------------------------------------------------------------------

    /// @notice Opens a borrowing position for the sender, using the underlying
    /// lending protocol.
    /// @param asset The asset to borrow
    /// @param amount The amount to borrow
    function borrow(IERC20 asset, uint256 amount) external view virtual;

    /// @notice Closes a borrowing position for the sender, using the underlying
    /// lending protocol.
    /// @param asset The asset to repay
    /// @param amount The amount to repay
    function repay(IERC20 asset, uint256 amount) external view virtual;

    /// -----------------------------------------------------------------------
    /// Internal functions
    /// -----------------------------------------------------------------------
}
