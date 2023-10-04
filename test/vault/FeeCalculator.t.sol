// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {PreMigrationSetup} from "../utils/DeploymentSetup.sol";
import {FeeCalculator} from "../../contracts/vault/FeeCalculator.sol";
import {ICollateralManager} from "../../contracts/vault/interfaces/ICollateralManager.sol";
import {IOracle} from "../../contracts/interfaces/IOracle.sol";
import {IUSDs} from "../../contracts/interfaces/IUSDs.sol";

contract TestFeeCalculator is PreMigrationSetup {
    FeeCalculator private feeCalculator;
    IOracle.PriceData private priceData;
    uint16 private _baseFeeIn;
    uint16 private _baseFeeOut;

    function setUp() public override {
        super.setUp();
        feeCalculator = new FeeCalculator(COLLATERAL_MANAGER);
        _baseFeeIn = 550;
        _baseFeeOut = 450;
    }

    function testGetFeeIn() public {
        ICollateralManager.CollateralMintData memory mintData;
        mintData.baseFeeIn = _baseFeeIn;
        uint256 feeIn = feeCalculator.getFeeIn(USDCe);
        assertEq(feeIn, _baseFeeIn, "Fee in mismatch");
    }

    function testGetFeeOut() public {
        ICollateralManager.CollateralRedeemData memory redeemData;
        redeemData.baseFeeOut = _baseFeeOut;
        uint256 feeOut = feeCalculator.getFeeOut(USDT);
        assertEq(feeOut, _baseFeeOut, "Fee out mismatch");
    }
}
