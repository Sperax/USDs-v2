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

    ICollateralManager public immutable collateralManager;

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
        if (block.timestamp < collateralFee[_collateral].nextUpdate)
            revert InvalidCalibration();
        _calibrateFee(_collateral);
    }

    /// @inheritdoc IFeeCalculator
    function getMintFee(address _collateral) external view returns (uint256) {
        FeeData memory feeData = collateralFee[_collateral];
        if (feeData.nextUpdate == 0) revert FeeNotCalibrated(_collateral);
        return feeData.mintFee;
    }

    /// @inheritdoc IFeeCalculator
    function getRedeemFee(address _collateral) external view returns (uint256) {
        FeeData memory feeData = collateralFee[_collateral];
        if (feeData.nextUpdate == 0) revert FeeNotCalibrated(_collateral);
        return collateralFee[_collateral].redeemFee;
    }

    /// @notice Calibrates fee for all the collaterals registered
    function calibrateFeeForAll() public {
        address[] memory collaterals = collateralManager.getAllCollaterals();
        for (uint256 i; i < collaterals.length; ) {
            if (block.timestamp > collateralFee[collaterals[i]].nextUpdate) {
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
            uint16 baseMintFee,
            uint16 baseRedeemFee,
            uint16 composition,
            uint256 totalCollateral
        ) = collateralManager.getFeeCalibrationData(_collateral);

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
                mintFee: baseMintFee / DISCOUNT_FACTOR,
                redeemFee: baseRedeemFee * PENALTY_MULTIPLIER
            });
        } else if (totalCollateral < upperLimit) {
            updatedFeeData = FeeData({
                nextUpdate: uint32(block.timestamp) + CALIBRATION_GAP,
                mintFee: baseMintFee,
                redeemFee: baseRedeemFee
            });
        } else {
            updatedFeeData = FeeData({
                nextUpdate: uint32(block.timestamp) + CALIBRATION_GAP,
                mintFee: baseMintFee * PENALTY_MULTIPLIER,
                redeemFee: baseRedeemFee / DISCOUNT_FACTOR
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
