// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {BaseTest} from "./utils/BaseTest.sol";
import {CollateralManager} from "../contracts/vault/CollateralManager.sol";
import {ICollateralManager} from "../contracts/vault/interfaces/ICollateralManager.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract CollateralManagerTest is BaseTest {
    //  Init Variables.
    CollateralManager public manager;

    // Events from the actual contract.
    // event CollateralAdded(address collateral, CollateralBaseData data);
    // event CollateralRemoved(address collateral);
    // event CollateralInfoUpdated(address collateral, CollateralBaseData data);
    // event CollateralStrategyAdded(address collateral, address strategy);
    // event CollateralStrategyUpdated(address collateral, address strategy);
    // event CollateralStrategyRemoved(address collateral, address strategy);
    function setUp() public override {
        super.setUp();
        setArbitrumFork();
        manager = new CollateralManager(VAULT);
        manager.transferOwnership(USDS_OWNER);
    }
}

contract CollateralManager_AddCollateral_Test is CollateralManagerTest {
    function test_revertsWhen_baseFeeExceedsMax(
        uint16 _baseFeeIn,
        uint16 _baseFeeOut,
        uint16 _downsidePeg
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseFeeIn > manager.PERC_PRECISION());
        vm.assume(_baseFeeOut > manager.PERC_PRECISION());
        vm.assume(_downsidePeg > manager.PERC_PRECISION());

        ICollateralManager.CollateralBaseData memory _data = ICollateralManager
            .CollateralBaseData({
                mintAllowed: true,
                redeemAllowed: true,
                allocationAllowed: true,
                baseFeeIn: _baseFeeIn,
                baseFeeOut: _baseFeeOut,
                downsidePeg: _downsidePeg,
                desiredCollateralComposition: 2000
            });
        vm.expectRevert("Illegal PERC input");
        manager.addCollateral(USDCe, _data);
    }

    function test_revertsWhen_addSameCollateral(
        uint16 _baseFeeIn,
        uint16 _baseFeeOut,
        uint16 _downsidePeg
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseFeeIn <= manager.PERC_PRECISION());
        vm.assume(_baseFeeOut <= manager.PERC_PRECISION());
        vm.assume(_downsidePeg <= manager.PERC_PRECISION());

        ICollateralManager.CollateralBaseData memory _data = ICollateralManager
            .CollateralBaseData({
                mintAllowed: true,
                redeemAllowed: true,
                allocationAllowed: true,
                baseFeeIn: _baseFeeIn,
                baseFeeOut: _baseFeeOut,
                downsidePeg: _downsidePeg,
                desiredCollateralComposition: 2000
            });
        manager.addCollateral(USDCe, _data);
        vm.expectRevert("Collateral already exists");
        manager.addCollateral(USDCe, _data);
    }

    function test_revertsWhen_collateralCompositionExceeded(
        uint16 _baseFeeIn,
        uint16 _baseFeeOut,
        uint16 _downsidePeg
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseFeeIn <= manager.PERC_PRECISION());
        vm.assume(_baseFeeOut <= manager.PERC_PRECISION());
        vm.assume(_downsidePeg <= manager.PERC_PRECISION());

        ICollateralManager.CollateralBaseData memory _data = ICollateralManager
            .CollateralBaseData({
                mintAllowed: true,
                redeemAllowed: true,
                allocationAllowed: true,
                baseFeeIn: _baseFeeIn,
                baseFeeOut: _baseFeeOut,
                downsidePeg: _downsidePeg,
                desiredCollateralComposition: 9000
            });
        ICollateralManager.CollateralBaseData memory _data2 = ICollateralManager
            .CollateralBaseData({
                mintAllowed: true,
                redeemAllowed: true,
                allocationAllowed: true,
                baseFeeIn: _baseFeeIn,
                baseFeeOut: _baseFeeOut,
                downsidePeg: _downsidePeg,
                desiredCollateralComposition: 1001
            });
        manager.addCollateral(USDCe, _data);
        vm.expectRevert("Collateral composition exceeded");
        manager.addCollateral(DAI, _data2);
    }

    function test_addCollateral(
        uint16 _baseFeeIn,
        uint16 _baseFeeOut,
        uint16 _downsidePeg,
        uint16 _collateralComposition
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseFeeIn <= manager.PERC_PRECISION());
        vm.assume(_baseFeeOut <= manager.PERC_PRECISION());
        vm.assume(_downsidePeg <= manager.PERC_PRECISION());
        vm.assume(_collateralComposition <= manager.PERC_PRECISION());

        ICollateralManager.CollateralBaseData memory _data = ICollateralManager
            .CollateralBaseData({
                mintAllowed: true,
                redeemAllowed: true,
                allocationAllowed: true,
                baseFeeIn: _baseFeeIn,
                baseFeeOut: _baseFeeOut,
                downsidePeg: _downsidePeg,
                desiredCollateralComposition: _collateralComposition
            });
        manager.addCollateral(USDCe, _data);
    }
}

