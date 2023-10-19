//SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

interface ICollateralManager {
    struct CollateralBaseData {
        bool mintAllowed;
        bool redeemAllowed;
        bool allocationAllowed;
        uint16 baseFeeIn;
        uint16 baseFeeOut;
        uint16 downsidePeg;
        uint16 desiredCollateralComposition;
    }

    struct CollateralMintData {
        bool mintAllowed;
        uint16 baseFeeIn;
        uint16 downsidePeg;
        uint16 desiredCollateralComposition;
        uint256 conversionFactor;
    }

    struct CollateralRedeemData {
        bool redeemAllowed;
        address defaultStrategy;
        uint16 baseFeeOut;
        uint16 desiredCollateralComposition;
        uint256 conversionFactor;
    }

    /// @notice Update existing collateral configuration
    /// @param _collateral Address of the collateral
    /// @param _updateData Updated configuration for the collateral
    function updateCollateralData(address _collateral, CollateralBaseData memory _updateData) external;

    function updateCollateralDefaultStrategy(address _collateral, address _strategy) external;

    /// @notice Validate allocation for a collateral
    /// @param _collateral Address of the collateral
    /// @param _strategy Address of the desired strategy
    /// @param _amount Amount to be allocated.
    /// @return True for valid allocation request.
    function validateAllocation(address _collateral, address _strategy, uint256 _amount) external view returns (bool);

    /// @notice Get the required data for mint
    /// @param _collateral Address of the collateral
    /// @return mintData
    function getMintParams(address _collateral) external view returns (CollateralMintData memory mintData);

    /// @notice Get the required data for USDs redemption
    /// @param _collateral Address of the collateral
    /// @return redeemData
    function getRedeemParams(address _collateral) external view returns (CollateralRedeemData memory redeemData);

    /// @notice Gets list of all the listed collateral
    /// @return address[] of listed collaterals
    function getAllCollaterals() external view returns (address[] memory);

    /// @notice Get the amount of collateral in all Strategies
    /// @param _collateral Address of the collateral
    /// @return amountInStrategies
    function getCollateralInStrategies(address _collateral) external view returns (uint256 amountInStrategies);

    /// @notice Get the amount of collateral in vault
    /// @param _collateral Address of the collateral
    /// @return amountInVault
    function getCollateralInVault(address _collateral) external view returns (uint256 amountInVault);

    /// @notice Verify if a strategy is linked to a collateral
    /// @param _collateral Address of the collateral
    /// @param _strategy Address of the strategy
    /// @return boolean true if the strategy is linked to the collateral
    function isValidStrategy(address _collateral, address _strategy) external view returns (bool);
}
