// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {IFeeCalculator} from "./interfaces/IFeeCalculator.sol";
import {ICollateralManager} from "./interfaces/ICollateralManager.sol";
import {IOracle} from "../interfaces/IOracle.sol";
import {Helpers} from "../libraries/Helpers.sol";

contract FeeCalculator is IFeeCalculator {
    /// @inheritdoc IFeeCalculator
    function getFeeIn(
        address,
        uint256,
        ICollateralManager.CollateralMintData calldata _mintData,
        IOracle.PriceData calldata
    ) external pure returns (uint256, uint256) {
        return (_mintData.baseFeeIn, Helpers.MAX_PERCENTAGE);
    }

    /// @inheritdoc IFeeCalculator
    function getFeeOut(
        address,
        uint256,
        ICollateralManager.CollateralRedeemData calldata _redeemData,
        IOracle.PriceData calldata
    ) external pure returns (uint256, uint256) {
        return (_redeemData.baseFeeOut, Helpers.MAX_PERCENTAGE);
    }
}
