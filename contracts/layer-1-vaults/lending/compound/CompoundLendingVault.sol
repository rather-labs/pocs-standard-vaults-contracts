// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.17;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ICERC20} from "../../../interfaces/ICERC20.sol";
import {LibCompound} from "./lib/LibCompound.sol";
import {IComptroller} from "../../../interfaces/IComptroller.sol";

import {LendingBaseVault} from "../base/LendingBaseVault.sol";
import {CompoundERC4626__CompoundError} from '../../../Errors.sol';

/// @title CompoundLendingVault
/// @author ffarall, LucaCevasco
/// @notice ERC4626 wrapper for Compound Finance
contract CompoundLendingVault is LendingBaseVault {
    /// -----------------------------------------------------------------------
    /// Libraries usage
    /// -----------------------------------------------------------------------

    using LibCompound for ICERC20;
    using SafeERC20 for ERC20;

    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------

    event ClaimRewards(uint256 amount);

    event Borrow(uint256 amount);

    event Repay(uint256 amount);

    /// -----------------------------------------------------------------------
    /// Constants
    /// -----------------------------------------------------------------------

    uint256 internal constant _NO_ERROR = 0;

    /// -----------------------------------------------------------------------
    /// Immutable params
    /// -----------------------------------------------------------------------

    /// @notice The Compound cToken contract
    ICERC20 public immutable cToken;

    // @notice The underlying token asset
    ERC20 public immutable underAsset;

    /// @notice The Compound comptroller contract
    IComptroller public immutable comptroller;

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

    constructor(ERC20 asset_, ICERC20 cToken_, IComptroller comptroller_)
        ERC4626(asset_)
        ERC20(_vaultName(asset_), _vaultSymbol(asset_))
    {
        cToken = cToken_;
        comptroller = comptroller_;
        underAsset = asset_;
    }

    /// -----------------------------------------------------------------------
    /// Compound liquidity mining - lending
    /// -----------------------------------------------------------------------

    /// @notice Borrow the given amount of asset from Compound
    function borrow(uint256 amount) public override {
      // Check account can borrow
      (uint256 ret, uint256 liquidity, uint256 shortfall) = comptroller.getAccountLiquidity(address(this));
      require(ret == 0, "COMPOUND_BORROWER: getAccountLiquidity failed.");
      require(shortfall == 0, "COMPOUND_BORROWER: Account underwater");
      require(liquidity > 0, "COMPOUND_BORROWER: Account doesn't have liquidity");

      ret = ICERC20(address(cToken)).borrow(amount);
      require(ret == 0, "COMPOUND_BORROWER: cErc20.borrow failed");
    }

    /// @notice Repay the given amount of asset to Compound
    function repay(uint256 amount) public override  {
      // Approve tokens to Compound contract
      IERC20(address(cToken)).approve(address(cToken), amount);

      // Repay given amount to borrowed contract
      uint256 ret = ICERC20(address(cToken)).repayBorrow(amount);
      require(ret == 0, "COMPOUND_BORROWER: cErc20.borrow failed");
    }

    /// -----------------------------------------------------------------------
    /// ERC4626 overrides
    /// -----------------------------------------------------------------------

    function totalAssets() public view virtual override returns (uint256) {
        return cToken.viewUnderlyingBalanceOf(address(this));
    }

    function _beforeWithdraw(uint256 assets, uint256 /*shares*/ ) internal virtual override {
        /// -----------------------------------------------------------------------
        /// Withdraw assets from Compound
        /// -----------------------------------------------------------------------

        uint256 errorCode = cToken.redeemUnderlying(assets);
        if (errorCode != _NO_ERROR) {
            revert CompoundERC4626__CompoundError(errorCode);
        }
    }

    function _afterDeposit(uint256 assets, uint256 /*shares*/ ) internal virtual override {
        /// -----------------------------------------------------------------------
        /// Deposit assets into Compound
        /// -----------------------------------------------------------------------

        // approve to cToken
        underAsset.safeApprove(address(cToken), assets);

        // deposit into cToken
        uint256 errorCode = cToken.mint(assets);
        if (errorCode != _NO_ERROR) {
            revert CompoundERC4626__CompoundError(errorCode);
        }
    }

    function maxDeposit(address) public view override returns (uint256) {
        if (comptroller.mintGuardianPaused(cToken)) {
            return 0;
        }
        return type(uint256).max;
    }

    function maxMint(address) public view override returns (uint256) {
        if (comptroller.mintGuardianPaused(cToken)) {
            return 0;
        }
        return type(uint256).max;
    }

    function maxWithdraw(address owner) public view override returns (uint256) {
        uint256 cash = cToken.getCash();
        uint256 assetsBalance = convertToAssets(balanceOf(owner));
        return cash < assetsBalance ? cash : assetsBalance;
    }

    function maxRedeem(address owner) public view override returns (uint256) {
        uint256 cash = cToken.getCash();
        uint256 cashInShares = convertToShares(cash);
        uint256 shareBalance = balanceOf(owner);
        return cashInShares < shareBalance ? cashInShares : shareBalance;
    }

    /// -----------------------------------------------------------------------
    /// ERC20 metadata generation
    /// -----------------------------------------------------------------------

    function _vaultName(ERC20 asset_) internal view virtual returns (string memory vaultName) {
        vaultName = string.concat("CompoundLendingVault-", asset_.symbol());
    }

    function _vaultSymbol(ERC20 asset_) internal view virtual returns (string memory vaultSymbol) {
        vaultSymbol = string.concat("CLV-", asset_.symbol());
    }
}
