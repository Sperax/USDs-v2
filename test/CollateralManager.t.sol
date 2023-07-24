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
    event CollateralAdded(
        address collateral,
        ICollateralManager.CollateralBaseData data
    );
    event CollateralRemoved(address collateral);
    event CollateralInfoUpdated(
        address collateral,
        ICollateralManager.CollateralBaseData data
    );
    event CollateralStrategyAdded(address collateral, address strategy);
    event CollateralStrategyUpdated(address collateral, address strategy);
    event CollateralStrategyRemoved(address collateral, address strategy);

    function setUp() public override {
        super.setUp();
        setArbitrumFork();
        manager = new CollateralManager(VAULT);
        manager.transferOwnership(USDS_OWNER);
    }

    function collateralSetUp(
        address _collateralAsset,
        uint16 desiredCollateralComposition,
        uint16 _baseFeeIn,
        uint16 _baseFeeOut,
        uint16 _downsidePeg
    ) public {
        ICollateralManager.CollateralBaseData memory _data = ICollateralManager
            .CollateralBaseData({
                mintAllowed: true,
                redeemAllowed: true,
                allocationAllowed: true,
                baseFeeIn: _baseFeeIn,
                baseFeeOut: _baseFeeOut,
                downsidePeg: _downsidePeg,
                desiredCollateralComposition: desiredCollateralComposition
            });

        manager.addCollateral(_collateralAsset, _data);
    }

    function collateralUpdate(
        address _collateralAsset,
        uint16 desiredCollateralComposition,
        uint16 _baseFeeIn,
        uint16 _baseFeeOut,
        uint16 _downsidePeg
    ) public {
        ICollateralManager.CollateralBaseData memory _data = ICollateralManager
            .CollateralBaseData({
                mintAllowed: true,
                redeemAllowed: true,
                allocationAllowed: true,
                baseFeeIn: _baseFeeIn,
                baseFeeOut: _baseFeeOut,
                downsidePeg: _downsidePeg,
                desiredCollateralComposition: desiredCollateralComposition
            });

        manager.updateCollateralData(_collateralAsset, _data);
    }
}

contract CollateralManager_AddCollateral_Test is CollateralManagerTest {
    function test_revertsWhen_baseFeeExceedsMax(
        uint16 _baseFeeIn,
        uint16 _baseFeeOut,
        uint16 _downsidePeg,
        uint16 _colComp
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseFeeIn > manager.PERC_PRECISION());
        vm.assume(_baseFeeOut > manager.PERC_PRECISION());
        vm.assume(_downsidePeg > manager.PERC_PRECISION());

        vm.expectRevert("Illegal PERC input");
        collateralSetUp(USDCe, _colComp, _baseFeeIn, _baseFeeOut, _downsidePeg);
    }

    function test_revertsWhen_addSameCollateral(
        uint16 _baseFeeIn,
        uint16 _baseFeeOut,
        uint16 _downsidePeg,
        uint16 _colComp
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_colComp <= manager.PERC_PRECISION());
        vm.assume(_baseFeeIn <= manager.PERC_PRECISION());
        vm.assume(_baseFeeOut <= manager.PERC_PRECISION());
        vm.assume(_downsidePeg <= manager.PERC_PRECISION());

        collateralSetUp(USDCe, _colComp, _baseFeeIn, _baseFeeOut, _downsidePeg);
        vm.expectRevert("Collateral already exists");
        collateralSetUp(USDCe, _colComp, _baseFeeIn, _baseFeeOut, _downsidePeg);
    }

    function test_revertsWhen_collateralCompositionExceeded(
        uint16 _baseFeeIn,
        uint16 _baseFeeOut,
        uint16 _downsidePeg
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseFeeIn <= manager.PERC_PRECISION());
        vm.assume(_baseFeeOut <= manager.PERC_PRECISION());
        vm.assume(_downsidePeg <= manager.PERC_PRECISION());

        collateralSetUp(USDCe, 9000, _baseFeeIn, _baseFeeOut, _downsidePeg);
        vm.expectRevert("Collateral compostion exceeded");
        collateralSetUp(USDT, 1001, _baseFeeIn, _baseFeeOut, _downsidePeg);
    }

    function test_addCollateral(
        uint16 _baseFeeIn,
        uint16 _baseFeeOut,
        uint16 _downsidePeg,
        uint16 _colComp
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseFeeIn <= manager.PERC_PRECISION());
        vm.assume(_baseFeeOut <= manager.PERC_PRECISION());
        vm.assume(_downsidePeg <= manager.PERC_PRECISION());
        vm.assume(_colComp <= manager.PERC_PRECISION());
        ICollateralManager.CollateralBaseData memory _data = ICollateralManager
            .CollateralBaseData({
                mintAllowed: true,
                redeemAllowed: true,
                allocationAllowed: true,
                baseFeeIn: _baseFeeIn,
                baseFeeOut: _baseFeeOut,
                downsidePeg: _downsidePeg,
                desiredCollateralComposition: _colComp
            });

        vm.expectEmit(true, true, false, true);
        emit CollateralAdded(USDCe, _data);

        manager.addCollateral(USDCe, _data);
    }
}

