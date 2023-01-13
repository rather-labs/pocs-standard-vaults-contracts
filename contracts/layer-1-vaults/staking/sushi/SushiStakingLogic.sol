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
library SushiStakingLogic {
    using SafeERC20 for ERC20;
    using Math for uint256;

    /// -----------------------------------------------------------------------
    /// SushiSwap handling functions
    /// -----------------------------------------------------------------------

    function getAccruedRewards(
        bool includeDust,
        IMasterChefV2 farm,
        uint256 poolId
    ) public view returns (address[] memory, uint256[] memory) {
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
    
    function addLiquidity(
        uint256 amountA, 
        uint256 amountB,
        ERC20 tokenA,
        ERC20 tokenB,
        IUniswapV2Router02 router
    )
        external
        returns (
        uint256,
        uint256,
        uint256
        )
    {
        uint256 deadline = block.timestamp + 300;
        uint256 minAmountA = (amountA * 95) / 100;
        uint256 minAmountB = (amountB * 95) / 100;

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

    function removeLiquidity(
        uint256 lptAmount,
        ERC20 tokenA,
        ERC20 tokenB,
        IUniswapV2Router02 router,
        IUniswapV2Pair pair
    ) external returns (uint256, uint256) {
        // Getting reserves of tokenA in Uniswap Pair
        uint256 reserveA; uint256 reserveB;
        uint256 minAmountA; uint256 minAmountB;

        { // This makes reserve0, reserve1, token0 and token1 local variables of
          // this scope, and prevents form stack too deep compilation error.
            {
                uint256 reserve0; uint256 reserve1;
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
            }

            // Getting total supply of LPTs in Uniswap Pair
            uint256 lptSupply = pair.totalSupply();

            // Calculate minAmountA and minAmountB considering 5% slippage
            minAmountA = lptAmount.mulDiv(reserveA, lptSupply) * 95 / 100;
            minAmountB = lptAmount.mulDiv(reserveB, lptSupply) * 95 / 100;
        }

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

    function stake(
        uint256 lptAmount,
        IUniswapV2Pair pair,
        IMasterChefV2 farm,
        uint256 poolId
    ) external {
        // Setting approval of LPTs to MasterChef contract
        pair.approve(address(farm), lptAmount);

        // Staking
        farm.deposit(poolId, lptAmount, address(this));
    }

    function unstake(
        uint256 lptAmount,
        IMasterChefV2 farm,
        uint256 poolId
    ) external {
        // Withdraw user's shares (i.e. LPTs)
        farm.withdraw(poolId, lptAmount, address(this));
    }

    function swap(
        uint256 amountIn,
        address[] memory path,
        IUniswapV2Router02 router
    ) public returns (uint256) {
        // Getting quote for swap, considering 1% slippage
        uint256[] memory amountsOutQuote = router.getAmountsOut(amountIn, path);
        uint256 minAmountOut = amountsOutQuote[amountsOutQuote.length - 1] * 990 / 1000;
        
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

    function claimRewards(
        ERC20 tokenA,
        IUniswapV2Router02 router,
        IMasterChefV2 farm,
        uint256 poolId
    ) public returns (address[] memory, uint256[] memory) {
        address[] memory rewards;
        uint256[] memory amounts;
        (rewards, amounts) = getAccruedRewards(false, farm, poolId);

        // Get rewards
        farm.harvest(poolId, address(this));

        // Swap rewards for Vault asset
        for (uint256 i=0; i < rewards.length; i++) {
            address[] memory path = new address[](2);
            path[0] = rewards[i];
            path[1] = address(tokenA);

            ERC20(rewards[i]).approve(address(router), amounts[i]);
            swap(amounts[i], path, router);
        }

        return (rewards, amounts);
    }
}
