pragma solidity 0.8.16;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface ILPStaking {
    function deposit(uint256 _pid, uint256 _amount) external;

    function withdraw(uint256 _pid, uint256 _amount) external;

    function emergencyWithdraw(uint256 _pid) external;

    function pendingStargate(
        uint256 _poolId,
        address _user
    ) external view returns (uint256);

    function poolInfo(
        uint256 _poolId
    ) external view returns (IERC20, uint256, uint256, address);

    function userInfo(
        uint256 _poolId,
        address _user
    ) external view returns (uint256 balance, uint256 rewardDebt);
}