contract CollateralManager_updateCollateral_Test is CollateralManagerTest {
    function test_revertsWhen_updateNonExistingCollateral(
        uint16 _baseFeeIn,
        uint16 _baseFeeOut,
        uint16 _downsidePeg,
        uint16 _colComp
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseFeeIn <= manager.PERC_PRECISION());
        vm.assume(_baseFeeOut <= manager.PERC_PRECISION());
        vm.assume(_downsidePeg <= manager.PERC_PRECISION());
        vm.assume(_colComp <= manager.PERC_PRECISION());

        vm.expectRevert("Collateral doesn't exist");
        collateralUpdate(USDT, _colComp, _baseFeeIn, _baseFeeOut, _downsidePeg);
    }

    function test_revertsWhen_collateralCompositionExceeded(
        uint16 _baseFeeIn,
        uint16 _baseFeeOut,
        uint16 _downsidePeg,
        uint16 _colComp,
        uint16 _colComp2
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseFeeIn <= manager.PERC_PRECISION());
        vm.assume(_baseFeeOut <= manager.PERC_PRECISION());
        vm.assume(_downsidePeg <= manager.PERC_PRECISION());
        vm.assume(_colComp <= manager.PERC_PRECISION());
        vm.assume(_colComp2 > manager.PERC_PRECISION());

        collateralSetUp(USDT, _colComp, _baseFeeIn, _baseFeeOut, _downsidePeg);
        vm.expectRevert("Collateral compostion exceeded");

        collateralUpdate(
            USDT,
            _colComp2,
            _baseFeeIn,
            _baseFeeOut,
            _downsidePeg
        );
    }

    function test_updateCollateral(
        uint16 _baseFeeIn,
        uint16 _baseFeeOut,
        uint16 _downsidePeg,
        uint16 _colComp
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseFeeIn <= manager.PERC_PRECISION());
        vm.assume(_baseFeeOut <= manager.PERC_PRECISION());
        vm.assume(_downsidePeg <= manager.PERC_PRECISION());
        vm.assume(_colComp <= manager.PERC_PRECISION());

        ICollateralManager.CollateralBaseData
            memory _dataUpdated = ICollateralManager.CollateralBaseData({
                mintAllowed: true,
                redeemAllowed: true,
                allocationAllowed: true,
                baseFeeIn: _baseFeeIn,
                baseFeeOut: _baseFeeOut,
                downsidePeg: _downsidePeg,
                desiredCollateralComposition: _colComp
            });
        collateralSetUp(USDCe, _colComp, _baseFeeIn, _baseFeeOut, _downsidePeg);

        vm.expectEmit(true, true, false, true);
        emit CollateralInfoUpdated(USDCe, _dataUpdated);

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
        uint16 _downsidePeg
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseFeeIn <= manager.PERC_PRECISION());
        vm.assume(_baseFeeOut <= manager.PERC_PRECISION());
        vm.assume(_downsidePeg <= manager.PERC_PRECISION());

        collateralSetUp(USDCe, 1000, _baseFeeIn, _baseFeeOut, _downsidePeg);
        collateralSetUp(USDT, 1500, _baseFeeIn, _baseFeeOut, _downsidePeg);
        collateralSetUp(DAI, 2000, _baseFeeIn, _baseFeeOut, _downsidePeg);
        collateralSetUp(VST, 3000, _baseFeeIn, _baseFeeOut, _downsidePeg);

        vm.expectEmit(true, true, false, true);
        emit CollateralRemoved(USDT);
        manager.removeCollateral(USDT);

        vm.expectEmit(true, true, false, true);
        emit CollateralRemoved(USDCe);
        manager.removeCollateral(USDCe);

        vm.expectEmit(true, true, false, true);
        emit CollateralRemoved(VST);
        manager.removeCollateral(VST);

        vm.expectEmit(true, true, false, true);
        emit CollateralRemoved(DAI);
        manager.removeCollateral(DAI);
    }

    function test_revertsWhen_removeStrategyCollateralStrategyExists(
        uint16 _baseFeeIn,
        uint16 _baseFeeOut,
        uint16 _downsidePeg,
        uint16 _colComp
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseFeeIn <= manager.PERC_PRECISION());
        vm.assume(_baseFeeOut <= manager.PERC_PRECISION());
        vm.assume(_downsidePeg <= manager.PERC_PRECISION());
        vm.assume(_colComp <= manager.PERC_PRECISION());

        collateralSetUp(USDCe, _colComp, _baseFeeIn, _baseFeeOut, _downsidePeg);
        manager.addCollateralStrategy(USDCe, stargate, _colComp);
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
        uint16 _colComp
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseFeeIn <= manager.PERC_PRECISION());
        vm.assume(_baseFeeOut <= manager.PERC_PRECISION());
        vm.assume(_downsidePeg <= manager.PERC_PRECISION());
        vm.assume(_colComp <= manager.PERC_PRECISION());

        collateralSetUp(USDCe, _colComp, _baseFeeIn, _baseFeeOut, _downsidePeg);
        manager.addCollateralStrategy(USDCe, stargate, _colComp);
        vm.expectRevert("Strategy already mapped");
        manager.addCollateralStrategy(USDCe, stargate, _colComp);
    }

    function test_revertsWhen_addCollateralstrategyNotSupported(
        uint16 _baseFeeIn,
        uint16 _baseFeeOut,
        uint16 _downsidePeg,
        uint16 _colComp
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseFeeIn <= manager.PERC_PRECISION());
        vm.assume(_baseFeeOut <= manager.PERC_PRECISION());
        vm.assume(_downsidePeg <= manager.PERC_PRECISION());
        vm.assume(_colComp <= manager.PERC_PRECISION());

        collateralSetUp(USDT, _colComp, _baseFeeIn, _baseFeeOut, _downsidePeg);
        vm.expectRevert("Collateral not supported");
        manager.addCollateralStrategy(USDT, stargate, _colComp);
    }

    function test_revertsWhen_addCollateralstrategyAllocationPerExceeded(
        uint16 _baseFeeIn,
        uint16 _baseFeeOut,
        uint16 _downsidePeg,
        uint16 _colComp,
        uint16 _colComp2
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseFeeIn <= manager.PERC_PRECISION());
        vm.assume(_baseFeeOut <= manager.PERC_PRECISION());
        vm.assume(_downsidePeg <= manager.PERC_PRECISION());
        vm.assume(_colComp <= manager.PERC_PRECISION());
        vm.assume(_colComp2 > manager.PERC_PRECISION());

        collateralSetUp(USDCe, _colComp, _baseFeeIn, _baseFeeOut, _downsidePeg);
        vm.expectRevert("AllocationPer exceeded");
        manager.addCollateralStrategy(USDCe, stargate, _colComp2);
    }

    function test_addCollateralStrategy(
        uint16 _baseFeeIn,
        uint16 _baseFeeOut,
        uint16 _downsidePeg,
        uint16 _colComp
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseFeeIn <= manager.PERC_PRECISION());
        vm.assume(_baseFeeOut <= manager.PERC_PRECISION());
        vm.assume(_downsidePeg <= manager.PERC_PRECISION());
        vm.assume(_colComp <= manager.PERC_PRECISION());

        collateralSetUp(USDCe, _colComp, _baseFeeIn, _baseFeeOut, _downsidePeg);

        vm.expectEmit(true, true, false, true);
        emit CollateralStrategyAdded(USDCe, stargate);

        manager.addCollateralStrategy(USDCe, stargate, _colComp);
    }
}