contract CollateralManager_updateCollateral_Test is CollateralManagerTest {
    function test_revertsWhen_updateNonExistingCollateral(
        uint16 _baseFeeIn,
        uint16 _baseFeeOut,
        uint16 _downsidePeg,
        uint16 _collateralComposition
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseFeeIn <= manager.PERC_PRECISION());
        vm.assume(_baseFeeOut <= manager.PERC_PRECISION());
        vm.assume(_downsidePeg <= manager.PERC_PRECISION());
        vm.assume(_collateralComposition <= manager.PERC_PRECISION());

        ICollateralManager.CollateralBaseData memory _data = ICollateralManager
            .CollateralBaseData({
                mintAllowed: true,
                redeemAllowed: true,
                allocationAllowed: true,
                baseFeeIn: _baseFeeIn,
                baseFeeOut: _baseFeeOut,
                downsidePeg: _downsidePeg,
                desiredCollateralComposition: _collateralComposition
            });
        vm.expectRevert("Collateral doesn't exist");
        manager.updateCollateralData(USDCe, _data);
    }

    function test_revertsWhen_collateralCompositionExceeded(
        uint16 _baseFeeIn,
        uint16 _baseFeeOut,
        uint16 _downsidePeg
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseFeeIn <= manager.PERC_PRECISION());
        vm.assume(_baseFeeOut <= manager.PERC_PRECISION());
        vm.assume(_downsidePeg <= manager.PERC_PRECISION());

        ICollateralManager.CollateralBaseData memory _data = ICollateralManager
            .CollateralBaseData({
                mintAllowed: true,
                redeemAllowed: true,
                allocationAllowed: true,
                baseFeeIn: _baseFeeIn,
                baseFeeOut: _baseFeeOut,
                downsidePeg: _downsidePeg,
                desiredCollateralComposition: 9000
            });
        ICollateralManager.CollateralBaseData memory _data2 = ICollateralManager
            .CollateralBaseData({
                mintAllowed: true,
                redeemAllowed: true,
                allocationAllowed: true,
                baseFeeIn: _baseFeeIn,
                baseFeeOut: _baseFeeOut,
                downsidePeg: _downsidePeg,
                desiredCollateralComposition: 10001
            });
        manager.addCollateral(USDCe, _data);
        vm.expectRevert("Collateral composition exceeded");
        manager.updateCollateralData(USDCe, _data2);
    }

    function test_updateCollateral(
        uint16 _baseFeeIn,
        uint16 _baseFeeOut,
        uint16 _downsidePeg,
        uint16 _collateralComposition
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseFeeIn <= manager.PERC_PRECISION());
        vm.assume(_baseFeeOut <= manager.PERC_PRECISION());
        vm.assume(_downsidePeg <= manager.PERC_PRECISION());
        vm.assume(_collateralComposition <= manager.PERC_PRECISION());

        ICollateralManager.CollateralBaseData memory _data = ICollateralManager
            .CollateralBaseData({
                mintAllowed: true,
                redeemAllowed: true,
                allocationAllowed: true,
                baseFeeIn: _baseFeeIn,
                baseFeeOut: _baseFeeOut,
                downsidePeg: _downsidePeg,
                desiredCollateralComposition: _collateralComposition
            });
        ICollateralManager.CollateralBaseData
            memory _dataUpdated = ICollateralManager.CollateralBaseData({
                mintAllowed: true,
                redeemAllowed: true,
                allocationAllowed: true,
                baseFeeIn: _baseFeeIn,
                baseFeeOut: _baseFeeOut,
                downsidePeg: _downsidePeg,
                desiredCollateralComposition: _collateralComposition
            });
        manager.addCollateral(USDCe, _data);
        manager.updateCollateralData(USDCe, _dataUpdated);
    }
}

