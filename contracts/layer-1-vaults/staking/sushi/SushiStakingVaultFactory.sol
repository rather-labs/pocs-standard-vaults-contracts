// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.17;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IUniswapV2Router02} from "../../../interfaces/IUniswapV2Router02.sol";
import {IMasterChefV2} from "../../../interfaces/IMasterChefV2.sol";
import {IUniswapV2Factory} from "../../../interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Pair} from "../../../interfaces/IUniswapV2Pair.sol";
import {ERC4626Factory} from "../../../base/ERC4626Factory.sol";
import {SushiStakingVault, ISushiStakingVault} from "./SushiStakingVault.sol";
import "../../../Errors.sol";

/// @title SushiStakingVaultFactory
/// @author ffarall, LucaCevasco
/// @notice Factory for creating SushiStakingVault contracts
contract SushiStakingVaultFactory is Ownable, ERC4626Factory {
    /// -----------------------------------------------------------------------
    /// Immutable params
    /// -----------------------------------------------------------------------

    /// @notice The UniswapV2 router2 address
    IUniswapV2Router02 public immutable router;
    /// @notice UniswapV2 Factory
    IUniswapV2Factory public immutable factory;
    /// @notice MasterChefV2/MiniChef SushiSwap contract to stake LPTs
    IMasterChefV2 public immutable farm;

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

    constructor(address implementation_, IUniswapV2Router02 router_, IMasterChefV2 farm_) {
        implementation = implementation_;
        router = router_;
        farm = farm_;

        factory = IUniswapV2Factory(router.factory());
    }

    /// -----------------------------------------------------------------------
    /// ERC4626 overrides
    /// -----------------------------------------------------------------------

    function _initialize(ERC4626 vault, ERC20 asset, bytes memory data) internal virtual override {
        if (address(asset) == address(0)) revert InvalidAddress();

        (address tokenB, uint256 poolId) = abi.decode(data, (address, uint256));
        if (tokenB == address(0)) revert InvalidAddress();
        if (poolId == 0) revert SushiStakingVaultFactory__InvalidPoolID();

        // Getting and pair
        IUniswapV2Pair pair = IUniswapV2Pair(factory.getPair(address(asset), address(tokenB)));
        ISushiStakingVault(address(vault)).initialize(
            asset,
            ERC20(tokenB),
            router,
            factory,
            pair,
            farm,
            poolId,
            msg.sender
        );
    }
}
