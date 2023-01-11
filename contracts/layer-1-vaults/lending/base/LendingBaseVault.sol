// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.17;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../../Errors.sol";

/// @title LendingBaseVault
/// @author ffarall, LucaCevasco
/// @notice Abstract base contract for vaults using decentarlised lending protocols
/// @dev Adds borrowing interface to ERC4626 lending protocols vaults
abstract contract LendingBaseVault is ERC4626 {

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
    /// Public variables
    /// -----------------------------------------------------------------------

    function convertCollateralToBorrow(uint256 amount) public view virtual returns (uint256);

    function convertBorrowToCollateral(uint256 amount) public view virtual returns (uint256);

    /// -----------------------------------------------------------------------
    /// Internal functions
    /// -----------------------------------------------------------------------

    /// @notice Opens a borrowing position for the sender, using the underlying
    /// lending protocol.
    /// @param amount The amount to borrow
    function _borrow(uint256 amount) internal virtual;

    /// @notice Closes a borrowing position for the sender, using the underlying
    /// lending protocol.
    /// @param from The address to repay the debt from
    function _repay(address from) internal virtual;

    function _beforeWithdraw(uint256 assets, address from) internal virtual {}

    function _afterDeposit(uint256 assets, uint256 shares) internal virtual {}

    /// -----------------------------------------------------------------------
    /// ERC4626 overrides
    /// -----------------------------------------------------------------------

    function deposit(uint256 assets, address receiver) public virtual override returns (uint256 shares) {
        require(assets <= maxDeposit(receiver), "ERC4626: deposit more than max");

        uint256 _shares = previewDeposit(assets);
        _deposit(_msgSender(), receiver, assets, _shares);

        _afterDeposit(assets, _shares);

        return _shares;
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public virtual override returns (uint256 shares) {
        require(assets <= maxWithdraw(owner), "ERC4626: withdraw more than max");

        _beforeWithdraw(assets, _msgSender());

        uint256 _shares = previewWithdraw(assets);
        _withdraw(_msgSender(), receiver, owner, assets, _shares);

        return _shares;
    }

    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal virtual override {
        // If _asset is ERC777, `transferFrom` can trigger a reenterancy BEFORE the transfer happens through the
        // `tokensToSend` hook. On the other hand, the `tokenReceived` hook, that is triggered after the transfer,
        // calls the vault, which is assumed not malicious.
        //
        // Conclusion: we need to do the transfer before we mint so that any reentrancy would happen before the
        // assets are transferred and before the shares are minted, which is a valid state.
        // slither-disable-next-line reentrancy-no-eth
        SafeERC20.safeTransferFrom(IERC20(asset()), caller, address(this), assets);
        _mint(receiver, shares);

        emit Deposit(caller, receiver, assets, shares);
    }

    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal virtual override {
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        // If _asset is ERC777, `transfer` can trigger a reentrancy AFTER the transfer happens through the
        // `tokensReceived` hook. On the other hand, the `tokensToSend` hook, that is triggered before the transfer,
        // calls the vault, which is assumed not malicious.
        //
        // Conclusion: we need to do the transfer after the burn so that any reentrancy would happen after the
        // shares are burned and after the assets are transferred, which is a valid state.
        _burn(owner, shares);
        SafeERC20.safeTransfer(IERC20(asset()), receiver, assets);

        emit Withdraw(caller, receiver, owner, assets, shares);
    }
}