contract CollateralManager_removeCollateral_Test is CollateralManagerTest {
    function test_revertsWhen_removeNonExistingCollateral()
        external
        useKnownActor(USDS_OWNER)
    {
        vm.expectRevert("Collateral doesn't exist");
        manager.removeCollateral(USDCe);
    }

    function test_removeMultipleCollaterals(
        uint16 _baseFeeIn,
        uint16 _baseFeeOut,
        uint16 _downsidePeg,
        uint16 _collateralComposition
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseFeeIn <= manager.PERC_PRECISION());
        vm.assume(_baseFeeOut <= manager.PERC_PRECISION());
        vm.assume(_downsidePeg <= manager.PERC_PRECISION());
        vm.assume(_collateralComposition <= manager.PERC_PRECISION());

        ICollateralManager.CollateralBaseData memory _data = ICollateralManager
            .CollateralBaseData({
                mintAllowed: true,
                redeemAllowed: true,
                allocationAllowed: true,
                baseFeeIn: _baseFeeIn,
                baseFeeOut: _baseFeeOut,
                downsidePeg: _downsidePeg,
                desiredCollateralComposition: 1000
            });
        manager.addCollateral(USDCe, _data);
        manager.addCollateral(USDT, _data);
        manager.addCollateral(DAI, _data);
        manager.addCollateral(VST, _data);

        // vm.expectRevert("Collateral doesn't exist");
        manager.removeCollateral(USDT);
        manager.removeCollateral(USDCe);
        manager.removeCollateral(VST);
        manager.removeCollateral(DAI);
    }

    function test_revertsWhen_removeStrategyCollateralStrategyExists(
        uint16 _baseFeeIn,
        uint16 _baseFeeOut,
        uint16 _downsidePeg,
        uint16 _collateralComposition
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseFeeIn <= manager.PERC_PRECISION());
        vm.assume(_baseFeeOut <= manager.PERC_PRECISION());
        vm.assume(_downsidePeg <= manager.PERC_PRECISION());
        vm.assume(_collateralComposition <= manager.PERC_PRECISION());

        ICollateralManager.CollateralBaseData memory _data = ICollateralManager
            .CollateralBaseData({
                mintAllowed: true,
                redeemAllowed: true,
                allocationAllowed: true,
                baseFeeIn: _baseFeeIn,
                baseFeeOut: _baseFeeOut,
                downsidePeg: _downsidePeg,
                desiredCollateralComposition: 1000
            });
        manager.addCollateral(USDCe, _data);
        manager.addCollateralStrategy(USDCe, stargate, 1000);
        // manager.addCollateralStrategy(USDCe,AAVE,10000);
        vm.expectRevert("Strategy/ies exists");
        manager.removeCollateral(USDCe);
    }
}

