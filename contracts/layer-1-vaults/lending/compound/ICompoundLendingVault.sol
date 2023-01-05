// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.17;

import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626, IERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ICERC20} from "../../../interfaces/ICERC20.sol";
import {IComptroller} from "../../../interfaces/IComptroller.sol";

interface ICompoundLendingVault {
    function initialise(
      ERC20 asset_, ICERC20 cToken_, IComptroller comptroller_
    ) external;
}
