// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.17;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import {ICERC20} from "../../../interfaces/ICERC20.sol";
import {LibCompound} from "./lib/LibCompound.sol";
import {IComptroller} from "../../../interfaces/IComptroller.sol";

import {LendingBaseVault} from "../base/LendingBaseVault.sol";
import {ICompoundLendingVault} from './ICompoundLendingVault.sol';
import '../../../Errors.sol';

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

    /// @notice For Compound error handling
    uint256 internal constant _NO_ERROR = 0;
    
    /// @notice Decimals used for Chainlink price conversion
    uint256 internal constant _DECIMALS = 18;

    /// -----------------------------------------------------------------------
    /// Public params
    /// -----------------------------------------------------------------------

    /// @notice The Compound cToken contract for the collateral asset
    ICERC20 public cToken;

    // @notice The underlying token asset
    ERC20 public underAsset;

    /// @notice The Compound comptroller contract
    IComptroller public comptroller;

    /// @notice The ratio of the value of the asset used as collateral vs the
    /// value of what is to be borrowed, in percentage terms with one decimal
    // (for 75.5%, borrowRate = 755).
    uint256 public borrowRate;

    /// @notice The Compound cToken contract for the borrowed asset
    ICERC20 public cTokenToBorrow;

    /// @notice The Chainlink price feed for the asset of this vault
    AggregatorV3Interface public assetPriceFeed;

    /// @notice The Chainlink price feed for the asset to borrow
    AggregatorV3Interface public borrowAssetPriceFeed;

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

    constructor()
        ERC4626(IERC20(address(0)))
        ERC20('CompoundLendingVault', 'CLV') { }

    function initialize(
        ERC20 asset_, 
        ICERC20 cToken_, 
        IComptroller comptroller_, 
        uint256 borrowRate_, 
        ICERC20 cTokenToBorrow_,
        AggregatorV3Interface assetPriceFeed_, 
        AggregatorV3Interface borrowAssetPriceFeed_
    ) external initializer {
        cToken = cToken_;
        comptroller = comptroller_;
        underAsset = asset_;
        borrowRate = borrowRate_;
        cTokenToBorrow = cTokenToBorrow_;
        assetPriceFeed = assetPriceFeed_;
        borrowAssetPriceFeed = borrowAssetPriceFeed_;
    }

    /// -----------------------------------------------------------------------
    /// LendingBaseVault overrides
    /// -----------------------------------------------------------------------

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
        
        // borrow
        uint256 valueInAssetBorrow = _convertCollateralToBorrow(assets);
        uint256 amountBorrow = valueInAssetBorrow * borrowRate / 1000;
        _borrow(amountBorrow);
    }

    function _beforeWithdraw(uint256 assets, address from) internal virtual override {
        /// -----------------------------------------------------------------------
        /// Withdraw assets from Compound
        /// -----------------------------------------------------------------------

        _repay(from);

        uint256 errorCode = cToken.redeemUnderlying(from, assets);
        if (errorCode != _NO_ERROR) {
            revert CompoundERC4626__CompoundError(errorCode);
        }
    }

    /// @notice Borrow the given amount of asset from Compound
    function _borrow(uint256 amount) internal override {
        // Check account can borrow
        (uint256 ret, uint256 liquidity, uint256 shortfall) = comptroller.getAccountLiquidity(address(this));
        require(ret == 0, "COMPOUND_BORROWER: getAccountLiquidity failed.");
        require(shortfall == 0, "COMPOUND_BORROWER: Account underwater");
        require(liquidity > 0, "COMPOUND_BORROWER: Account doesn't have liquidity");

        ret = ICERC20(address(cTokenToBorrow)).borrow(amount);
        require(ret == 0, "COMPOUND_BORROWER: cErc20.borrow failed");

        emit Borrow(amount);
    }

    /// @notice Repay the given amount of asset to Compound
    function _repay(address from) internal override {
        uint256 amountToRepay = ICERC20(address(cTokenToBorrow)).borrowBalanceCurrent(from);
        // Approve tokens to Compound contract
        IERC20(address(cTokenToBorrow)).approve(address(cTokenToBorrow), amountToRepay);

        // Repay given amount to borrowed contract
        uint256 ret = ICERC20(address(cTokenToBorrow)).repayBorrow(amountToRepay);
        require(ret == 0, "COMPOUND_BORROWER: cErc20.repay failed");

        emit Repay(amountToRepay);
    }

    /// -----------------------------------------------------------------------
    /// ERC4626 overrides
    /// -----------------------------------------------------------------------

    function asset() public view virtual override returns (address) {
        return address(underAsset);
    }

    function totalAssets() public view virtual override returns (uint256) {
        return cToken.viewUnderlyingBalanceOf(address(this));
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
    /// Internal functions
    /// -----------------------------------------------------------------------

    function _convertCollateralToBorrow(
        uint256 amount
    ) internal view returns (uint256) {
        (, int256 assetPriceInUSD, , , ) = assetPriceFeed.latestRoundData();
        if (assetPriceInUSD <= 0) revert CompoundERC4626__InvalidPrice({
            price: assetPriceInUSD,
            priceFeed: address(assetPriceFeed)
        });

        uint256 assetDecimals = ERC20(asset()).decimals();
        assetPriceInUSD = _scalePrice(assetPriceInUSD, assetDecimals, _DECIMALS);

        (, int256 borrowAssetPriceInUSD, , , ) = borrowAssetPriceFeed.latestRoundData();
        if (assetPriceInUSD <= 0) revert CompoundERC4626__InvalidPrice({
            price: borrowAssetPriceInUSD,
            priceFeed: address(borrowAssetPriceFeed)
        });

        uint256 borrowAssetDecimals = cTokenToBorrow.underlying().decimals();
        borrowAssetPriceInUSD = _scalePrice(borrowAssetPriceInUSD, borrowAssetDecimals, _DECIMALS);

        return amount * uint256(borrowAssetPriceInUSD) / uint256(assetPriceInUSD);
    }

    function _scalePrice(
        int256 price,
        uint256 priceDecimals,
        uint256 decimals
    ) internal pure returns (int256) {
        if (priceDecimals < decimals) {
            return price * int256(10 ** uint256(decimals - priceDecimals));
        } else if (priceDecimals > decimals) {
            return price / int256(10 ** uint256(priceDecimals - decimals));
        }
        return price;
    }

}