contract CollateralManager_addCollateralStrategy_Test is CollateralManagerTest {
    function test_revertsWhen_collateralDoesntExist(
        uint16 _collateralComposition
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_collateralComposition <= manager.PERC_PRECISION());
        vm.expectRevert("Collateral doesn't exist");
        manager.addCollateralStrategy(USDCe, stargate, 1000);
    }

    function test_revertsWhen_addCollateralstrategyWhenAlreadyMapped(
        uint16 _baseFeeIn,
        uint16 _baseFeeOut,
        uint16 _downsidePeg,
        uint16 _collateralComposition
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseFeeIn <= manager.PERC_PRECISION());
        vm.assume(_baseFeeOut <= manager.PERC_PRECISION());
        vm.assume(_downsidePeg <= manager.PERC_PRECISION());
        vm.assume(_collateralComposition <= manager.PERC_PRECISION());

        ICollateralManager.CollateralBaseData memory _data = ICollateralManager
            .CollateralBaseData({
                mintAllowed: true,
                redeemAllowed: true,
                allocationAllowed: true,
                baseFeeIn: _baseFeeIn,
                baseFeeOut: _baseFeeOut,
                downsidePeg: _downsidePeg,
                desiredCollateralComposition: 1000
            });
        manager.addCollateral(USDCe, _data);
        manager.addCollateralStrategy(USDCe, stargate, 1000);
        vm.expectRevert("Strategy already mapped");
        manager.addCollateralStrategy(USDCe, stargate, 2000);
    }

    function test_revertsWhen_addCollateralstrategyNotSupported(
        uint16 _baseFeeIn,
        uint16 _baseFeeOut,
        uint16 _downsidePeg,
        uint16 _collateralComposition
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseFeeIn <= manager.PERC_PRECISION());
        vm.assume(_baseFeeOut <= manager.PERC_PRECISION());
        vm.assume(_downsidePeg <= manager.PERC_PRECISION());
        vm.assume(_collateralComposition <= manager.PERC_PRECISION());

        ICollateralManager.CollateralBaseData memory _data = ICollateralManager
            .CollateralBaseData({
                mintAllowed: true,
                redeemAllowed: true,
                allocationAllowed: true,
                baseFeeIn: _baseFeeIn,
                baseFeeOut: _baseFeeOut,
                downsidePeg: _downsidePeg,
                desiredCollateralComposition: 1000
            });
        manager.addCollateral(USDT, _data);
        vm.expectRevert("Collateral not supported");
        manager.addCollateralStrategy(USDT, stargate, 2000);
    }

    function test_revertsWhen_addCollateralstrategyAllocationPerExceeded(
        uint16 _baseFeeIn,
        uint16 _baseFeeOut,
        uint16 _downsidePeg,
        uint16 _collateralComposition
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseFeeIn <= manager.PERC_PRECISION());
        vm.assume(_baseFeeOut <= manager.PERC_PRECISION());
        vm.assume(_downsidePeg <= manager.PERC_PRECISION());
        vm.assume(_collateralComposition <= manager.PERC_PRECISION());

        ICollateralManager.CollateralBaseData memory _data = ICollateralManager
            .CollateralBaseData({
                mintAllowed: true,
                redeemAllowed: true,
                allocationAllowed: true,
                baseFeeIn: _baseFeeIn,
                baseFeeOut: _baseFeeOut,
                downsidePeg: _downsidePeg,
                desiredCollateralComposition: 1000
            });
        manager.addCollateral(USDCe, _data);
        vm.expectRevert("AllocationPer exceeded");
        manager.addCollateralStrategy(USDCe, stargate, 10001);
    }
}

