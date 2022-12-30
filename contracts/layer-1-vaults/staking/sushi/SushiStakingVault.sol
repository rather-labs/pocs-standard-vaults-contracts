// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.17;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IUniswapV2Router02} from "../../../interfaces/IUniswapV2Router02.sol";
import {IMasterChefV2} from "../../../interfaces/IMasterChefV2.sol";
import {IUniswapV2Factory} from "../../../interfaces/IUniswapV2Factory.sol";
import {IRewarder} from "../../../interfaces/IRewarder.sol";

/// @title SushiStakingVault
/// @author ffarall, LucaCevasco
/// @notice Automated SushiSwap liquidity provider and staker with ERC4626 interface
/// @dev Adds liquidity to a SushiSwap pool and stakes the LP tokens on the MasterChef
/// contract to earn rewards.
contract SushiStakingVault is ERC4626 {
    using SafeERC20 for ERC20;

    /// -----------------------------------------------------------------------
    /// Immutable params
    /// -----------------------------------------------------------------------

    /// @notice One of the tokens of the pool
    ERC20 public immutable tokenA;
    /// @notice The other token of the pool
    ERC20 public immutable tokenB;
    /// @notice The Uniswap router address
    IUniswapV2Router02 public immutable router;
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
    }

    /// -----------------------------------------------------------------------
    /// ERC4626 overrides
    /// -----------------------------------------------------------------------

    /// @dev Deposit/mint common workflow.
    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal virtual override {
        super._deposit(caller, receiver, assets, shares);

        // TODO
    }


    /// @dev Deposit/mint common workflow.
    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal virtual override {
        super._withdraw(caller, receiver, owner, assets, shares);

        // TODO
    }

    /// -----------------------------------------------------------------------
    /// SushiSwap handling functions
    /// -----------------------------------------------------------------------
    
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
    /// @dev A 300s deadline is internally specified. 
    /// @param lptAmount the amount of liquidity provider tokens to burn.
    /// @param minAmountA the minimum amount of `tokenA` to be retrieved.
    /// @param minAmountB the minimum amount of `tokenB` to be retrieved.
    function _removeLiquidity(
        uint256 lptAmount,
        uint256 minAmountA,
        uint256 minAmountB
    ) internal returns (uint256, uint256) {
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
        // Getting pair
        IUniswapV2Factory factory = IUniswapV2Factory(router.factory());
        ERC20 pair = ERC20(factory.getPair(address(tokenA), address(tokenB)));

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
}
