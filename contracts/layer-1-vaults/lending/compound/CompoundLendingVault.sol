// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.17;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import {ICERC20} from "../../../interfaces/ICERC20.sol";
import {LibCompound} from "./lib/LibCompound.sol";
import {IComptroller} from "../../../interfaces/IComptroller.sol";

import {LendingBaseVault} from "../base/LendingBaseVault.sol";
import {ICompoundLendingVault} from "./ICompoundLendingVault.sol";
import "../../../Errors.sol";
import "hardhat/console.sol";

/// @title CompoundLendingVault
/// @author ffarall, LucaCevasco
/// @notice ERC4626 wrapper for Compound Finance
contract CompoundLendingVault is Ownable, LendingBaseVault, Initializable, ICompoundLendingVault {

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

    /// @notice The underlying token asset
    ERC20 public underAsset;

    /// @notice The Compound comptroller contract
    IComptroller public comptroller;

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
        ERC20("CompoundLendingVault", "CLV") { }

    function initialize(
        ERC20 asset_, 
        ICERC20 cToken_, 
        IComptroller comptroller_,
        ICERC20 cTokenToBorrow_,
        AggregatorV3Interface assetPriceFeed_, 
        AggregatorV3Interface borrowAssetPriceFeed_,
        address deployer
    ) external initializer {
      _transferOwnership(deployer);

        cToken = cToken_;
        comptroller = comptroller_;
        underAsset = asset_;
        cTokenToBorrow = cTokenToBorrow_;
        assetPriceFeed = assetPriceFeed_;
        borrowAssetPriceFeed = borrowAssetPriceFeed_;

        // enter market to use supplied token as collateral
        address[] memory cTokensAux = new address[](1);
        cTokensAux[0] = address(cToken);
        uint256[] memory errors = comptroller.enterMarkets(cTokensAux);
        require(errors[0] == 0, "COMPOUND_BORROWER: enterMarkets failed");

        // pre-approve ERC20 transfers
        ERC20(cTokenToBorrow.underlying()).safeApprove(address(cTokenToBorrow), 2**256 - 1);
    }

    /// -----------------------------------------------------------------------
    /// LendingBaseVault overrides
    /// -----------------------------------------------------------------------

    function convertCollateralToBorrow(
        uint256 amount
    ) public view virtual override returns (uint256) {
        (, int256 assetPriceInUSD, , , ) = assetPriceFeed.latestRoundData();
        if (assetPriceInUSD <= 0) revert CompoundERC4626__InvalidPrice({
            price: assetPriceInUSD,
            priceFeed: address(assetPriceFeed)
        });

        uint256 assetDecimals = assetPriceFeed.decimals();
        assetPriceInUSD = _scalePrice(assetPriceInUSD, assetDecimals, _DECIMALS);

        (, int256 borrowAssetPriceInUSD, , , ) = borrowAssetPriceFeed.latestRoundData();
        if (assetPriceInUSD <= 0) revert CompoundERC4626__InvalidPrice({
            price: borrowAssetPriceInUSD,
            priceFeed: address(borrowAssetPriceFeed)
        });

        uint256 borrowAssetDecimals = borrowAssetPriceFeed.decimals();
        borrowAssetPriceInUSD = _scalePrice(borrowAssetPriceInUSD, borrowAssetDecimals, _DECIMALS);

        return amount * uint256(borrowAssetPriceInUSD) / uint256(assetPriceInUSD);
    }

    function convertBorrowToCollateral(
        uint256 amount
    ) public view virtual override returns (uint256) {
        (, int256 assetPriceInUSD, , , ) = assetPriceFeed.latestRoundData();
        // if (assetPriceInUSD <= 0) revert CompoundERC4626__InvalidPrice({
        //     price: assetPriceInUSD,
        //     priceFeed: address(assetPriceFeed)
        // });
        uint256 assetDecimals = assetPriceFeed.decimals();
        assetPriceInUSD = _scalePrice(assetPriceInUSD, assetDecimals, _DECIMALS);

        (, int256 borrowAssetPriceInUSD, , , ) = borrowAssetPriceFeed.latestRoundData();
        // if (assetPriceInUSD <= 0) revert CompoundERC4626__InvalidPrice({
        //     price: borrowAssetPriceInUSD,
        //     priceFeed: address(borrowAssetPriceFeed)
        // });
        uint256 borrowAssetDecimals = borrowAssetPriceFeed.decimals();
        borrowAssetPriceInUSD = _scalePrice(borrowAssetPriceInUSD, borrowAssetDecimals, _DECIMALS);

        return amount * uint256(assetPriceInUSD) / uint256(borrowAssetPriceInUSD);
    }

    function _afterDeposit(
        address /* caller */,
        address receiver,
        uint256 assets,
        uint256 /* shares */
    ) internal virtual override {
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
        
        // borrow
        uint256 valueInAssetBorrow = convertCollateralToBorrow(assets);
        (bool isListed, uint256 colFactor, ) = comptroller.markets(address(cToken));
        if (!isListed) revert CompoundERC4626__MarketNotListed(address(cToken));

        colFactor = colFactor * 90 / 100;
        uint256 amountBorrow = valueInAssetBorrow * colFactor / 10**18;
        _borrow(receiver, amountBorrow);
    }

    function _beforeWithdraw(
        address caller,
        address /* receiver */,
        address /* owner*/,
        uint256 assets,
        uint256 /* shares*/
    ) internal virtual override {
        /// -----------------------------------------------------------------------
        /// Withdraw assets from Compound
        /// -----------------------------------------------------------------------

        _repay(caller);

        uint256 errorCode = cToken.redeemUnderlying(assets);
        if (errorCode != _NO_ERROR) {
            revert CompoundERC4626__CompoundError(errorCode);
        }
    }

    /// @notice Borrow the given amount of asset from Compound
    function _borrow(address holder, uint256 amount) internal override {
        // Check account can borrow
        (uint256 ret, uint256 liquidity, uint256 shortfall) = comptroller.getAccountLiquidity(address(this));
        require(ret == 0, "COMPOUND_BORROWER: getAccountLiquidity failed.");
        require(shortfall == 0, "COMPOUND_BORROWER: Account underwater");
        require(liquidity > 0, "COMPOUND_BORROWER: Account doesn't have liquidity");

        ret = cTokenToBorrow.borrow(amount);
        require(ret == 0, "COMPOUND_BORROWER: cErc20.borrow failed");

        _holdersLoans[holder] = amount;
        emit Borrow(amount);
    }

    /// TODO @notice Repay the given amount of asset to Compound
    function _repay(address holder) internal override {
        uint256 amountToRepay = _holdersLoans[holder];

        // Repay given amount to borrowed contract
        uint256 ret = cTokenToBorrow.repayBorrow(amountToRepay);
        require(ret == 0, "COMPOUND_BORROWER: cErc20.repay failed");

        _holdersLoans[holder] = 0;
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

    function _convertToShares(uint256 assets, Math.Rounding /* rounding */) internal view virtual override returns (uint256 shares) {
        uint256 exchangeRate = cToken.exchangeRateStored();
        uint256 scaleUp = 10 ** (10 + ERC20(cToken.underlying()).decimals());
        shares = assets * scaleUp / exchangeRate;
    }

    function _convertToAssets(uint256 shares, Math.Rounding /* rounding */) internal view virtual override returns (uint256 assets) {
        uint256 exchangeRate = cToken.exchangeRateStored();
        uint256 scaleDown = 10 ** (10 + ERC20(cToken.underlying()).decimals());
        assets = shares * exchangeRate / scaleDown;
    }

    /// -----------------------------------------------------------------------
    /// Internal functions
    /// -----------------------------------------------------------------------

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
