// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.17;

import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {IUniswapV2Router02} from "../../../interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Factory} from "../../../interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Pair} from "../../../interfaces/IUniswapV2Pair.sol";
import {IMasterChefV2} from "../../../interfaces/IMasterChefV2.sol";
import {IRewarder} from "../../../interfaces/IRewarder.sol";
import {SushiStakingLogic} from "./SushiStakingLogic.sol";
import {ISushiStakingVault} from "./ISushiStakingVault.sol";

/// @title SushiStakingVault
/// @author ffarall, LucaCevasco
/// @notice Automated SushiSwap liquidity provider and staker with ERC4626 interface
/// @dev Adds liquidity to a SushiSwap pool and stakes the LP tokens on the MasterChef
/// contract to earn rewards. Uses LPTs as shares accounting instead of using regular
/// vault accounting.
contract SushiStakingVault is Ownable, Initializable, ERC4626, ISushiStakingVault {
    using SafeERC20 for ERC20;
    using Math for uint256;

    /// -----------------------------------------------------------------------
    /// Immutable params
    /// -----------------------------------------------------------------------

    /// @notice One of the tokens of the pool, is the same as the asset of the vault
    ERC20 public tokenA;
    /// @notice The other token of the pool
    ERC20 public tokenB;
    /// @notice The UniswapV2 router2 address
    IUniswapV2Router02 public router;
    /// @notice UniswapV2 Factory
    IUniswapV2Factory public factory;
    /// @notice UniswapV2 pair of tokenA and tokenB
    IUniswapV2Pair public pair;
    /// @notice Path to swap tokens form tokenA to tokenB
    address[] public pathAtoB;
    /// @notice MasterChefV2/MiniChef SushiSwap contract to stake LPTs
    IMasterChefV2 public farm;
    /// @notice MasterChef's pool ID to invest in
    uint256 public poolId;

    /// -----------------------------------------------------------------------
    /// Private vars
    /// -----------------------------------------------------------------------

    /// @notice Amount of LPTs deposited in this vault
    uint256 private _lptsDeposited;

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

    constructor()
    ERC4626(IERC20(address(0)))
    ERC20("SushiStakingVault", "SSV") { }

    /// -----------------------------------------------------------------------
    /// Initalizable
    /// -----------------------------------------------------------------------

    function initialize(
        ERC20 tokenA_, 
        ERC20 tokenB_, 
        IUniswapV2Router02 router_,
        IUniswapV2Factory factory_,
        IUniswapV2Pair pair_,
        IMasterChefV2 farm_,
        uint256 poolId_,
        address deployer
    ) external initializer {
        _transferOwnership(deployer);

        tokenA = tokenA_;
        tokenB = tokenB_;
        router = router_;
        factory = factory_;
        pair = pair_;
        farm = farm_;
        poolId = poolId_;

        // Setting path to swap, using simplest option as default
        pathAtoB.push(address(tokenA));
        pathAtoB.push(address(tokenB));

        // Pre-authorising smart contracts to use this vault's tokens
        tokenA.approve(address(router), 2**256 - 1);
        tokenB.approve(address(router), 2**256 - 1);
        pair.approve(address(farm), 2**256 - 1);
        pair.approve(address(router), 2**256 - 1);
    }

    /// -----------------------------------------------------------------------
    /// ERC4626 overrides
    /// -----------------------------------------------------------------------

    /// @inheritdoc ERC4626
    function asset() public view virtual override returns (address) {
        return address(tokenA);
    }

    /// @inheritdoc ERC4626
    function deposit(uint256 assets, address receiver) public virtual override returns (uint256) {
        require(assets <= maxDeposit(receiver), "ERC4626: deposit more than max");

        uint256 shares;
        (shares, ) = _depositAssets(_msgSender(), receiver, assets);

        return shares;
    }

    /// @inheritdoc ERC4626
    function mint(uint256 shares, address receiver) public virtual override returns (uint256) {
        require(shares <= maxMint(receiver), "ERC4626: mint more than max");

        uint256 assets = previewMint(shares);
        (, assets) = _depositAssets(_msgSender(), receiver, assets);

        return assets;
    }

    /// @inheritdoc ERC4626
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public virtual override returns (uint256) {
        require(assets <= maxWithdraw(owner), "ERC4626: withdraw more than max");

        uint256 shares = previewWithdraw(assets);
        (, shares) = _withdrawLPTs(_msgSender(), receiver, owner, shares);

        return shares;
    }

    /// @inheritdoc ERC4626
    function totalAssets() public view virtual override returns (uint256) {
        return _convertToAssets(_lptsDeposited, Math.Rounding.Down);
    }

    /// @inheritdoc ERC4626
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public virtual override returns (uint256) {
        require(shares <= maxRedeem(owner), "ERC4626: redeem more than max");

        uint256 assets = previewRedeem(shares);
        (assets, ) = _withdrawLPTs(_msgSender(), receiver, owner, shares);

        return assets;
    }

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

    /// @dev Deposit/mint common workflow.
    function _depositAssets(
        address caller,
        address receiver,
        uint256 assets
    ) internal returns (uint256, uint256) {
        // If _asset is ERC777, `transferFrom` can trigger a reenterancy BEFORE the transfer happens through the
        // `tokensToSend` hook. On the other hand, the `tokenReceived` hook, that is triggered after the transfer,
        // calls the vault, which is assumed not malicious.
        //
        // Conclusion: we need to do the transfer before we mint so that any reentrancy would happen before the
        // assets are transferred and before the shares are minted, which is a valid state.
        // slither-disable-next-line reentrancy-no-eth
        SafeERC20.safeTransferFrom(ERC20(asset()), caller, address(this), assets);

        // Swap half the assets to tokenB, to invest in pool
        uint256 amountA = assets / 2;
        uint256 amountB = SushiStakingLogic.swap(amountA, pathAtoB, router);

        // Add liquidity with both assets
        uint256 lptAmount;
        (, , lptAmount) = _addLiquidity(amountA, amountB);

        // Invest in SushiSwap farm
        _stake(lptAmount);
        _mint(receiver, lptAmount);

        _lptsDeposited += lptAmount;

        emit Deposit(caller, receiver, assets, lptAmount);

        return (assets, lptAmount);
    }

    /// @dev Withdraw/redeem common workflow.
    function _withdrawLPTs(
        address caller,
        address receiver,
        address owner,
        uint256 shares
    ) internal virtual returns (uint256, uint256) {
        // If _asset is ERC777, `transfer` can trigger a reentrancy AFTER the transfer happens through the
        // `tokensReceived` hook. On the other hand, the `tokensToSend` hook, that is triggered before the transfer,
        // calls the vault, which is assumed not malicious.
        //
        // Conclusion: we need to do the transfer after the burn so that any reentrancy would happen after the
        // shares are burned and after the assets are transferred, which is a valid state.
        _burn(owner, shares);
        _unstake(shares);

        uint256 amountA;
        amountA = _removeLiquidity(shares);
        SafeERC20.safeTransfer(ERC20(asset()), receiver, amountA);

        emit Withdraw(caller, receiver, owner, amountA, shares);

        return (amountA, shares);
    }

    /// -----------------------------------------------------------------------
    /// SushiSwap handling functions
    /// -----------------------------------------------------------------------

    /// @notice Gets amount of rewards pending in the MasterChef contract.
    /// @dev Considers both SUSHI and additional rewards of the pool, as part of the Onsen program.
    /// @param includeDust If the calculation should include fractions of the tokens remaining in
    /// this contract.
    function getAccruedRewards(bool includeDust) public view returns (address[] memory, uint256[] memory) {
        return SushiStakingLogic.getAccruedRewards(includeDust, farm, poolId);
    }
    
    /// @notice This contract must be previously funded with the required amounts.
    /// `amountA` and `amountB` must be accordingly balanced given the current pool price.
    /// min amounts are internally computed.
    /// a 300s deadline is internally specified.
    /// @dev Adds liquidity to a liquidity pool given by `tokenA` and `tokenB` via `router`.
    /// @param amountA the amount of `tokenA` to be deposited.
    /// @param amountB the amount of `tokenB` to be deposited.
    function _addLiquidity(uint256 amountA, uint256 amountB)
        internal
        returns (
        uint256,
        uint256,
        uint256
        )
    {
        return SushiStakingLogic.addLiquidity(amountA, amountB, tokenA, tokenB, router);
    }

    /// @notice Removes liquidity from a liquidity pool given by `tokenA` and `tokenB` via `router`,
    /// back to this contract.
    /// @dev A 300s deadline is internally specified and a slippage of 5% is tolerated.
    /// @param lptAmount the amount of liquidity provider tokens to burn.
    function _removeLiquidity(
        uint256 lptAmount
    ) internal returns (uint256) {
        uint256 amountA; uint256 amountB;
        (amountA, amountB) = SushiStakingLogic.removeLiquidity(lptAmount, tokenA, tokenB, router, pair);

        address[] memory path = new address[](2);
        path[0] = address(tokenB);
        path[1] = address(tokenA);
        uint256 swappedAmountA = SushiStakingLogic.swap(amountB, path, router);

        return amountA + swappedAmountA;
    }

    /// @notice Stakes LPTs to MasterChef contract to earn rewards.
    /// @dev Approves usage of LPTs first.
    /// @param lptAmount the amount of liquidity provider tokens to burn.
    function _stake(uint256 lptAmount) internal {
        SushiStakingLogic.stake(lptAmount, pair, farm, poolId);
    }

    /// @notice Claims rewards and unstakes LPTs from MasterChef contract.
    /// @param lptAmount the amount of liquidity provider tokens to burn.
    function _unstake(uint256 lptAmount) internal {
        SushiStakingLogic.unstake(tokenA, lptAmount, router, farm, poolId);
    }

    /// -----------------------------------------------------------------------
    /// Public variables setters
    /// -----------------------------------------------------------------------

    /// @notice Sets path to swap from tokenA to tokenB
    function setPath(address[] memory newPath) external onlyOwner {
        delete pathAtoB;
        pathAtoB = newPath;
    }
}