contract CollateralManager_updateCollateralStrategy_Test is
    CollateralManagerTest
{
    function test_revertsWhen_collateralDoesntExist(
        uint16 _collateralComposition
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_collateralComposition <= manager.PERC_PRECISION());
        vm.expectRevert("Collateral doesn't exist");
        manager.addCollateralStrategy(USDCe, stargate, 1000);
    }

    function test_revertsWhen_updateCollateralstrategyWhenAlreadyMapped(
        uint16 _baseFeeIn,
        uint16 _baseFeeOut,
        uint16 _downsidePeg,
        uint16 _collateralComposition
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseFeeIn <= manager.PERC_PRECISION());
        vm.assume(_baseFeeOut <= manager.PERC_PRECISION());
        vm.assume(_downsidePeg <= manager.PERC_PRECISION());
        vm.assume(_collateralComposition <= manager.PERC_PRECISION());

        ICollateralManager.CollateralBaseData memory _data = ICollateralManager
            .CollateralBaseData({
                mintAllowed: true,
                redeemAllowed: true,
                allocationAllowed: true,
                baseFeeIn: _baseFeeIn,
                baseFeeOut: _baseFeeOut,
                downsidePeg: _downsidePeg,
                desiredCollateralComposition: 1000
            });
        manager.addCollateral(USDCe, _data);
        vm.expectRevert("Strategy not mapped");
        manager.updateCollateralStrategy(USDCe, stargate, 2000);
    }

    function test_updateCollateralStrategy(
        uint16 _baseFeeIn,
        uint16 _baseFeeOut,
        uint16 _downsidePeg,
        uint16 _collateralComposition
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseFeeIn <= manager.PERC_PRECISION());
        vm.assume(_baseFeeOut <= manager.PERC_PRECISION());
        vm.assume(_downsidePeg <= manager.PERC_PRECISION());
        vm.assume(_collateralComposition <= manager.PERC_PRECISION());

        ICollateralManager.CollateralBaseData memory _data = ICollateralManager
            .CollateralBaseData({
                mintAllowed: true,
                redeemAllowed: true,
                allocationAllowed: true,
                baseFeeIn: _baseFeeIn,
                baseFeeOut: _baseFeeOut,
                downsidePeg: _downsidePeg,
                desiredCollateralComposition: 1000
            });
        manager.addCollateral(USDCe, _data);
        manager.addCollateralStrategy(USDCe, stargate, 2000);
        manager.updateCollateralStrategy(USDCe, stargate, 3500);
    }

    function test_revertsWhen_updateCollateralstrategyAllocationPerExceeded(
        uint16 _baseFeeIn,
        uint16 _baseFeeOut,
        uint16 _downsidePeg,
        uint16 _collateralComposition
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseFeeIn <= manager.PERC_PRECISION());
        vm.assume(_baseFeeOut <= manager.PERC_PRECISION());
        vm.assume(_downsidePeg <= manager.PERC_PRECISION());
        vm.assume(_collateralComposition <= manager.PERC_PRECISION());

        ICollateralManager.CollateralBaseData memory _data = ICollateralManager
            .CollateralBaseData({
                mintAllowed: true,
                redeemAllowed: true,
                allocationAllowed: true,
                baseFeeIn: _baseFeeIn,
                baseFeeOut: _baseFeeOut,
                downsidePeg: _downsidePeg,
                desiredCollateralComposition: 1000
            });
        manager.addCollateral(USDCe, _data);
        manager.addCollateralStrategy(USDCe, stargate, 2000);
        vm.expectRevert("AllocationPer exceeded");
        manager.updateCollateralStrategy(USDCe, stargate, 10001);
    }

    function test_revertsWhen_updateCollateralstrategyAllocationNotValid(
        uint16 _baseFeeIn,
        uint16 _baseFeeOut,
        uint16 _downsidePeg,
        uint16 _collateralComposition
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseFeeIn <= manager.PERC_PRECISION());
        vm.assume(_baseFeeOut <= manager.PERC_PRECISION());
        vm.assume(_downsidePeg <= manager.PERC_PRECISION());
        vm.assume(_collateralComposition <= manager.PERC_PRECISION());

        ICollateralManager.CollateralBaseData memory _data = ICollateralManager
            .CollateralBaseData({
                mintAllowed: true,
                redeemAllowed: true,
                allocationAllowed: true,
                baseFeeIn: _baseFeeIn,
                baseFeeOut: _baseFeeOut,
                downsidePeg: _downsidePeg,
                desiredCollateralComposition: 1000
            });
        manager.addCollateral(USDCe, _data);
        manager.addCollateralStrategy(USDCe, stargate, 1);
        vm.expectRevert("AllocationPer not valid");
        manager.updateCollateralStrategy(USDCe, stargate, 10000);
    }
}