contract CollateralManager_updateCollateralStrategy_Test is
    CollateralManagerTest
{
    function test_revertsWhen_updateCollateralstrategyWhenNotMapped(
        uint16 _baseFeeIn,
        uint16 _baseFeeOut,
        uint16 _downsidePeg,
        uint16 _colComp
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseFeeIn <= manager.PERC_PRECISION());
        vm.assume(_baseFeeOut <= manager.PERC_PRECISION());
        vm.assume(_downsidePeg <= manager.PERC_PRECISION());
        vm.assume(_colComp <= manager.PERC_PRECISION());

        collateralSetUp(USDCe, _colComp, _baseFeeIn, _baseFeeOut, _downsidePeg);
        vm.expectRevert("Strategy not mapped");
        manager.updateCollateralStrategy(USDCe, stargate, 2000);
    }

    function test_revertsWhen_updateCollateralstrategyAllocationPerExceeded(
        uint16 _baseFeeIn,
        uint16 _baseFeeOut,
        uint16 _downsidePeg,
        uint16 _colComp
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseFeeIn <= manager.PERC_PRECISION());
        vm.assume(_baseFeeOut <= manager.PERC_PRECISION());
        vm.assume(_downsidePeg <= manager.PERC_PRECISION());
        vm.assume(_colComp <= manager.PERC_PRECISION());

        collateralSetUp(USDCe, _colComp, _baseFeeIn, _baseFeeOut, _downsidePeg);
        manager.addCollateralStrategy(USDCe, stargate, 2000);
        vm.expectRevert("AllocationPer exceeded");
        manager.updateCollateralStrategy(USDCe, stargate, 10001);
    }

    function test_revertsWhen_updateCollateralstrategyAllocationNotValid(
        uint16 _baseFeeIn,
        uint16 _baseFeeOut,
        uint16 _downsidePeg,
        uint16 _colComp
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseFeeIn <= manager.PERC_PRECISION());
        vm.assume(_baseFeeOut <= manager.PERC_PRECISION());
        vm.assume(_downsidePeg <= manager.PERC_PRECISION());
        vm.assume(_colComp <= manager.PERC_PRECISION());

        collateralSetUp(USDCe, _colComp, _baseFeeIn, _baseFeeOut, _downsidePeg);
        manager.addCollateralStrategy(USDCe, stargate, 1);
        vm.expectRevert("AllocationPer not valid");
        manager.updateCollateralStrategy(USDCe, stargate, 10000);
    }

    function test_updateCollateralStrategy(
        uint16 _baseFeeIn,
        uint16 _baseFeeOut,
        uint16 _downsidePeg,
        uint16 _colComp
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseFeeIn <= manager.PERC_PRECISION());
        vm.assume(_baseFeeOut <= manager.PERC_PRECISION());
        vm.assume(_downsidePeg <= manager.PERC_PRECISION());
        vm.assume(_colComp <= manager.PERC_PRECISION());

        collateralSetUp(USDCe, _colComp, _baseFeeIn, _baseFeeOut, _downsidePeg);
        manager.addCollateralStrategy(USDCe, stargate, _colComp);

        vm.expectEmit(true, true, false, true);
        emit CollateralStrategyUpdated(USDCe, stargate);

        manager.updateCollateralStrategy(USDCe, stargate, 3500);
    }
}

