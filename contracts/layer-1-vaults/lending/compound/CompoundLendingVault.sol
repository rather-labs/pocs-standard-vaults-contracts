// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.17;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ICERC20} from "../../../interfaces/ICERC20.sol";
import {LibCompound} from "./lib/LibCompound.sol";
import {IComptroller} from "../../../interfaces/IComptroller.sol";

import {LendingBaseVault} from "../base/LendingBaseVault.sol";
import {ICompoundLendingVault} from './ICompoundLendingVault.sol';
import {CompoundERC4626__CompoundError} from '../../../Errors.sol';

/// @title CompoundLendingVault
/// @author ffarall, LucaCevasco
/// @notice ERC4626 wrapper for Compound Finance
contract CompoundLendingVault is LendingBaseVault, Initializable, ICompoundLendingVault {

    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------

    event Borrow(uint256 amount);

    event Repay(uint256 amount);

    /// -----------------------------------------------------------------------
    /// Libraries usage
    /// -----------------------------------------------------------------------

    using LibCompound for ICERC20;
    using SafeERC20 for ERC20;

    /// -----------------------------------------------------------------------
    /// Constants
    /// -----------------------------------------------------------------------

    uint256 internal constant _NO_ERROR = 0;

    /// -----------------------------------------------------------------------
    /// params
    /// -----------------------------------------------------------------------

    /// @notice The Compound cToken contract for the collateral asset
    ICERC20 public cToken;

    // @notice The underlying token asset
    ERC20 public underAsset;

    /// @notice The Compound comptroller contract
    IComptroller public comptroller;

    /// @notice The ratio between the value of the asset borrowed and the asset lent,
    /// in percentage terms with one decimal (for 75.5%, borrowRate = 755).
    uint256 public borrowRate;

    /// @notice The ratio between the value of the asset borrowed and the asset lent
    uint256 public asset2borrowAssetRate;

    /// @notice The Compound cToken contract for the borrowed asset
    ICERC20 public cToken2Borrow;

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

    constructor()
        ERC4626(IERC20(address(0)))
        ERC20('CompoundLendingVault', 'CLV') { }

    function initialize(ERC20 asset_, ICERC20 cToken_, IComptroller comptroller_, uint256 borrowRate_, uint256 asset2borrowAssetRate_, ICERC20 cToken2Borrow_) external initializer {
        // TODO make it onlyOwner and manage owner in creation
        cToken = cToken_;
        comptroller = comptroller_;
        underAsset = asset_;
        borrowRate = borrowRate_;
        cToken2Borrow = cToken2Borrow_;
        asset2borrowAssetRate = asset2borrowAssetRate_;
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

      ret = ICERC20(address(cToken2Borrow)).borrow(amount);
      require(ret == 0, "COMPOUND_BORROWER: cErc20.borrow failed");
    }

    /// @notice Repay the given amount of asset to Compound
    function repay(address from) public override {

      uint256 amountToRepay = ICERC20(address(cToken2Borrow)).borrowBalanceCurrent(from);
      // Approve tokens to Compound contract
      IERC20(address(cToken2Borrow)).approve(address(cToken2Borrow), amountToRepay);

      // Repay given amount to borrowed contract
      uint256 ret = ICERC20(address(cToken2Borrow)).repayBorrow(amountToRepay);
      require(ret == 0, "COMPOUND_BORROWER: cErc20.repay failed");


    }

    /// -----------------------------------------------------------------------
    /// ERC4626 overrides
    /// -----------------------------------------------------------------------

    function totalAssets() public view virtual override returns (uint256) {
        return cToken.viewUnderlyingBalanceOf(address(this));
    }

    function _beforeWithdraw(uint256 assets, address from) internal virtual override {
        /// -----------------------------------------------------------------------
        /// Withdraw assets from Compound
        /// -----------------------------------------------------------------------

        repay(from);
        emit Repay(assets);

        uint256 errorCode = cToken.redeemUnderlying(from, assets);
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
        uint256 errorCode = cToken.mintForSelfAndEnterMarket(assets);
        if (errorCode != _NO_ERROR) {
            revert CompoundERC4626__CompoundError(errorCode);
        }
        // borrow assets (assets 200 * borrowRate 75.5 = 150.1)
        uint256 valueInAssetBorrow = assets * asset2borrowAssetRate / 1000;
        uint256 amountBorrow = valueInAssetBorrow * borrowRate / 1000;
        borrow(amountBorrow);
        emit Borrow(amountBorrow);
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
}
