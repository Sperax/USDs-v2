//SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {ICollateralManager} from "./ICollateralManager.sol";
import {IOracle} from "../../interfaces/IOracle.sol";

interface IFeeCalculator {
    /// @notice Calculates fee to be collected for minting
    /// @param _collateralAddr Address of the collateral
    /// @param _collateralAmt amount to mint USDs
    /// @param _mintData Mint configuration for the collateral
    /// @param _collateralPriceData Price information for the collateral
    /// @return (uint256, uint256) baseFeeIn and Max Percentage (10000)
    function getFeeIn(
        address _collateralAddr,
        uint256 _collateralAmt,
        ICollateralManager.CollateralMintData calldata _mintData,
        IOracle.PriceData calldata _collateralPriceData
    ) external view returns (uint256, uint256);

    /// @notice Calculates fee to be collected for redeeming
    /// @param _collateralAddr Address of the collateral
    /// @param  _usdsAmt Amount of USDs to burn
    /// @param _redeemData Redeem configuration for the collateral
    /// @param _collateralPriceData Price information for the collateral
    /// @return (uint256, uint256) baseFeeOut and Max Percentage (10000)
    function getFeeOut(
        address _collateralAddr,
        uint256 _usdsAmt,
        ICollateralManager.CollateralRedeemData calldata _redeemData,
        IOracle.PriceData calldata _collateralPriceData
    ) external view returns (uint256, uint256);
}
