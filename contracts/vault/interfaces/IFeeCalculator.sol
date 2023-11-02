//SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

interface IFeeCalculator {
    /// @notice Calculates fee to be collected for minting
    /// @param _collateralAddr Address of the collateral
    /// @return (uint256) baseFeeIn
    function getMintFee(address _collateralAddr) external view returns (uint256);

    /// @notice Calculates fee to be collected for redeeming
    /// @param _collateralAddr Address of the collateral
    /// @return (uint256) baseFeeOut
    function getRedeemFee(address _collateralAddr) external view returns (uint256);
}
