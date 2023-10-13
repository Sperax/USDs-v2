// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

// https://docs.compound.finance/#compound-iii
interface IComet {
    /// @notice Supply an amount of asset to the protocol
    /// @param asset The asset to supply
    /// @param amount The quantity to supply
    function supply(address asset, uint256 amount) external;

    /// @notice Withdraw an amount of asset from the protocol
    /// @param asset The asset to withdraw
    /// @param amount The quantity to withdraw
    function withdraw(address asset, uint256 amount) external;

    /// @notice Withdraw an amount of asset to `to`
    /// @param to The recipient address
    /// @param asset The asset to withdraw
    /// @param amount The quantity to withdraw
    function withdrawTo(address to, address asset, uint256 amount) external;

    /// @notice A function to call to accrue rewards and interest
    /// @param account The account whose rewards to be accrued
    function accrueAccount(address account) external;

    /// @notice Query the current positive base balance of an account or zero
    /// @dev Note: uses updated interest indices to calculate
    /// @param account The account whose balance to query
    /// @return The present day base balance magnitude of the account, if positive
    function balanceOf(address account) external view returns (uint256);

    /// @notice Returns the base token for the contract
    function baseToken() external view returns (address);

    /// @notice Query the total accrued base rewards for an account
    /// @param account The account to query
    /// @return The accrued rewards, scaled by `BASE_ACCRUAL_SCALE`
    function baseTrackingAccrued(
        address account
    ) external view returns (uint64);

    /// @notice Gets the total amount of protocol reserves of the base asset
    function getReserves() external view returns (int256);
}

interface IReward {
    struct RewardOwed {
        address token;
        uint256 owed;
    }

    struct RewardConfig {
        address token;
        uint64 rescaleFactor;
        bool shouldUpscale;
        // Note: We define new variables after existing variables to keep interface backwards-compatible
        uint256 multiplier;
    }

    //  @notice Calculates the amount of a reward token owed to an account
    //  @param comet The protocol instance
    //  @param account The account to check rewards for
    function getRewardOwed(
        address comet,
        address account
    ) external returns (RewardOwed memory);

    /// @notice Claim rewards of token type from a comet instance to owner address
    /// @param comet The protocol instance
    /// @param src The owner to claim for
    /// @param shouldAccrue Whether or not to call accrue first
    function claim(address comet, address src, bool shouldAccrue) external;

    /// @notice Claim rewards of token type from a comet instance to a target address
    /// @param comet The protocol instance
    /// @param src The owner to claim for
    /// @param to The address to receive the rewards
    function claimTo(
        address comet,
        address src,
        address to,
        bool shouldAccrue
    ) external;

    function rewardConfig(
        address comet
    ) external view returns (RewardConfig memory);

    function rewardsClaimed(
        address commet,
        address account
    ) external view returns (uint256);
}