contract CollateralManager_removeCollateralStrategy_Test is
    CollateralManagerTest
{
    function test_revertsWhen_strategyNotMapped(
        uint16 _baseFeeIn,
        uint16 _baseFeeOut,
        uint16 _downsidePeg,
        uint16 _collateralComposition
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseFeeIn <= manager.PERC_PRECISION());
        vm.assume(_baseFeeOut <= manager.PERC_PRECISION());
        vm.assume(_downsidePeg <= manager.PERC_PRECISION());
        vm.assume(_collateralComposition <= manager.PERC_PRECISION());

        ICollateralManager.CollateralBaseData memory _data = ICollateralManager
            .CollateralBaseData({
                mintAllowed: true,
                redeemAllowed: true,
                allocationAllowed: true,
                baseFeeIn: _baseFeeIn,
                baseFeeOut: _baseFeeOut,
                downsidePeg: _downsidePeg,
                desiredCollateralComposition: 1000
            });
        manager.addCollateral(USDCe, _data);
        vm.expectRevert("Strategy not mapped");
        manager.removeCollateralStrategy(USDCe, stargate);
    }

    function test_removeCollateralStrategy(
        uint16 _baseFeeIn,
        uint16 _baseFeeOut,
        uint16 _downsidePeg,
        uint16 _collateralComposition
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseFeeIn <= manager.PERC_PRECISION());
        vm.assume(_baseFeeOut <= manager.PERC_PRECISION());
        vm.assume(_downsidePeg <= manager.PERC_PRECISION());
        vm.assume(_collateralComposition <= manager.PERC_PRECISION());

        ICollateralManager.CollateralBaseData memory _data = ICollateralManager
            .CollateralBaseData({
                mintAllowed: true,
                redeemAllowed: true,
                allocationAllowed: true,
                baseFeeIn: _baseFeeIn,
                baseFeeOut: _baseFeeOut,
                downsidePeg: _downsidePeg,
                desiredCollateralComposition: 1000
            });
        manager.addCollateral(USDCe, _data);
        manager.addCollateral(DAI, _data);
        manager.addCollateralStrategy(USDCe, stargate, 2000);
        manager.addCollateralStrategy(USDCe, AAVE, 2000);
        manager.removeCollateralStrategy(USDCe, AAVE);
    }

    function test_revertsWhen_strategyInUse(
        uint16 _baseFeeIn,
        uint16 _baseFeeOut,
        uint16 _downsidePeg,
        uint16 _collateralComposition
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseFeeIn <= manager.PERC_PRECISION());
        vm.assume(_baseFeeOut <= manager.PERC_PRECISION());
        vm.assume(_downsidePeg <= manager.PERC_PRECISION());
        vm.assume(_collateralComposition <= manager.PERC_PRECISION());

        ICollateralManager.CollateralBaseData memory _data = ICollateralManager
            .CollateralBaseData({
                mintAllowed: true,
                redeemAllowed: true,
                allocationAllowed: true,
                baseFeeIn: _baseFeeIn,
                baseFeeOut: _baseFeeOut,
                downsidePeg: _downsidePeg,
                desiredCollateralComposition: 1000
            });
        manager.addCollateral(USDCe, _data);
        manager.addCollateralStrategy(USDCe, stargate, 2000);
        vm.expectRevert("Strategy in use");
        manager.removeCollateralStrategy(USDCe, stargate);
    }

    function test_revertsWhen_DefaultStrategy(
        uint16 _baseFeeIn,
        uint16 _baseFeeOut,
        uint16 _downsidePeg,
        uint16 _collateralComposition
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseFeeIn <= manager.PERC_PRECISION());
        vm.assume(_baseFeeOut <= manager.PERC_PRECISION());
        vm.assume(_downsidePeg <= manager.PERC_PRECISION());
        vm.assume(_collateralComposition <= manager.PERC_PRECISION());

        ICollateralManager.CollateralBaseData memory _data = ICollateralManager
            .CollateralBaseData({
                mintAllowed: true,
                redeemAllowed: true,
                allocationAllowed: true,
                baseFeeIn: _baseFeeIn,
                baseFeeOut: _baseFeeOut,
                downsidePeg: _downsidePeg,
                desiredCollateralComposition: 1000
            });
        manager.addCollateral(USDCe, _data);
        manager.addCollateralStrategy(USDCe, stargate, 2000);
        manager.updateCollateralDefaultStrategy(USDCe, stargate);
        vm.expectRevert("DS removal not allowed");
        manager.removeCollateralStrategy(USDCe, stargate);
    }

    function test_revertsWhen_DefaultStrategyNotExist(
        uint16 _baseFeeIn,
        uint16 _baseFeeOut,
        uint16 _downsidePeg,
        uint16 _collateralComposition
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseFeeIn <= manager.PERC_PRECISION());
        vm.assume(_baseFeeOut <= manager.PERC_PRECISION());
        vm.assume(_downsidePeg <= manager.PERC_PRECISION());
        vm.assume(_collateralComposition <= manager.PERC_PRECISION());

        ICollateralManager.CollateralBaseData memory _data = ICollateralManager
            .CollateralBaseData({
                mintAllowed: true,
                redeemAllowed: true,
                allocationAllowed: true,
                baseFeeIn: _baseFeeIn,
                baseFeeOut: _baseFeeOut,
                downsidePeg: _downsidePeg,
                desiredCollateralComposition: 1000
            });
        manager.addCollateral(USDCe, _data);
        manager.addCollateralStrategy(USDCe, stargate, 2000);
        vm.expectRevert("Collateral doesn't exist");
        manager.updateCollateralDefaultStrategy(VST, stargate);
    }
}

