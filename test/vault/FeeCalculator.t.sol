// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {BaseTest} from "../utils/BaseTest.sol";
import {FeeCalculator} from "../../contracts/vault/FeeCalculator.sol";
import {ICollateralManager} from "../../contracts/vault/interfaces/ICollateralManager.sol";
import {IOracle} from "../../contracts/interfaces/IOracle.sol";
import {IUSDs} from "../../contracts/interfaces/IUSDs.sol";

contract TestFeeCalculator is BaseTest {
    FeeCalculator private feeCalculator;
    uint256 public constant PERCENT_PRECISION = 1e4;
    IOracle.PriceData private priceData;
    uint16 private _baseFeeIn;
    uint16 private _baseFeeOut;

    function setUp() public override {
        super.setUp();
        feeCalculator = new FeeCalculator();
        _baseFeeIn = 550;
        _baseFeeOut = 450;
    }

    function testGetFeeIn() public {
        ICollateralManager.CollateralMintData memory mintData;
        mintData.baseFeeIn = _baseFeeIn;
        (uint256 feeIn, uint256 precision) = feeCalculator.getFeeIn(
            USDCe,
            100e18,
            mintData,
            priceData
        );
        assertEq(feeIn, _baseFeeIn, "Fee in mismatch");
        assertEq(precision, PERCENT_PRECISION, "Precision mismatch");
    }

    function testGetFeeOut() public {
        ICollateralManager.CollateralRedeemData memory redeemData;
        redeemData.baseFeeOut = _baseFeeOut;
        (uint256 feeOut, uint256 precision) = feeCalculator.getFeeOut(
            USDT,
            1000e18,
            redeemData,
            priceData
        );
        assertEq(feeOut, _baseFeeOut, "Fee out mismatch");
        assertEq(precision, PERCENT_PRECISION, "Precision mismatch");
    }
}
