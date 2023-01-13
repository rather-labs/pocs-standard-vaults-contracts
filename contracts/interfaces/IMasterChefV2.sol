// SPDX-License-Identifier: MIT
pragma solidity >=0.6.12;
pragma experimental ABIEncoderV2;
import "./IRewarder.sol";
import "./IMasterChef.sol";

interface IMasterChefV2 {
  struct UserInfo {
    uint256 amount;
    uint256 rewardDebt;
  }

  struct PoolInfo {
    uint128 accSushiPerShare;
    uint64 lastRewardTime;
    uint64 allocPoint;
  }

  function SUSHI() external view returns (address);

  function rewarder(uint256) external view returns (IRewarder);

  function lpToken(uint256) external view returns (address);

  function totalAllocPoint() external view returns (uint256);

  function sushiPerBlock() external view returns (uint256 amount);

  function poolLength() external view returns (uint256);

  function poolInfo(uint256 pid) external view returns (PoolInfo memory);

  function userInfo(uint256 _pid, address _user) external view returns (UserInfo memory);

  function pendingSushi(uint256 _pid, address _user) external view returns (uint256 pending);

  function deposit(
    uint256 pid,
    uint256 amount,
    address to
  ) external;

  function withdraw(
    uint256 pid,
    uint256 amount,
    address to
  ) external;

  function harvest(uint256 pid, address to) external;

  function withdrawAndHarvest(
    uint256 pid,
    uint256 amount,
    address to
  ) external;

  function emergencyWithdraw(uint256 pid, address to) external;
}