contract CollateralManager_validateAllocation_test is CollateralManagerTest {
    function test_revertsWhen_validateAllocationNotAllowed(
        uint16 _baseFeeIn,
        uint16 _baseFeeOut,
        uint16 _downsidePeg,
        uint16 _collateralComposition
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseFeeIn <= manager.PERC_PRECISION());
        vm.assume(_baseFeeOut <= manager.PERC_PRECISION());
        vm.assume(_downsidePeg <= manager.PERC_PRECISION());
        vm.assume(_collateralComposition <= manager.PERC_PRECISION());

        ICollateralManager.CollateralBaseData memory _data = ICollateralManager
            .CollateralBaseData({
                mintAllowed: true,
                redeemAllowed: true,
                allocationAllowed: false,
                baseFeeIn: _baseFeeIn,
                baseFeeOut: _baseFeeOut,
                downsidePeg: _downsidePeg,
                desiredCollateralComposition: 1000
            });
        manager.addCollateral(USDT, _data);
        manager.addCollateralStrategy(USDT, USDTTWOPOOLSTRATEGY, 2000);
        vm.expectRevert("Allocation not allowed");
        manager.validateAllocation(USDT, USDTTWOPOOLSTRATEGY, 1);
    }

    function test_validateAllocation(
        uint16 _baseFeeIn,
        uint16 _baseFeeOut,
        uint16 _downsidePeg,
        uint16 _collateralComposition
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseFeeIn <= manager.PERC_PRECISION());
        vm.assume(_baseFeeOut <= manager.PERC_PRECISION());
        vm.assume(_downsidePeg <= manager.PERC_PRECISION());
        vm.assume(_collateralComposition <= manager.PERC_PRECISION());

        ICollateralManager.CollateralBaseData memory _data = ICollateralManager
            .CollateralBaseData({
                mintAllowed: true,
                redeemAllowed: true,
                allocationAllowed: true,
                baseFeeIn: _baseFeeIn,
                baseFeeOut: _baseFeeOut,
                downsidePeg: _downsidePeg,
                desiredCollateralComposition: 1000
            });
        manager.addCollateral(USDCe, _data);
        manager.addCollateralStrategy(USDCe, stargate, 2000);
        manager.validateAllocation(USDCe, stargate, 1000);
    }

    function test_validateAllocationMaxCollateralUsageSup(
        uint16 _baseFeeIn,
        uint16 _baseFeeOut,
        uint16 _downsidePeg,
        uint16 _collateralComposition
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseFeeIn <= manager.PERC_PRECISION());
        vm.assume(_baseFeeOut <= manager.PERC_PRECISION());
        vm.assume(_downsidePeg <= manager.PERC_PRECISION());
        vm.assume(_collateralComposition <= manager.PERC_PRECISION());

        ICollateralManager.CollateralBaseData memory _data = ICollateralManager
            .CollateralBaseData({
                mintAllowed: true,
                redeemAllowed: true,
                allocationAllowed: true,
                baseFeeIn: _baseFeeIn,
                baseFeeOut: _baseFeeOut,
                downsidePeg: _downsidePeg,
                desiredCollateralComposition: 1000
            });
        manager.addCollateral(USDCe, _data);
        manager.addCollateralStrategy(USDCe, stargate, 10000);
        manager.validateAllocation(USDCe, stargate, 11000000000);
    }

    function test_getAllCollaterals(
        uint16 _baseFeeIn,
        uint16 _baseFeeOut,
        uint16 _downsidePeg,
        uint16 _collateralComposition
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseFeeIn <= manager.PERC_PRECISION());
        vm.assume(_baseFeeOut <= manager.PERC_PRECISION());
        vm.assume(_downsidePeg <= manager.PERC_PRECISION());
        vm.assume(_collateralComposition <= manager.PERC_PRECISION());

        ICollateralManager.CollateralBaseData memory _data = ICollateralManager
            .CollateralBaseData({
                mintAllowed: true,
                redeemAllowed: true,
                allocationAllowed: true,
                baseFeeIn: _baseFeeIn,
                baseFeeOut: _baseFeeOut,
                downsidePeg: _downsidePeg,
                desiredCollateralComposition: 1000
            });
        manager.addCollateral(USDCe, _data);
        manager.addCollateral(USDT, _data);
        manager.addCollateral(VST, _data);
        manager.addCollateral(FRAX, _data);
        manager.addCollateral(DAI, _data);
        manager.addCollateralStrategy(USDCe, AAVE, 2000);

        (manager.getAllCollaterals());
    }

    function test_getZeroCollaterals() external useKnownActor(USDS_OWNER) {
        manager.getAllCollaterals();
    }

    function test_getCollateralStrategies(
        uint16 _baseFeeIn,
        uint16 _baseFeeOut,
        uint16 _downsidePeg,
        uint16 _collateralComposition
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseFeeIn <= manager.PERC_PRECISION());
        vm.assume(_baseFeeOut <= manager.PERC_PRECISION());
        vm.assume(_downsidePeg <= manager.PERC_PRECISION());
        vm.assume(_collateralComposition <= manager.PERC_PRECISION());

        ICollateralManager.CollateralBaseData memory _data = ICollateralManager
            .CollateralBaseData({
                mintAllowed: true,
                redeemAllowed: true,
                allocationAllowed: true,
                baseFeeIn: _baseFeeIn,
                baseFeeOut: _baseFeeOut,
                downsidePeg: _downsidePeg,
                desiredCollateralComposition: 1000
            });
        manager.addCollateral(USDCe, _data);
        manager.addCollateralStrategy(USDCe, AAVE, 2000);
        manager.addCollateralStrategy(USDCe, stargate, 2000);
        manager.isValidStrategy(USDCe, AAVE);
        manager.isValidStrategy(USDT, USDCe);

        manager.getCollateralStrategies(USDCe);
    }
}