contract CollateralManager_removeCollateralStrategy_Test is
    CollateralManagerTest
{
    function test_revertsWhen_strategyNotMapped(
        uint16 _baseFeeIn,
        uint16 _baseFeeOut,
        uint16 _downsidePeg,
        uint16 _colComp
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseFeeIn <= manager.PERC_PRECISION());
        vm.assume(_baseFeeOut <= manager.PERC_PRECISION());
        vm.assume(_downsidePeg <= manager.PERC_PRECISION());
        vm.assume(_colComp <= manager.PERC_PRECISION());

        collateralSetUp(USDCe, _colComp, _baseFeeIn, _baseFeeOut, _downsidePeg);
        vm.expectRevert("Strategy not mapped");
        manager.removeCollateralStrategy(USDCe, stargate);
    }

    function test_removeCollateralStrategy(
        uint16 _baseFeeIn,
        uint16 _baseFeeOut,
        uint16 _downsidePeg,
        uint16 _colComp
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseFeeIn <= manager.PERC_PRECISION());
        vm.assume(_baseFeeOut <= manager.PERC_PRECISION());
        vm.assume(_downsidePeg <= manager.PERC_PRECISION());
        vm.assume(_colComp <= manager.PERC_PRECISION() / 2);

        collateralSetUp(USDCe, _colComp, _baseFeeIn, _baseFeeOut, _downsidePeg);
        collateralSetUp(DAI, _colComp, _baseFeeIn, _baseFeeOut, _downsidePeg);
        manager.addCollateralStrategy(USDCe, stargate, 2000);
        manager.addCollateralStrategy(USDCe, AAVE, 2000);

        vm.expectEmit(true, true, false, true);
        emit CollateralStrategyRemoved(USDCe, AAVE);
        manager.removeCollateralStrategy(USDCe, AAVE);
    }

    function test_revertsWhen_strategyInUse(
        uint16 _baseFeeIn,
        uint16 _baseFeeOut,
        uint16 _downsidePeg,
        uint16 _colComp
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseFeeIn <= manager.PERC_PRECISION());
        vm.assume(_baseFeeOut <= manager.PERC_PRECISION());
        vm.assume(_downsidePeg <= manager.PERC_PRECISION());
        vm.assume(_colComp <= manager.PERC_PRECISION());

        collateralSetUp(USDCe, _colComp, _baseFeeIn, _baseFeeOut, _downsidePeg);
        manager.addCollateralStrategy(USDCe, stargate, 2000);
        vm.expectRevert("Strategy in use");
        manager.removeCollateralStrategy(USDCe, stargate);
    }

    function test_revertsWhen_DefaultStrategy(
        uint16 _baseFeeIn,
        uint16 _baseFeeOut,
        uint16 _downsidePeg,
        uint16 _colComp
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseFeeIn <= manager.PERC_PRECISION());
        vm.assume(_baseFeeOut <= manager.PERC_PRECISION());
        vm.assume(_downsidePeg <= manager.PERC_PRECISION());
        vm.assume(_colComp <= manager.PERC_PRECISION());

        collateralSetUp(USDCe, _colComp, _baseFeeIn, _baseFeeOut, _downsidePeg);
        manager.addCollateralStrategy(USDCe, stargate, 2000);
        manager.updateCollateralDefaultStrategy(USDCe, stargate);
        vm.expectRevert("DS removal not allowed");
        manager.removeCollateralStrategy(USDCe, stargate);
    }

    function test_revertsWhen_DefaultStrategyNotExist(
        uint16 _baseFeeIn,
        uint16 _baseFeeOut,
        uint16 _downsidePeg,
        uint16 _colComp
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseFeeIn <= manager.PERC_PRECISION());
        vm.assume(_baseFeeOut <= manager.PERC_PRECISION());
        vm.assume(_downsidePeg <= manager.PERC_PRECISION());
        vm.assume(_colComp <= manager.PERC_PRECISION() / 2);

        collateralSetUp(USDCe, _colComp, _baseFeeIn, _baseFeeOut, _downsidePeg);
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
        uint16 _colComp
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseFeeIn <= manager.PERC_PRECISION());
        vm.assume(_baseFeeOut <= manager.PERC_PRECISION());
        vm.assume(_downsidePeg <= manager.PERC_PRECISION());
        vm.assume(_colComp <= manager.PERC_PRECISION());

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
        uint16 _colComp
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseFeeIn <= manager.PERC_PRECISION());
        vm.assume(_baseFeeOut <= manager.PERC_PRECISION());
        vm.assume(_downsidePeg <= manager.PERC_PRECISION());
        vm.assume(_colComp <= manager.PERC_PRECISION());

        collateralSetUp(USDCe, _colComp, _baseFeeIn, _baseFeeOut, _downsidePeg);
        manager.addCollateralStrategy(USDCe, stargate, 2000);
        manager.validateAllocation(USDCe, stargate, 1000);
    }

    function test_validateAllocationMaxCollateralUsageSup(
        uint16 _baseFeeIn,
        uint16 _baseFeeOut,
        uint16 _downsidePeg,
        uint16 _colComp
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseFeeIn <= manager.PERC_PRECISION());
        vm.assume(_baseFeeOut <= manager.PERC_PRECISION());
        vm.assume(_downsidePeg <= manager.PERC_PRECISION());
        vm.assume(_colComp <= manager.PERC_PRECISION());

        collateralSetUp(USDCe, _colComp, _baseFeeIn, _baseFeeOut, _downsidePeg);
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

        address[] memory collateralsList = manager.getAllCollaterals();

        for (uint8 i = 0; i < collateralsList.length; i++) {
            assertEq(collateralsList[0], USDCe);
            assertEq(collateralsList[1], USDT);
            assertEq(collateralsList[2], VST);
            assertEq(collateralsList[3], FRAX);
            assertEq(collateralsList[4], DAI);
        }
    }

    function test_getZeroCollaterals() external useKnownActor(USDS_OWNER) {
        address[] memory collateralsList = manager.getAllCollaterals();
        assertEq(collateralsList.length, 0);
    }

    function test_getCollateralStrategies(
        uint16 _baseFeeIn,
        uint16 _baseFeeOut,
        uint16 _downsidePeg,
        uint16 _colComp
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseFeeIn <= manager.PERC_PRECISION());
        vm.assume(_baseFeeOut <= manager.PERC_PRECISION());
        vm.assume(_downsidePeg <= manager.PERC_PRECISION());
        vm.assume(_colComp <= manager.PERC_PRECISION());

        collateralSetUp(USDCe, _colComp, _baseFeeIn, _baseFeeOut, _downsidePeg);
        manager.addCollateralStrategy(USDCe, AAVE, 2000);
        manager.addCollateralStrategy(USDCe, stargate, 2000);
        manager.isValidStrategy(USDCe, AAVE);
        manager.isValidStrategy(USDT, USDCe);

        address[] memory collateralsList = manager.getCollateralStrategies(
            USDCe
        );
        for (uint8 i = 0; i < collateralsList.length; i++) {
            assertEq(collateralsList[0], AAVE);
            assertEq(collateralsList[1], stargate);
        }
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
        manager.addCollateralStrategy(USDCe, stargate, 2000);
        manager.addCollateralStrategy(USDCe, AAVE, 2000);
        ICollateralManager.CollateralMintData memory mintData = manager
            .getMintParams(USDCe);
        assertEq(mintData.mintAllowed, _data.mintAllowed);
        assertEq(mintData.baseFeeIn, _data.baseFeeIn);
        assertEq(mintData.downsidePeg, _data.downsidePeg);
        assertEq(
            mintData.desiredCollateralComposition,
            _data.desiredCollateralComposition
        );
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
        manager.updateCollateralDefaultStrategy(USDCe, stargate);

        ICollateralManager.CollateralRedeemData memory redeemData = manager
            .getRedeemParams(USDCe);
        assertEq(redeemData.redeemAllowed, _data.redeemAllowed);
        assertEq(redeemData.baseFeeOut, _data.baseFeeOut);
        assertEq(redeemData.defaultStrategy, stargate);
        assertEq(
            redeemData.desiredCollateralComposition,
            _data.desiredCollateralComposition
        );
    }

    function test_revertsWhen_getRedeemParams_collateralDoesntExist()
        external
        useKnownActor(USDS_OWNER)
    {
        vm.expectRevert("Collateral doesn't exist");
        manager.getRedeemParams(USDT);
    }
}
