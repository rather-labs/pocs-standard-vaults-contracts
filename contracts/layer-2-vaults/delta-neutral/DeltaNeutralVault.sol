// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.17;

import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {LendingBaseVault} from "../../layer-1-vaults/lending/base/LendingBaseVault.sol";
import {IUniswapV2Router02} from "../../interfaces/IUniswapV2Router02.sol";

/// @title DeltaNeutralVault
/// @author ffarall, LucaCevasco
/// @notice Automated delta neutral DeFi strategy that uses a lending vault and a
/// staking vault implementing an ERC4626 interface and which also implements the ERC4626
/// standard for its use.
/// @dev Supplies the base asset (a stablecoin) to the lending vault, uses it as collateral,
/// and then borrows against it to invest in the staking vault
contract DeltaNeutralVault is Ownable, Initializable, ERC4626 {
    using SafeERC20 for ERC20;
    using Math for uint256;

    /// -----------------------------------------------------------------------
    /// Immutable params
    /// -----------------------------------------------------------------------

    /// @notice Lending vault used for providing collateral and borrowing against it
    LendingBaseVault public lendingVault;
    /// @notice Staking vault in which this vault invests what borrows from the lending vault
    ERC4626 public stakingVault;
    /// @notice The ratio between the value of the asset borrowed and the asset lent,
    /// in percentage terms with one decimal (for 75.5%, borrowRate = 755).
    uint256 public borrowRate;

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

    constructor()
    ERC4626(IERC20(address(0)))
    ERC20("DeltaNeutralVault", "DNV") { }

    /// -----------------------------------------------------------------------
    /// Initalizable
    /// -----------------------------------------------------------------------

    function initialize(
        LendingBaseVault lendingVault_,
        ERC4626 stakingVault_,
        uint256 borrowRate_,
        address deployer
    ) external initializer {
        _transferOwnership(deployer);

        lendingVault = lendingVault_;
        stakingVault = stakingVault_;
        borrowRate = borrowRate_;
    }

    /// -----------------------------------------------------------------------
    /// ERC4626 overrides
    /// -----------------------------------------------------------------------

    /// @inheritdoc ERC4626
    function _deposit(
        address caller, 
        address receiver, 
        uint256 assets, 
        uint256 shares
    ) internal virtual override {
        lendingVault.deposit(assets, address(this));

        // TODO deposit in staking vault
        stakingVault.deposit(amountAssetStake, address(this));

        super._deposit(caller, receiver, assets, shares);
    }

    // TODO _withdraw

    /// @inheritdoc ERC4626
    function _convertToShares(uint256 assets, Math.Rounding rounding) internal view virtual override returns (uint256) {
        // Getting reserves of tokenA in Uniswap Pair
        uint256 reserve0; uint256 reserve1; uint256 reserveA;
        (reserve0, reserve1, ) = pair.getReserves();
        address token0 = pair.token0();
        address token1 = pair.token1();

        if (address(tokenA) == token0) {
            reserveA = reserve0;
        } else if (address(tokenA) == token1) {
            reserveA = reserve1;
        } else {
            return _initialConvertToShares(assets, rounding);
        }

        // Getting total supply of LPTs in Uniswap Pair
        uint256 lptSupply = pair.totalSupply();

        return (assets / 2).mulDiv(lptSupply, reserveA, rounding);
    }

    /// @inheritdoc ERC4626
    function _convertToAssets(uint256 shares, Math.Rounding rounding) internal view virtual override returns (uint256) {
        // Getting reserves of tokenA in Uniswap Pair
        uint256 reserve0; uint256 reserve1; uint256 reserveA;
        (reserve0, reserve1, ) = pair.getReserves();
        address token0 = pair.token0();
        address token1 = pair.token1();

        if (address(tokenA) == token0) {
            reserveA = reserve0;
        } else if (address(tokenA) == token1) {
            reserveA = reserve1;
        } else {
            return _initialConvertToAssets(shares, rounding);
        }

        // Getting total supply of LPTs in Uniswap Pair
        uint256 lptSupply = pair.totalSupply();

        return shares.mulDiv(reserveA, lptSupply, rounding) * 2;
    }
}