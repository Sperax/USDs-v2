// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {BaseTest} from "../utils/BaseTest.sol";
import {CollateralManager} from "../../contracts/vault/CollateralManager.sol";
import {ICollateralManager} from "../../contracts/vault/interfaces/ICollateralManager.sol";
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
        vm.expectRevert("Collateral Composition exceeded");
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
        assertEq(manager.collateralCompositionUsed(), _colComp);

        (
            ,
            ,
            ,
            bool exists,
            address defaultStrategy,
            ,
            ,
            ,
            ,
            uint16 collateralCapacityUsed,
            uint256 conversionFactor
        ) = manager.collateralInfo(USDCe);

        assertEq(exists, true);
        assertEq(defaultStrategy, address(0));
        assertEq(collateralCapacityUsed, 0);
        assertEq(conversionFactor, 10 ** 12); //USDC has 6 Decimals (18-6)=12
    }

    function test_addMultipleCollaterals(
        uint16 _baseFeeIn,
        uint16 _baseFeeOut,
        uint16 _downsidePeg,
        uint16 _colComp
    ) external useKnownActor(USDS_OWNER) {
        address[5] memory collaterals = [USDCe, USDT, VST, FRAX, DAI];
        vm.assume(_baseFeeIn <= manager.PERC_PRECISION());
        vm.assume(_baseFeeOut <= manager.PERC_PRECISION());
        vm.assume(_downsidePeg <= manager.PERC_PRECISION());
        vm.assume(_colComp <= manager.PERC_PRECISION() / collaterals.length);
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

        assertEq(manager.collateralCompositionUsed(), 0);

        for (uint8 i = 0; i < collaterals.length; i++) {
            vm.expectEmit(true, true, false, true);
            emit CollateralAdded(collaterals[i], _data);
            manager.addCollateral(collaterals[i], _data);

            assertEq(manager.collateralCompositionUsed(), _colComp * (i + 1));
        }
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
        vm.expectRevert("Collateral Composition exceeded");

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
        uint16 _colComp,
        uint16 _colComp2
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseFeeIn <= manager.PERC_PRECISION());
        vm.assume(_baseFeeOut <= manager.PERC_PRECISION());
        vm.assume(_downsidePeg <= manager.PERC_PRECISION());
        vm.assume(_colComp <= manager.PERC_PRECISION());
        vm.assume(_colComp2 <= manager.PERC_PRECISION());

        assertEq(manager.collateralCompositionUsed(), 0);
        collateralSetUp(USDCe, _colComp, _baseFeeIn, _baseFeeOut, _downsidePeg);
        assertEq(manager.collateralCompositionUsed(), _colComp);

        uint16 compBeforeUpdate = manager.collateralCompositionUsed();

        ICollateralManager.CollateralBaseData
            memory _dataUpdated = ICollateralManager.CollateralBaseData({
                mintAllowed: true,
                redeemAllowed: true,
                allocationAllowed: true,
                baseFeeIn: _baseFeeIn,
                baseFeeOut: _baseFeeOut,
                downsidePeg: _downsidePeg,
                desiredCollateralComposition: _colComp2
            });
        uint16 compAfterUpdate = compBeforeUpdate - _colComp + _colComp2;
        vm.expectEmit(true, true, false, true);
        emit CollateralInfoUpdated(USDCe, _dataUpdated);

        manager.updateCollateralData(USDCe, _dataUpdated);

        assertEq(manager.collateralCompositionUsed(), compAfterUpdate);
    }

    function test_updateMultipleCollaterals(
        uint16 _baseFeeIn,
        uint16 _baseFeeOut,
        uint16 _downsidePeg,
        uint16 _colComp,
        uint16 _colComp2
    ) external useKnownActor(USDS_OWNER) {
        address[5] memory collaterals = [USDCe, USDT, VST, FRAX, DAI];
        vm.assume(_baseFeeIn <= manager.PERC_PRECISION());
        vm.assume(_baseFeeOut <= manager.PERC_PRECISION());
        vm.assume(_downsidePeg <= manager.PERC_PRECISION());
        vm.assume(_colComp <= manager.PERC_PRECISION() / collaterals.length);
        vm.assume(_colComp2 <= manager.PERC_PRECISION() / collaterals.length);

        assertEq(manager.collateralCompositionUsed(), 0);

        for (uint8 i = 0; i < collaterals.length; i++) {
            collateralSetUp(
                collaterals[i],
                _colComp,
                _baseFeeIn,
                _baseFeeOut,
                _downsidePeg
            );
            assertEq(manager.collateralCompositionUsed(), _colComp * (i + 1));
        }

        ICollateralManager.CollateralBaseData
            memory _dataUpdated = ICollateralManager.CollateralBaseData({
                mintAllowed: true,
                redeemAllowed: true,
                allocationAllowed: true,
                baseFeeIn: _baseFeeIn,
                baseFeeOut: _baseFeeOut,
                downsidePeg: _downsidePeg,
                desiredCollateralComposition: _colComp2
            });

        for (uint8 i = 0; i < collaterals.length; i++) {
            uint16 compBeforeUpdate = manager.collateralCompositionUsed();

            vm.expectEmit(true, true, false, true);
            emit CollateralInfoUpdated(collaterals[i], _dataUpdated);

            manager.updateCollateralData(collaterals[i], _dataUpdated);
            uint16 compAfterUpdate = compBeforeUpdate - _colComp + _colComp2;
            assertEq(manager.collateralCompositionUsed(), compAfterUpdate);
        }
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
        address[5] memory collaterals = [USDCe, USDT, VST, FRAX, DAI];
        vm.assume(_baseFeeIn <= manager.PERC_PRECISION());
        vm.assume(_baseFeeOut <= manager.PERC_PRECISION());
        vm.assume(_downsidePeg <= manager.PERC_PRECISION());
        uint16 colComp = 1000;

        //increasing Removal
        for (uint8 i = 0; i < collaterals.length; i++) {
            collateralSetUp(
                collaterals[i],
                colComp + (500 * i),
                _baseFeeIn,
                _baseFeeOut,
                _downsidePeg
            );
        }
        for (uint8 i = 0; i < collaterals.length; i++) {
            uint16 compBfr = manager.collateralCompositionUsed();
            (, , , , , , , , uint16 desiredCollateralComposition, , ) = manager
                .collateralInfo(collaterals[i]);

            vm.expectEmit(true, true, false, true);
            emit CollateralRemoved(collaterals[i]);
            manager.removeCollateral(collaterals[i]);

            assertEq(
                manager.collateralCompositionUsed(),
                compBfr - desiredCollateralComposition
            );
        }
        //Decreasing Removal
        for (uint8 i = 0; i < collaterals.length; i++) {
            collateralSetUp(
                collaterals[i],
                colComp + (500 * i),
                _baseFeeIn,
                _baseFeeOut,
                _downsidePeg
            );
        }
        for (uint256 i = collaterals.length; i < 1; i--) {
            uint16 compBfr = manager.collateralCompositionUsed();
            (, , , , , , , , uint16 desiredCollateralComposition, , ) = manager
                .collateralInfo(collaterals[i]);
            vm.expectEmit(true, true, false, true);
            emit CollateralRemoved(collaterals[i]);
            manager.removeCollateral(collaterals[i]);

            assertEq(
                manager.collateralCompositionUsed(),
                compBfr - desiredCollateralComposition
            );
        }
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
        manager.addCollateralStrategy(USDCe, STARGATE, _colComp);
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
        manager.addCollateralStrategy(USDCe, STARGATE, 1000);
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
        manager.addCollateralStrategy(USDCe, STARGATE, _colComp);
        vm.expectRevert("Strategy already mapped");
        manager.addCollateralStrategy(USDCe, STARGATE, _colComp);
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
        manager.addCollateralStrategy(USDT, STARGATE, _colComp);
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
        manager.addCollateralStrategy(USDCe, STARGATE, _colComp2);
    }

    function test_addCollateralStrategy(
        uint16 _baseFeeIn,
        uint16 _baseFeeOut,
        uint16 _downsidePeg,
        uint16 _colComp,
        uint16 _allocCap
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseFeeIn <= manager.PERC_PRECISION());
        vm.assume(_baseFeeOut <= manager.PERC_PRECISION());
        vm.assume(_downsidePeg <= manager.PERC_PRECISION());
        vm.assume(_colComp <= manager.PERC_PRECISION());
        vm.assume(_allocCap <= manager.PERC_PRECISION());

        collateralSetUp(USDCe, _colComp, _baseFeeIn, _baseFeeOut, _downsidePeg);

        vm.expectEmit(true, true, false, true);
        emit CollateralStrategyAdded(USDCe, STARGATE);

        manager.addCollateralStrategy(USDCe, STARGATE, _allocCap);
    }

    function test_addMultipleCollateralStrategies(
        uint16 _baseFeeIn,
        uint16 _baseFeeOut,
        uint16 _downsidePeg,
        uint16 _colComp,
        uint16 _allocCap
    ) external useKnownActor(USDS_OWNER) {
        address[2] memory strategies = [AAVE, STARGATE];
        vm.assume(_baseFeeIn <= manager.PERC_PRECISION());
        vm.assume(_baseFeeOut <= manager.PERC_PRECISION());
        vm.assume(_downsidePeg <= manager.PERC_PRECISION());
        vm.assume(_colComp <= manager.PERC_PRECISION());
        vm.assume(_allocCap <= manager.PERC_PRECISION() / strategies.length);

        collateralSetUp(USDCe, _colComp, _baseFeeIn, _baseFeeOut, _downsidePeg);
        (, , , , , , , , , uint16 collateralCapacityUsedBfr, ) = manager
            .collateralInfo(USDCe);
        assertEq(collateralCapacityUsedBfr, 0);

        for (uint8 i = 0; i < strategies.length; i++) {
            vm.expectEmit(true, true, false, true);
            emit CollateralStrategyAdded(USDCe, strategies[i]);

            manager.addCollateralStrategy(USDCe, strategies[i], _allocCap);
            (, , , , , , , , , uint16 collateralCapacityUsed, ) = manager
                .collateralInfo(USDCe);
            assertEq(collateralCapacityUsed, _allocCap * (i + 1));
        }
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
        manager.updateCollateralStrategy(USDCe, STARGATE, 2000);
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
        manager.addCollateralStrategy(USDCe, STARGATE, 2000);
        vm.expectRevert("AllocationPer exceeded");
        manager.updateCollateralStrategy(USDCe, STARGATE, 10001);
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
        manager.addCollateralStrategy(USDCe, STARGATE, 1);
        vm.expectRevert("AllocationPer not valid");
        manager.updateCollateralStrategy(USDCe, STARGATE, 10000);
    }

    function test_updateCollateralStrategy(
        uint16 _baseFeeIn,
        uint16 _baseFeeOut,
        uint16 _downsidePeg,
        uint16 _colComp,
        uint16 _allocCap
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseFeeIn <= manager.PERC_PRECISION());
        vm.assume(_baseFeeOut <= manager.PERC_PRECISION());
        vm.assume(_downsidePeg <= manager.PERC_PRECISION());
        vm.assume(_colComp <= manager.PERC_PRECISION());
        vm.assume(_allocCap <= manager.PERC_PRECISION());

        collateralSetUp(USDCe, _colComp, _baseFeeIn, _baseFeeOut, _downsidePeg);
        manager.addCollateralStrategy(USDCe, STARGATE, _colComp);

        vm.expectEmit(true, true, false, true);
        emit CollateralStrategyUpdated(USDCe, STARGATE);

        manager.updateCollateralStrategy(USDCe, STARGATE, _allocCap);
    }

    function test_updateMultipleCollateralStrategies(
        uint16 _baseFeeIn,
        uint16 _baseFeeOut,
        uint16 _downsidePeg,
        uint16 _colComp
    ) external useKnownActor(USDS_OWNER) {
        address[2] memory strategies = [AAVE, STARGATE];
        vm.assume(_baseFeeIn <= manager.PERC_PRECISION());
        vm.assume(_baseFeeOut <= manager.PERC_PRECISION());
        vm.assume(_downsidePeg <= manager.PERC_PRECISION());
        vm.assume(_colComp <= manager.PERC_PRECISION());

        collateralSetUp(USDCe, _colComp, _baseFeeIn, _baseFeeOut, _downsidePeg);
        (, , , , , , , , , uint16 collateralCapacityUsedBfr, ) = manager
            .collateralInfo(USDCe);
        assertEq(collateralCapacityUsedBfr, 0);

        for (uint8 i = 0; i < strategies.length; i++) {
            vm.expectEmit(true, true, false, true);
            emit CollateralStrategyAdded(USDCe, strategies[i]);

            manager.addCollateralStrategy(USDCe, strategies[i], 3500);
            (, , , , , , , , , uint16 collateralCapacityUsed, ) = manager
                .collateralInfo(USDCe);
            assertEq(collateralCapacityUsed, 3500 * (i + 1));
        }

        // for (uint8 i = 0; i < strategies.length; i++) {
        //     (, , , , , , , , , uint16 collateralCapacityUsedBfrUp, ) = manager
        //         .collateralInfo(USDCe);
        //     // vm.expectEmit(true, true, false, true);
        //     // emit CollateralStrategyUpdated(USDCe, strategies[i]);

        //     manager.updateCollateralStrategy(USDCe, strategies[i], 4500);

        //     uint16 alocAfter = collateralCapacityUsedBfrUp -
        //         3500 +
        //         4500;
        //     (, , , , , , , , , uint16 collateralCapacityUsedAftrUp, ) = manager
        //         .collateralInfo(USDCe);
        //     assertEq(collateralCapacityUsedAftrUp, alocAfter);
        // }
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
        manager.removeCollateralStrategy(USDCe, STARGATE);
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
        manager.addCollateralStrategy(USDCe, STARGATE, 2000);
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
        manager.addCollateralStrategy(USDCe, STARGATE, 2000);
        vm.expectRevert("Strategy in use");
        manager.removeCollateralStrategy(USDCe, STARGATE);
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
        manager.addCollateralStrategy(USDCe, STARGATE, 2000);
        manager.updateCollateralDefaultStrategy(USDCe, STARGATE);
        vm.expectRevert("DS removal not allowed");
        manager.removeCollateralStrategy(USDCe, STARGATE);
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
        manager.addCollateralStrategy(USDCe, STARGATE, 2000);
        vm.expectRevert("Collateral doesn't exist");
        manager.updateCollateralDefaultStrategy(VST, STARGATE);
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
        manager.addCollateralStrategy(USDT, USDT_TWO_POOL_STRATEGY, 2000);
        vm.expectRevert("Allocation not allowed");
        manager.validateAllocation(USDT, USDT_TWO_POOL_STRATEGY, 1);
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
        manager.addCollateralStrategy(USDCe, STARGATE, 2000);
        manager.validateAllocation(USDCe, STARGATE, 1000);
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
        manager.addCollateralStrategy(USDCe, STARGATE, 10000);
        manager.validateAllocation(USDCe, STARGATE, 11000000000);
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
        address[5] memory collaterals = [USDCe, USDT, VST, FRAX, DAI];

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
        for (uint8 i = 0; i < collaterals.length; i++) {
            manager.addCollateral(collaterals[i], _data);
        }

        manager.addCollateralStrategy(USDCe, AAVE, 2000);

        address[] memory collateralsList = manager.getAllCollaterals();

        for (uint8 i = 0; i < collateralsList.length; i++) {
            assertEq(collateralsList[i], collaterals[i]);
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
        address[2] memory strategies = [AAVE, STARGATE];

        collateralSetUp(USDCe, _colComp, _baseFeeIn, _baseFeeOut, _downsidePeg);
        for (uint8 i = 0; i < strategies.length; i++) {
            manager.addCollateralStrategy(USDCe, strategies[i], 2000);
        }
        manager.isValidStrategy(USDCe, AAVE);
        manager.isValidStrategy(USDT, USDCe);

        address[] memory collateralStrategiesList = manager
            .getCollateralStrategies(USDCe);
        for (uint8 i = 0; i < collateralStrategiesList.length; i++) {
            assertEq(collateralStrategiesList[i], strategies[i]);
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
        manager.addCollateralStrategy(USDCe, STARGATE, 2000);
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
        manager.addCollateralStrategy(USDCe, STARGATE, 2000);
        manager.addCollateralStrategy(USDCe, AAVE, 2000);
        manager.updateCollateralDefaultStrategy(USDCe, STARGATE);

        ICollateralManager.CollateralRedeemData memory redeemData = manager
            .getRedeemParams(USDCe);
        assertEq(redeemData.redeemAllowed, _data.redeemAllowed);
        assertEq(redeemData.baseFeeOut, _data.baseFeeOut);
        assertEq(redeemData.defaultStrategy, STARGATE);
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
