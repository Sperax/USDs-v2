pragma solidity 0.8.18;

interface ISaddleFarm {
    /// @notice Info of each MCV2 user.
    /// `amount` LP token amount the user has provided.
    /// `rewardDebt` The amount of SADDLE entitled to the user.
    struct UserInfo {
        uint256 amount;
        int256 rewardDebt;
    }

    /// @notice Info of each MCV2 pool.
    /// `allocPoint` The amount of allocation points assigned to the pool.
    /// Also known as the amount of SADDLE to distribute per block.
    struct PoolInfo {
        uint128 accSaddlePerShare;
        uint64 lastRewardTime;
        uint64 allocPoint;
    }

    /// @notice Deposit LP tokens to MCV2 for SADDLE allocation.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param amount LP token amount to deposit.
    /// @param to The receiver of `amount` deposit benefit.
    function deposit(uint256 pid, uint256 amount, address to) external;

    /// @notice Withdraw LP tokens from MCV2.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param amount LP token amount to withdraw.
    /// @param to Receiver of the LP tokens.
    function withdraw(uint256 pid, uint256 amount, address to) external;

    /// @notice Withdraw LP tokens from MCV2 and harvest proceeds for transaction sender to `to`.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param amount LP token amount to withdraw.
    /// @param to Receiver of the LP tokens and SADDLE rewards.
    function withdrawAndHarvest(
        uint256 pid,
        uint256 amount,
        address to
    ) external;

    /// @notice Withdraw without caring about rewards. EMERGENCY ONLY.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param to Receiver of the LP tokens.
    function emergencyWithdraw(uint256 pid, address to) external;

    /// @notice Harvest proceeds for transaction sender to `to`.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param to Receiver of SADDLE rewards.
    function harvest(uint256 pid, address to) external;

    /// @notice View function to see pending SADDLE on frontend.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param user Address of user.
    /// @return pending SADDLE reward for a given user.
    function pendingSaddle(
        uint256 pid,
        address user
    ) external view returns (uint256 pending);

    /// @notice Info of each user that stakes LP tokens.
    function userInfo(
        uint256 pid,
        address user
    ) external view returns (UserInfo memory);
}
