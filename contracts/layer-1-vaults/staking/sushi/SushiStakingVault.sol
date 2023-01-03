// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.17;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IUniswapV2Router02} from "../../../interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Factory} from "../../../interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Pair} from "../../../interfaces/IUniswapV2Pair.sol";
import {IMasterChefV2} from "../../../interfaces/IMasterChefV2.sol";
import {IRewarder} from "../../../interfaces/IRewarder.sol";

/// @title SushiStakingVault
/// @author ffarall, LucaCevasco
/// @notice Automated SushiSwap liquidity provider and staker with ERC4626 interface
/// @dev Adds liquidity to a SushiSwap pool and stakes the LP tokens on the MasterChef
/// contract to earn rewards. Uses LPTs as shares accounting instead of using regular
/// vault accounting.
contract SushiStakingVault is ERC4626, Ownable {
    using SafeERC20 for ERC20;
    using Math for uint256;

    /// -----------------------------------------------------------------------
    /// Immutable params
    /// -----------------------------------------------------------------------

    /// @notice One of the tokens of the pool
    ERC20 public immutable tokenA;
    /// @notice The other token of the pool
    ERC20 public immutable tokenB;
    /// @notice The UniswapV2 router2 address
    IUniswapV2Router02 public immutable router;
    /// @notice UniswapV2 Factory
    IUniswapV2Factory public immutable factory;
    /// @notice UniswapV2 pair of tokenA and tokenB
    IUniswapV2Pair public immutable pair;
    /// @notice Path to swap tokens form tokenA to tokenB
    address[] public pathAtoB;
    /// @notice MasterChefV2/MiniChef SushiSwap contract to stake LPTs
    IMasterChefV2 public immutable farm;
    /// @notice MasterChef's pool ID to invest in
    uint256 public immutable poolId;

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

    constructor(
        ERC20 asset_, 
        ERC20 tokenA_, 
        ERC20 tokenB_, 
        IUniswapV2Router02 router_,
        IMasterChefV2 farm_,
        uint256 poolId_
    )
    ERC4626(asset_)
    ERC20("SushiStakingVault", "SSV") {
        tokenA = tokenA_;
        tokenB = tokenB_;
        router = router_;
        farm = farm_;
        poolId = poolId_;

        // Getting factory and pair
        factory = IUniswapV2Factory(router.factory());
        pair = IUniswapV2Pair(factory.getPair(address(tokenA), address(tokenB)));

        // Setting path to swap, using simplest option as default
        pathAtoB[0] = address(tokenA);
        pathAtoB[1] = address(tokenB);
    }

    /// -----------------------------------------------------------------------
    /// ERC4626 overrides
    /// -----------------------------------------------------------------------

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
        uint256 amountB = _swap(amountA, pathAtoB);

        // Add liquidity with both assets
        uint256 lptAmount;
        (, , lptAmount) = _addLiquidity(amountA, amountB);

        // Invest in SushiSwap farm
        _stake(lptAmount);
        _mint(receiver, lptAmount);

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
        (amountA, ) = _removeLiquidity(shares);
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
        address sushi = farm.SUSHI();
        IRewarder poolRewarder = farm.rewarder(poolId);

        uint256 pendingSushi = farm.pendingSushi(poolId, address(this));

        address[] memory extraRewards;
        uint256[] memory extraAmounts;
        (extraRewards, extraAmounts) = poolRewarder.pendingTokens(poolId, address(this), pendingSushi);

        address[] memory rewards = new address[](extraRewards.length + 1);
        uint256[] memory amounts = new uint256[](extraAmounts.length + 1);

        rewards[0] = sushi;
        amounts[0] = pendingSushi;

        for (uint256 i = 0; i < extraRewards.length; i++) {
            rewards[i + 1] = extraRewards[i];
            amounts[i + 1] = extraAmounts[i];
        }

        if (includeDust) {
            for (uint256 i = 0; i < rewards.length; i++) {
                ERC20 rewardToken = ERC20(rewards[i]);
                amounts[i] += (rewardToken.balanceOf(address(this)));
            }
        }

        return (rewards, amounts);
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
        uint256 deadline = block.timestamp + 300;
        uint256 restPercentageTolerance = 100 - 2;
        uint256 minAmountA = (amountA * restPercentageTolerance) / 100;
        uint256 minAmountB = (amountB * restPercentageTolerance) / 100;

        return
        IUniswapV2Router02(router).addLiquidity(
            address(tokenA),
            address(tokenB),
            amountA,
            amountB,
            minAmountA,
            minAmountB,
            address(this),
            deadline
        );
    }

    /// @notice Removes liquidity from a liquidity pool given by `tokenA` and `tokenB` via `router`,
    /// back to this contract.
    /// @dev A 300s deadline is internally specified and a slippage of 5% is tolerated.
    /// @param lptAmount the amount of liquidity provider tokens to burn.
    function _removeLiquidity(
        uint256 lptAmount
    ) internal returns (uint256, uint256) {
        // Getting reserves of tokenA in Uniswap Pair
        uint256 reserve0; uint256 reserve1; uint256 reserveA; uint256 reserveB;
        (reserve0, reserve1, ) = pair.getReserves();
        address token0 = pair.token0();
        address token1 = pair.token1();

        if (address(tokenA) == token0) {
            reserveA = reserve0;
            reserveB = reserve1;
        } else if (address(tokenA) == token1) {
            reserveA = reserve1;
            reserveB = reserve0;
        }

        // Getting total supply of LPTs in Uniswap Pair
        uint256 lptSupply = pair.totalSupply();

        // Calculate minAmountA and minAmountB considering 5% slippage
        uint256 minAmountA = lptAmount.mulDiv(reserveA, lptSupply) * 95 / 100;
        uint256 minAmountB = lptAmount.mulDiv(reserveB, lptSupply) * 95 / 100;

        uint256 deadline = block.timestamp + 300;
        return
        IUniswapV2Router02(router).removeLiquidity(
            address(tokenA),
            address(tokenB),
            lptAmount,
            minAmountA,
            minAmountB,
            address(this),
            deadline
        );
    }

    /// @notice Stakes LPTs to MasterChef contract to earn rewards.
    /// @dev Approves usage of LPTs first.
    /// @param lptAmount the amount of liquidity provider tokens to burn.
    function _stake(uint256 lptAmount) internal {
        // Setting approval of LPTs to MasterChef contract
        pair.approve(address(farm), lptAmount);

        // Staking
        farm.deposit(poolId, lptAmount, address(this));
    }

    /// @notice Claims rewards and unstakes LPTs from MasterChef contract.
    /// @param lptAmount the amount of liquidity provider tokens to burn.
    function _unstake(uint256 lptAmount) internal {
        _claimRewards();
        farm.withdraw(poolId, lptAmount, address(this));
    }

    /// @notice Claims rewards from MasterChef contract.
    function _claimRewards() internal returns (address[] memory, uint256[] memory) {
        address[] memory rewards;
        uint256[] memory amounts;
        (rewards, amounts) = getAccruedRewards(false);

        // Get rewards
        farm.harvest(poolId, address(this));

        return (rewards, amounts);
    }

    /// @notice Swaps the given using the given path.
    /// @dev Calculates minAmountOut getting a quoted amount from getAmountsOut method
    /// and considering a 5% slippage.
    /// @param amountIn Amount of first token in path to swap for last token in path.
    /// @param path Path of tokens to perform the swap with.
    /// @return amountOut Amount of last token in path gotten after the swap for first
    /// token in path.
    function _swap(
        uint256 amountIn,
        address[] memory path
    ) internal returns (uint256) {
        // Getting quote for swap, considering 5% slippage
        uint256[] memory amountsOutQuote = router.getAmountsOut(amountIn, path);
        uint256 minAmountOut = amountsOutQuote[amountsOutQuote.length - 1] * 95 / 100;
        
        // Swapping
        uint256[] memory amountsOut = router.swapExactTokensForTokens(
            amountIn,
            minAmountOut,
            path,
            address(this),
            block.timestamp + 300
        );
        uint256 amountOut = amountsOut[amountsOut.length - 1];

        return amountOut;
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
