pragma solidity 0.8.19;

interface IveSPARewarder {
    /// @notice Add rewards tokens for future epochs in uniform manner.
    /// @dev Any rewards tokens directly transferred to the contract are not considered for distribution.
    ///       They have to be recovered from the contract using `recoverERC20` function.
    /// @param _token Address of the reward token.
    /// @param _amount The total amount to be funded.
    /// @param _numEpochs The number of epochs the amount should be split. (2 = 2 epochs).
    function addRewards(address _token, uint256 _amount, uint256 _numEpochs) external;

    /// @notice Gets the scheduled rewards for a particular `_weekCursor`.
    /// @param _weekCursor Timestamp of the week. (THU 00:00 UTC)
    /// @param _rewardToken Address of the reward token.
    function rewardsPerWeek(uint256 _weekCursor, address _rewardToken) external view returns (uint256);
}
