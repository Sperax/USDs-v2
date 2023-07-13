// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {IFeeCalculator} from "./interfaces/IFeeCalculator.sol";
import {ICollateralManager} from "./interfaces/ICollateralManager.sol";
import {IOracle} from "../interfaces/IOracle.sol";

contract FeeCalculator is IFeeCalculator {
    uint256 public constant PERC_PRECISION = 1e4;

    /// @inheritdoc IFeeCalculator
    function getFeeIn(
        address,
        uint256,
        ICollateralManager.CollateralMintData calldata _mintData,
        IOracle.PriceData calldata
    ) external pure returns (uint256, uint256) {
        return (_mintData.baseFeeIn, PERC_PRECISION);
    }

    /// @inheritdoc IFeeCalculator
    function getFeeOut(
        address,
        uint256,
        ICollateralManager.CollateralRedeemData calldata _redeemData,
        IOracle.PriceData calldata
    ) external pure returns (uint256, uint256) {
        return (_redeemData.baseFeeOut, PERC_PRECISION);
    }
}
