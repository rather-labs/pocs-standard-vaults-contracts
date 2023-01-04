// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.17;

import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626, IERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IUniswapV2Router02} from "../../../interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Factory} from "../../../interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Pair} from "../../../interfaces/IUniswapV2Pair.sol";
import {IMasterChefV2} from "../../../interfaces/IMasterChefV2.sol";

interface ISushiStakingVault {
    function initialise(
        ERC20 tokenA_, 
        ERC20 tokenB_, 
        IUniswapV2Router02 router_,
        IUniswapV2Factory factory_,
        IUniswapV2Pair pair_,
        IMasterChefV2 farm_,
        uint256 poolId_
    ) external;

    /// -----------------------------------------------------------------------
    /// SushiSwap handling functions
    /// -----------------------------------------------------------------------

    function getAccruedRewards(bool includeDust) external view returns (address[] memory, uint256[] memory);

    /// -----------------------------------------------------------------------
    /// Public variables setters
    /// -----------------------------------------------------------------------

    /// @notice Sets path to swap from tokenA to tokenB
    function setPath(address[] memory newPath) external;
}