contract CollateralManager_mintRedeemParams_test is CollateralManagerTest {
    function test_getMintParams(
        uint16 _baseFeeIn,
        uint16 _baseFeeOut,
        uint16 _downsidePeg,
        uint16 _collateralComposition
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseFeeIn <= manager.PERC_PRECISION());
        vm.assume(_baseFeeOut <= manager.PERC_PRECISION());
        vm.assume(_downsidePeg <= manager.PERC_PRECISION());
        vm.assume(_collateralComposition <= manager.PERC_PRECISION());

        ICollateralManager.CollateralBaseData memory _data = ICollateralManager
            .CollateralBaseData({
                mintAllowed: true,
                redeemAllowed: true,
                allocationAllowed: true,
                baseFeeIn: _baseFeeIn,
                baseFeeOut: _baseFeeOut,
                downsidePeg: _downsidePeg,
                desiredCollateralComposition: 1000
            });
        manager.addCollateral(USDCe, _data);
        manager.addCollateral(DAI, _data);
        manager.addCollateralStrategy(USDCe, stargate, 2000);
        manager.addCollateralStrategy(USDCe, AAVE, 2000);
        manager.getMintParams(USDCe);
    }

    function test_revertsWhen_getMintParams_collateralDoesntExist()
        external
        useKnownActor(USDS_OWNER)
    {
        vm.expectRevert("Collateral doesn't exist");
        manager.getMintParams(USDT);
    }

    function test_getRedeemParams(
        uint16 _baseFeeIn,
        uint16 _baseFeeOut,
        uint16 _downsidePeg,
        uint16 _collateralComposition
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseFeeIn <= manager.PERC_PRECISION());
        vm.assume(_baseFeeOut <= manager.PERC_PRECISION());
        vm.assume(_downsidePeg <= manager.PERC_PRECISION());
        vm.assume(_collateralComposition <= manager.PERC_PRECISION());

        ICollateralManager.CollateralBaseData memory _data = ICollateralManager
            .CollateralBaseData({
                mintAllowed: true,
                redeemAllowed: true,
                allocationAllowed: true,
                baseFeeIn: _baseFeeIn,
                baseFeeOut: _baseFeeOut,
                downsidePeg: _downsidePeg,
                desiredCollateralComposition: 1000
            });
        manager.addCollateral(USDCe, _data);
        manager.addCollateral(DAI, _data);
        manager.addCollateralStrategy(USDCe, stargate, 2000);
        manager.addCollateralStrategy(USDCe, AAVE, 2000);
        manager.getRedeemParams(USDCe);
    }

    function test_revertsWhen_getRedeemParams_collateralDoesntExist()
        external
        useKnownActor(USDS_OWNER)
    {
        vm.expectRevert("Collateral doesn't exist");
        manager.getRedeemParams(USDT);
    }
}
