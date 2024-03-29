//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IStrategy {
    /// @notice Deposit asset into the strategy
    /// @param _asset Address of the asset
    /// @param _amount Amount of asset to be deposited
    function deposit(address _asset, uint256 _amount) external;

    /// @notice Withdraw `_asset` to `_recipient` (usually vault)
    /// @param _recipient Address of the recipient
    /// @param _asset Address of the asset
    /// @param _amount Amount to be withdrawn
    /// @return amountReceived The actual amount received
    function withdraw(address _recipient, address _asset, uint256 _amount) external returns (uint256);

    /// @notice Check if collateral allocation is supported by the strategy
    /// @param _asset Address of the asset which is to be checked
    /// @return isSupported True if supported and False if not
    function supportsCollateral(address _asset) external view returns (bool);

    /// @notice Get the amount of a specific asset held in the strategy
    ///           excluding the interest
    /// @dev    Assuming balanced withdrawal
    /// @param  _asset      Address of the asset
    /// @return Balance of the asset
    function checkBalance(address _asset) external view returns (uint256);

    /// @notice Gets the amount of asset withdrawable at any given time
    /// @param _asset Address of the asset
    /// @return availableBalance Available balance of the asset
    function checkAvailableBalance(address _asset) external view returns (uint256);
}
