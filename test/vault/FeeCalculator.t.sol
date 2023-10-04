// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {PreMigrationSetup} from "../utils/DeploymentSetup.sol";
import {Helpers, FeeCalculator} from "../../contracts/vault/FeeCalculator.sol";
import {ICollateralManager} from "../../contracts/vault/interfaces/ICollateralManager.sol";
import {IOracle} from "../../contracts/interfaces/IOracle.sol";
import {IUSDs} from "../../contracts/interfaces/IUSDs.sol";

contract TestFeeCalculator is PreMigrationSetup {
    FeeCalculator private feeCalculator;
    IOracle.PriceData private priceData;
    uint16 private baseFeeIn;
    uint16 private baseFeeOut;
    uint16 private composition;
    uint16 private constant LOWER_THRESHOLD = 5000;
    uint16 private constant UPPER_THRESHOLD = 15000;
    uint16 private constant DISCOUNT_FACTOR = 2;
    uint16 private constant PENALTY_MULTIPLIER = 2;

    function setUp() public override {
        super.setUp();
        feeCalculator = new FeeCalculator(COLLATERAL_MANAGER);
    }

    function testGetFeeIn() public {
        baseFeeIn = getFeeIn();
        uint256 feeIn = feeCalculator.getFeeIn(USDCe);
        assertEq(feeIn, baseFeeIn, "Fee in mismatch");
    }

    function testGetFeeOut() public {
        baseFeeOut = getFeeOut();
        uint256 feeOut = feeCalculator.getFeeOut(USDT);
        assertEq(feeOut, baseFeeOut, "Fee out mismatch");
    }

    function getFeeIn() private returns (uint16) {
        (baseFeeIn, , composition) = ICollateralManager(COLLATERAL_MANAGER)
            .getCollateralFeeData(USDCe);
        uint256 totalCollateral = getTotalCollateral(USDCe);
        uint256 tvl = IUSDs(Helpers.USDS).totalSupply();
        uint256 desiredCollateralAmt = (tvl * composition) /
            (Helpers.MAX_PERCENTAGE);
        uint256 lowerLimit = (desiredCollateralAmt * LOWER_THRESHOLD) /
            (Helpers.MAX_PERCENTAGE);
        uint256 upperLimit = (desiredCollateralAmt * UPPER_THRESHOLD) /
            (Helpers.MAX_PERCENTAGE);
        if (totalCollateral < lowerLimit) {
            return baseFeeIn / DISCOUNT_FACTOR;
        } else if (totalCollateral < upperLimit) {
            return baseFeeIn;
        } else {
            return baseFeeIn * PENALTY_MULTIPLIER;
        }
    }

    function getFeeOut() private returns (uint16) {
        (, baseFeeOut, composition) = ICollateralManager(COLLATERAL_MANAGER)
            .getCollateralFeeData(USDCe);
        uint256 totalCollateral = getTotalCollateral(USDCe);
        uint256 tvl = IUSDs(Helpers.USDS).totalSupply();
        uint256 desiredCollateralAmt = (tvl * composition) /
            (Helpers.MAX_PERCENTAGE);
        uint256 lowerLimit = (desiredCollateralAmt * LOWER_THRESHOLD) /
            (Helpers.MAX_PERCENTAGE);
        uint256 upperLimit = (desiredCollateralAmt * UPPER_THRESHOLD) /
            (Helpers.MAX_PERCENTAGE);
        if (totalCollateral < lowerLimit) {
            return baseFeeOut * PENALTY_MULTIPLIER;
        } else if (totalCollateral < upperLimit) {
            return baseFeeOut;
        } else {
            return baseFeeOut / DISCOUNT_FACTOR;
        }
    }

    function getTotalCollateral(
        address _collateral
    ) private view returns (uint256) {
        return
            ICollateralManager(COLLATERAL_MANAGER).getCollateralInVault(
                _collateral
            ) +
            ICollateralManager(COLLATERAL_MANAGER).getCollateralInStrategies(
                _collateral
            );
    }
}
