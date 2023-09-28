// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {IFeeCalculator} from "./interfaces/IFeeCalculator.sol";
import {ICollateralManager} from "./interfaces/ICollateralManager.sol";
import {IOracle} from "../interfaces/IOracle.sol";
import {Helpers} from "../libraries/Helpers.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract FeeCalculator is IFeeCalculator {
    struct FeeData {
        uint32 nextUpdate;
        uint16 mintFee;
        uint16 redeemFee;
    }

    uint16 private constant LOWER_THRESHOLD = 5000;
    uint16 private constant UPPER_THRESHOLD = 15000;
    uint16 private constant DISCOUNT_FACTOR = 2;
    uint16 private constant PENALTY_MULTIPLIER = 2;
    uint32 private constant CALIBRATION_GAP = 1 days;

    ICollateralManager private immutable collateralManager;

    mapping(address => FeeData) public collateralFee;

    event FeeCalibrated(
        address indexed collateral,
        uint16 mintFee,
        uint16 redeemFee
    );

    error InvalidCalibration();
    error FeeNotCalibrated(address collateral);

    constructor(address _collateralManager) {
        collateralManager = ICollateralManager(_collateralManager);
        calibrateFeeForAll();
    }

    /// @notice Calibrates fee for a particular collateral
    /// @param _collateral Address of the desired collateral
    function calibrateFee(address _collateral) external {
        FeeData memory feeData = collateralFee[_collateral];
        if (block.timestamp < feeData.nextUpdate) revert InvalidCalibration();
        _calibrateFee(_collateral);
    }

    /// @inheritdoc IFeeCalculator
    function getFeeIn(address _collateral) external view returns (uint256) {
        FeeData memory feeData = collateralFee[_collateral];
        if (feeData.nextUpdate == 0) revert FeeNotCalibrated(_collateral);
        return collateralFee[_collateral].mintFee;
    }

    /// @inheritdoc IFeeCalculator
    function getFeeOut(address _collateral) external view returns (uint256) {
        FeeData memory feeData = collateralFee[_collateral];
        if (feeData.nextUpdate == 0) revert FeeNotCalibrated(_collateral);
        return collateralFee[_collateral].redeemFee;
    }

    /// @notice Calibrates fee for all the collaterals registered
    function calibrateFeeForAll() public {
        address[] memory collaterals = collateralManager.getAllCollaterals();
        for (uint256 i; i < collaterals.length; ) {
            FeeData memory feeData = collateralFee[collaterals[i]];
            if (block.timestamp > feeData.nextUpdate) {
                _calibrateFee(collaterals[i]);
            }
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Helper function for calibrating fee for a collateral
    /// @param _collateral Address of the desired collateral
    function _calibrateFee(address _collateral) private {
        // get current stats
        uint256 tvl = IERC20(Helpers.USDS).totalSupply();
        (
            uint16 baseFeeIn,
            uint16 baseFeeOut,
            uint16 composition
        ) = collateralManager.getCollateralFeeData(_collateral);
        uint256 totalCollateral = collateralManager.getCollateralInVault(
            _collateral
        ) + collateralManager.getCollateralInStrategies(_collateral);

        // compute segments
        uint256 desiredCollateralAmt = (tvl * composition) /
            (Helpers.MAX_PERCENTAGE);
        uint256 lowerLimit = (desiredCollateralAmt * LOWER_THRESHOLD) /
            (Helpers.MAX_PERCENTAGE);
        uint256 upperLimit = (desiredCollateralAmt * UPPER_THRESHOLD) /
            (Helpers.MAX_PERCENTAGE);

        FeeData memory updatedFeeData;
        if (totalCollateral < lowerLimit) {
            updatedFeeData = FeeData({
                nextUpdate: uint32(block.timestamp) + CALIBRATION_GAP,
                mintFee: baseFeeIn / DISCOUNT_FACTOR,
                redeemFee: baseFeeOut * PENALTY_MULTIPLIER
            });
        } else if (totalCollateral < upperLimit) {
            updatedFeeData = FeeData({
                nextUpdate: uint32(block.timestamp) + CALIBRATION_GAP,
                mintFee: baseFeeIn,
                redeemFee: baseFeeOut
            });
        } else {
            updatedFeeData = FeeData({
                nextUpdate: uint32(block.timestamp) + CALIBRATION_GAP,
                mintFee: baseFeeIn * PENALTY_MULTIPLIER,
                redeemFee: baseFeeOut / DISCOUNT_FACTOR
            });
        }
        collateralFee[_collateral] = updatedFeeData;
        emit FeeCalibrated(
            _collateral,
            updatedFeeData.mintFee,
            updatedFeeData.redeemFee
        );
    }
}
