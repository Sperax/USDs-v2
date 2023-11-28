// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {PreMigrationSetup} from "../utils/DeploymentSetup.sol";
import {CollateralManager, Helpers} from "../../contracts/vault/CollateralManager.sol";
import {ICollateralManager} from "../../contracts/vault/interfaces/ICollateralManager.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract CollateralManagerTest is PreMigrationSetup {
    //  Init Variables.
    CollateralManager public manager;

    // Events from the actual contract.
    event CollateralAdded(address collateral, ICollateralManager.CollateralBaseData data);
    event CollateralRemoved(address collateral);
    event CollateralInfoUpdated(address collateral, ICollateralManager.CollateralBaseData data);
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
        uint16 _baseMintFee,
        uint16 _baseRedeemFee,
        uint16 _downsidePeg
    ) public {
        ICollateralManager.CollateralBaseData memory _data = ICollateralManager.CollateralBaseData({
            mintAllowed: true,
            redeemAllowed: true,
            allocationAllowed: true,
            baseMintFee: _baseMintFee,
            baseRedeemFee: _baseRedeemFee,
            downsidePeg: _downsidePeg,
            desiredCollateralComposition: desiredCollateralComposition
        });

        manager.addCollateral(_collateralAsset, _data);
    }

    function collateralUpdate(
        address _collateralAsset,
        uint16 desiredCollateralComposition,
        uint16 _baseMintFee,
        uint16 _baseRedeemFee,
        uint16 _downsidePeg
    ) public {
        ICollateralManager.CollateralBaseData memory _data = ICollateralManager.CollateralBaseData({
            mintAllowed: true,
            redeemAllowed: true,
            allocationAllowed: true,
            baseMintFee: _baseMintFee,
            baseRedeemFee: _baseRedeemFee,
            downsidePeg: _downsidePeg,
            desiredCollateralComposition: desiredCollateralComposition
        });

        manager.updateCollateralData(_collateralAsset, _data);
    }
}

contract Constructor is CollateralManagerTest {
    function test_RevertWhen_InvalidAddress() external {
        vm.expectRevert(abi.encodeWithSelector(Helpers.InvalidAddress.selector));
        new CollateralManager(address(0));
    }

    function test_constructor() external {
        assertEq(manager.VAULT(), VAULT);
        assertEq(manager.owner(), USDS_OWNER); // owner is USDS_OWNER
    }
}

contract CollateralManager_AddCollateral_Test is CollateralManagerTest {
    function test_revertsWhen_downsidePegExceedsMax(
        uint16 _baseMintFee,
        uint16 _baseRedeemFee,
        uint16 _downsidePeg,
        uint16 _colComp
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseMintFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_baseRedeemFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_downsidePeg > Helpers.MAX_PERCENTAGE);

        vm.expectRevert(abi.encodeWithSelector(Helpers.GTMaxPercentage.selector, _downsidePeg));
        collateralSetUp(USDCe, _colComp, _baseMintFee, _baseRedeemFee, _downsidePeg);
    }

    function test_revertsWhen_baseMintFeeExceedsMax(
        uint16 _baseMintFee,
        uint16 _baseRedeemFee,
        uint16 _downsidePeg,
        uint16 _colComp
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseMintFee > Helpers.MAX_PERCENTAGE);
        vm.assume(_baseRedeemFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_downsidePeg <= Helpers.MAX_PERCENTAGE);

        vm.expectRevert(abi.encodeWithSelector(Helpers.GTMaxPercentage.selector, _baseMintFee));
        collateralSetUp(USDCe, _colComp, _baseMintFee, _baseRedeemFee, _downsidePeg);
    }

    function test_revertsWhen_baseRedeemFeeExceedsMax(
        uint16 _baseMintFee,
        uint16 _baseRedeemFee,
        uint16 _downsidePeg,
        uint16 _colComp
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseMintFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_baseRedeemFee > Helpers.MAX_PERCENTAGE);
        vm.assume(_downsidePeg <= Helpers.MAX_PERCENTAGE);

        vm.expectRevert(abi.encodeWithSelector(Helpers.GTMaxPercentage.selector, _baseRedeemFee));
        collateralSetUp(USDCe, _colComp, _baseMintFee, _baseRedeemFee, _downsidePeg);
    }

    function test_revertsWhen_addSameCollateral(
        uint16 _baseMintFee,
        uint16 _baseRedeemFee,
        uint16 _downsidePeg,
        uint16 _colComp
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_colComp <= Helpers.MAX_PERCENTAGE);
        vm.assume(_baseMintFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_baseRedeemFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_downsidePeg <= Helpers.MAX_PERCENTAGE);

        collateralSetUp(USDCe, _colComp, _baseMintFee, _baseRedeemFee, _downsidePeg);
        vm.expectRevert(abi.encodeWithSelector(CollateralManager.CollateralExists.selector));
        collateralSetUp(USDCe, _colComp, _baseMintFee, _baseRedeemFee, _downsidePeg);
    }

    function test_revertsWhen_collateralCompositionExceeded(
        uint16 _baseMintFee,
        uint16 _baseRedeemFee,
        uint16 _downsidePeg
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseMintFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_baseRedeemFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_downsidePeg <= Helpers.MAX_PERCENTAGE);

        collateralSetUp(USDCe, 9000, _baseMintFee, _baseRedeemFee, _downsidePeg);
        vm.expectRevert(abi.encodeWithSelector(Helpers.CustomError.selector, "Collateral composition exceeded"));
        collateralSetUp(USDT, 1001, _baseMintFee, _baseRedeemFee, _downsidePeg);
    }

    function test_addCollateral(uint16 _baseMintFee, uint16 _baseRedeemFee, uint16 _downsidePeg, uint16 _colComp)
        external
        useKnownActor(USDS_OWNER)
    {
        vm.assume(_baseMintFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_baseRedeemFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_downsidePeg <= Helpers.MAX_PERCENTAGE);
        vm.assume(_colComp <= Helpers.MAX_PERCENTAGE);
        ICollateralManager.CollateralBaseData memory _data = ICollateralManager.CollateralBaseData({
            mintAllowed: true,
            redeemAllowed: true,
            allocationAllowed: true,
            baseMintFee: _baseMintFee,
            baseRedeemFee: _baseRedeemFee,
            downsidePeg: _downsidePeg,
            desiredCollateralComposition: _colComp
        });

        vm.expectEmit(true, true, false, true);
        emit CollateralAdded(USDCe, _data);

        manager.addCollateral(USDCe, _data);
        assertEq(manager.collateralCompositionUsed(), _colComp);

        (,,, bool exists, address defaultStrategy,,,,, uint16 collateralCapacityUsed, uint256 conversionFactor) =
            manager.collateralInfo(USDCe);

        assertEq(exists, true);
        assertEq(defaultStrategy, address(0));
        assertEq(collateralCapacityUsed, 0);
        assertEq(conversionFactor, 10 ** 12); //USDC has 6 Decimals (18-6)=12
    }

    function test_addMultipleCollaterals(
        uint16 _baseMintFee,
        uint16 _baseRedeemFee,
        uint16 _downsidePeg,
        uint16 _colComp
    ) external useKnownActor(USDS_OWNER) {
        address[5] memory collaterals = [USDCe, USDT, VST, FRAX, DAI];
        vm.assume(_baseMintFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_baseRedeemFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_downsidePeg <= Helpers.MAX_PERCENTAGE);
        vm.assume(_colComp <= Helpers.MAX_PERCENTAGE / collaterals.length);
        ICollateralManager.CollateralBaseData memory _data = ICollateralManager.CollateralBaseData({
            mintAllowed: true,
            redeemAllowed: true,
            allocationAllowed: true,
            baseMintFee: _baseMintFee,
            baseRedeemFee: _baseRedeemFee,
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
        uint16 _baseMintFee,
        uint16 _baseRedeemFee,
        uint16 _downsidePeg,
        uint16 _colComp
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseMintFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_baseRedeemFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_downsidePeg <= Helpers.MAX_PERCENTAGE);
        vm.assume(_colComp <= Helpers.MAX_PERCENTAGE);

        vm.expectRevert(abi.encodeWithSelector(CollateralManager.CollateralDoesNotExist.selector));
        collateralUpdate(USDT, _colComp, _baseMintFee, _baseRedeemFee, _downsidePeg);
    }

    function test_revertsWhen_collateralCompositionExceeded(
        uint16 _baseMintFee,
        uint16 _baseRedeemFee,
        uint16 _downsidePeg,
        uint16 _colComp,
        uint16 _colComp2
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseMintFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_baseRedeemFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_downsidePeg <= Helpers.MAX_PERCENTAGE);
        vm.assume(_colComp <= Helpers.MAX_PERCENTAGE);
        vm.assume(_colComp2 > Helpers.MAX_PERCENTAGE);

        collateralSetUp(USDT, _colComp, _baseMintFee, _baseRedeemFee, _downsidePeg);
        vm.expectRevert(abi.encodeWithSelector(Helpers.CustomError.selector, "Collateral composition exceeded"));
        collateralUpdate(USDT, _colComp2, _baseMintFee, _baseRedeemFee, _downsidePeg);
    }

    function test_updateCollateral(
        uint16 _baseMintFee,
        uint16 _baseRedeemFee,
        uint16 _downsidePeg,
        uint16 _colComp,
        uint16 _colComp2
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseMintFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_baseRedeemFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_downsidePeg <= Helpers.MAX_PERCENTAGE);
        vm.assume(_colComp <= Helpers.MAX_PERCENTAGE);
        vm.assume(_colComp2 <= Helpers.MAX_PERCENTAGE);

        assertEq(manager.collateralCompositionUsed(), 0);
        collateralSetUp(USDCe, _colComp, _baseMintFee, _baseRedeemFee, _downsidePeg);
        assertEq(manager.collateralCompositionUsed(), _colComp);

        uint16 compBeforeUpdate = manager.collateralCompositionUsed();

        ICollateralManager.CollateralBaseData memory _dataUpdated = ICollateralManager.CollateralBaseData({
            mintAllowed: true,
            redeemAllowed: true,
            allocationAllowed: true,
            baseMintFee: _baseMintFee,
            baseRedeemFee: _baseRedeemFee,
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
        uint16 _baseMintFee,
        uint16 _baseRedeemFee,
        uint16 _downsidePeg,
        uint16 _colComp,
        uint16 _colComp2
    ) external useKnownActor(USDS_OWNER) {
        address[5] memory collaterals = [USDCe, USDT, VST, FRAX, DAI];
        vm.assume(_baseMintFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_baseRedeemFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_downsidePeg <= Helpers.MAX_PERCENTAGE);
        vm.assume(_colComp <= Helpers.MAX_PERCENTAGE / collaterals.length);
        vm.assume(_colComp2 <= Helpers.MAX_PERCENTAGE / collaterals.length);

        assertEq(manager.collateralCompositionUsed(), 0);

        for (uint8 i = 0; i < collaterals.length; i++) {
            collateralSetUp(collaterals[i], _colComp, _baseMintFee, _baseRedeemFee, _downsidePeg);
            assertEq(manager.collateralCompositionUsed(), _colComp * (i + 1));
        }

        ICollateralManager.CollateralBaseData memory _dataUpdated = ICollateralManager.CollateralBaseData({
            mintAllowed: true,
            redeemAllowed: true,
            allocationAllowed: true,
            baseMintFee: _baseMintFee,
            baseRedeemFee: _baseRedeemFee,
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
    function test_revertsWhen_removeNonExistingCollateral() external useKnownActor(USDS_OWNER) {
        vm.expectRevert(abi.encodeWithSelector(CollateralManager.CollateralDoesNotExist.selector));
        manager.removeCollateral(USDCe);
    }

    function test_removeMultipleCollaterals(uint16 _baseMintFee, uint16 _baseRedeemFee, uint16 _downsidePeg)
        external
        useKnownActor(USDS_OWNER)
    {
        address[5] memory collaterals = [USDCe, USDT, VST, FRAX, DAI];
        vm.assume(_baseMintFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_baseRedeemFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_downsidePeg <= Helpers.MAX_PERCENTAGE);
        uint16 colComp = 1000;

        //increasing Removal
        for (uint8 i = 0; i < collaterals.length; i++) {
            collateralSetUp(collaterals[i], colComp + (500 * i), _baseMintFee, _baseRedeemFee, _downsidePeg);
        }
        for (uint8 i = 0; i < collaterals.length; i++) {
            uint16 compBfr = manager.collateralCompositionUsed();
            (,,,,,,,, uint16 desiredCollateralComposition,,) = manager.collateralInfo(collaterals[i]);

            vm.expectEmit(true, true, false, true);
            emit CollateralRemoved(collaterals[i]);
            manager.removeCollateral(collaterals[i]);

            assertEq(manager.collateralCompositionUsed(), compBfr - desiredCollateralComposition);
        }
        //Decreasing Removal
        for (uint8 i = 0; i < collaterals.length; i++) {
            collateralSetUp(collaterals[i], colComp + (500 * i), _baseMintFee, _baseRedeemFee, _downsidePeg);
        }
        for (uint256 i = collaterals.length; i < 1; i--) {
            uint16 compBfr = manager.collateralCompositionUsed();
            (,,,,,,,, uint16 desiredCollateralComposition,,) = manager.collateralInfo(collaterals[i]);
            vm.expectEmit(true, true, false, true);
            emit CollateralRemoved(collaterals[i]);
            manager.removeCollateral(collaterals[i]);

            assertEq(manager.collateralCompositionUsed(), compBfr - desiredCollateralComposition);
        }
    }

    function test_revertsWhen_removeStrategyCollateralStrategyExists(
        uint16 _baseMintFee,
        uint16 _baseRedeemFee,
        uint16 _downsidePeg,
        uint16 _colComp
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseMintFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_baseRedeemFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_downsidePeg <= Helpers.MAX_PERCENTAGE);
        vm.assume(_colComp <= Helpers.MAX_PERCENTAGE);

        collateralSetUp(USDCe, _colComp, _baseMintFee, _baseRedeemFee, _downsidePeg);
        manager.addCollateralStrategy(USDCe, STARGATE, _colComp);
        vm.expectRevert(abi.encodeWithSelector(CollateralManager.CollateralStrategyExists.selector));
        manager.removeCollateral(USDCe);
    }
}

contract CollateralManager_addCollateralStrategy_Test is CollateralManagerTest {
    function test_revertsWhen_collateralDoesntExist(uint16 _collateralComposition) external useKnownActor(USDS_OWNER) {
        vm.assume(_collateralComposition <= Helpers.MAX_PERCENTAGE);
        vm.expectRevert(abi.encodeWithSelector(CollateralManager.CollateralDoesNotExist.selector));
        manager.addCollateralStrategy(USDCe, STARGATE, 1000);
    }

    function test_revertsWhen_addCollateralstrategyWhenAlreadyMapped(
        uint16 _baseMintFee,
        uint16 _baseRedeemFee,
        uint16 _downsidePeg,
        uint16 _colComp
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseMintFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_baseRedeemFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_downsidePeg <= Helpers.MAX_PERCENTAGE);
        vm.assume(_colComp <= Helpers.MAX_PERCENTAGE);

        collateralSetUp(USDCe, _colComp, _baseMintFee, _baseRedeemFee, _downsidePeg);
        manager.addCollateralStrategy(USDCe, STARGATE, _colComp);
        vm.expectRevert(abi.encodeWithSelector(CollateralManager.CollateralStrategyMapped.selector));
        manager.addCollateralStrategy(USDCe, STARGATE, _colComp);
    }

    function test_revertsWhen_addCollateralstrategyNotSupported(
        uint16 _baseMintFee,
        uint16 _baseRedeemFee,
        uint16 _downsidePeg,
        uint16 _colComp
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseMintFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_baseRedeemFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_downsidePeg <= Helpers.MAX_PERCENTAGE);
        vm.assume(_colComp <= Helpers.MAX_PERCENTAGE);

        collateralSetUp(FRAX, _colComp, _baseMintFee, _baseRedeemFee, _downsidePeg);
        vm.expectRevert(abi.encodeWithSelector(CollateralManager.CollateralNotSupportedByStrategy.selector));
        manager.addCollateralStrategy(FRAX, STARGATE, _colComp);
    }

    function test_revertsWhen_addCollateralstrategyAllocationPerExceeded(
        uint16 _baseMintFee,
        uint16 _baseRedeemFee,
        uint16 _downsidePeg,
        uint16 _colComp,
        uint16 _colComp2
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseMintFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_baseRedeemFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_downsidePeg <= Helpers.MAX_PERCENTAGE);
        vm.assume(_colComp <= Helpers.MAX_PERCENTAGE);
        vm.assume(_colComp2 > Helpers.MAX_PERCENTAGE);

        collateralSetUp(USDCe, _colComp, _baseMintFee, _baseRedeemFee, _downsidePeg);
        vm.expectRevert(abi.encodeWithSelector(Helpers.CustomError.selector, "Allocation percentage exceeded"));
        manager.addCollateralStrategy(USDCe, STARGATE, _colComp2);
    }

    function test_addCollateralStrategy(
        uint16 _baseMintFee,
        uint16 _baseRedeemFee,
        uint16 _downsidePeg,
        uint16 _colComp,
        uint16 _allocCap
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseMintFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_baseRedeemFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_downsidePeg <= Helpers.MAX_PERCENTAGE);
        vm.assume(_colComp <= Helpers.MAX_PERCENTAGE);
        vm.assume(_allocCap <= Helpers.MAX_PERCENTAGE);

        collateralSetUp(USDCe, _colComp, _baseMintFee, _baseRedeemFee, _downsidePeg);

        vm.expectEmit(true, true, false, true);
        emit CollateralStrategyAdded(USDCe, STARGATE);

        manager.addCollateralStrategy(USDCe, STARGATE, _allocCap);
    }

    function test_addMultipleCollateralStrategies(
        uint16 _baseMintFee,
        uint16 _baseRedeemFee,
        uint16 _downsidePeg,
        uint16 _colComp,
        uint16 _allocCap
    ) external useKnownActor(USDS_OWNER) {
        address[2] memory strategies = [AAVE, STARGATE];
        vm.assume(_baseMintFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_baseRedeemFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_downsidePeg <= Helpers.MAX_PERCENTAGE);
        vm.assume(_colComp <= Helpers.MAX_PERCENTAGE);
        vm.assume(_allocCap <= Helpers.MAX_PERCENTAGE / strategies.length);

        collateralSetUp(USDCe, _colComp, _baseMintFee, _baseRedeemFee, _downsidePeg);
        (,,,,,,,,, uint16 collateralCapacityUsedBfr,) = manager.collateralInfo(USDCe);
        assertEq(collateralCapacityUsedBfr, 0);

        for (uint8 i = 0; i < strategies.length; i++) {
            vm.expectEmit(true, true, false, true);
            emit CollateralStrategyAdded(USDCe, strategies[i]);

            manager.addCollateralStrategy(USDCe, strategies[i], _allocCap);
            (,,,,,,,,, uint16 collateralCapacityUsed,) = manager.collateralInfo(USDCe);
            assertEq(collateralCapacityUsed, _allocCap * (i + 1));
        }
    }
}

contract CollateralManager_updateCollateralStrategy_Test is CollateralManagerTest {
    function test_revertsWhen_updateCollateralstrategyWhenNotMapped(
        uint16 _baseMintFee,
        uint16 _baseRedeemFee,
        uint16 _downsidePeg,
        uint16 _colComp
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseMintFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_baseRedeemFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_downsidePeg <= Helpers.MAX_PERCENTAGE);
        vm.assume(_colComp <= Helpers.MAX_PERCENTAGE);

        collateralSetUp(USDCe, _colComp, _baseMintFee, _baseRedeemFee, _downsidePeg);
        vm.expectRevert(abi.encodeWithSelector(CollateralManager.CollateralStrategyNotMapped.selector));
        manager.updateCollateralStrategy(USDCe, STARGATE, 2000);
    }

    function test_revertsWhen_updateCollateralstrategyAllocationPerExceeded(
        uint16 _baseMintFee,
        uint16 _baseRedeemFee,
        uint16 _downsidePeg,
        uint16 _colComp
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseMintFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_baseRedeemFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_downsidePeg <= Helpers.MAX_PERCENTAGE);
        vm.assume(_colComp <= Helpers.MAX_PERCENTAGE);

        collateralSetUp(USDCe, _colComp, _baseMintFee, _baseRedeemFee, _downsidePeg);
        manager.addCollateralStrategy(USDCe, STARGATE, 2000);
        vm.expectRevert(abi.encodeWithSelector(Helpers.CustomError.selector, "Allocation percentage exceeded"));
        manager.updateCollateralStrategy(USDCe, STARGATE, 10001);
    }

    function test_revertsWhen_updateCollateralstrategyAllocationNotValid(
        uint16 _baseMintFee,
        uint16 _baseRedeemFee,
        uint16 _downsidePeg,
        uint16 _colComp
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseMintFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_baseRedeemFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_downsidePeg <= Helpers.MAX_PERCENTAGE);
        vm.assume(_colComp <= Helpers.MAX_PERCENTAGE);

        collateralSetUp(USDCe, _colComp, _baseMintFee, _baseRedeemFee, _downsidePeg);
        manager.addCollateralStrategy(USDCe, STARGATE, 1000);
        vm.expectRevert(abi.encodeWithSelector(CollateralManager.AllocationPercentageLowerThanAllocatedAmt.selector));
        manager.updateCollateralStrategy(USDCe, STARGATE, 700);
    }

    function test_updateCollateralStrategy(
        uint16 _baseMintFee,
        uint16 _baseRedeemFee,
        uint16 _downsidePeg,
        uint16 _colComp,
        uint16 _allocCap
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseMintFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_baseRedeemFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_downsidePeg <= Helpers.MAX_PERCENTAGE);
        vm.assume(_colComp <= Helpers.MAX_PERCENTAGE);
        vm.assume(_allocCap <= Helpers.MAX_PERCENTAGE - 100);

        deal(USDCe, VAULT, 1e6);

        collateralSetUp(USDCe, _colComp, _baseMintFee, _baseRedeemFee, _downsidePeg);
        manager.addCollateralStrategy(USDCe, STARGATE, _allocCap);
        uint256 totalCollateral = manager.getCollateralInVault(USDCe) + manager.getCollateralInStrategies(USDCe);
        uint256 currentAllocatedPer =
            (manager.getCollateralInAStrategy(USDCe, STARGATE) * Helpers.MAX_PERCENTAGE) / totalCollateral;
        _allocCap = uint16(bound(_allocCap, currentAllocatedPer, Helpers.MAX_PERCENTAGE));
        vm.expectEmit(true, true, false, true);
        emit CollateralStrategyUpdated(USDCe, STARGATE);
        manager.updateCollateralStrategy(USDCe, STARGATE, _allocCap);
    }

    function test_updateMultipleCollateralStrategies(
        uint16 _baseMintFee,
        uint16 _baseRedeemFee,
        uint16 _downsidePeg,
        uint16 _colComp
    ) external useKnownActor(USDS_OWNER) {
        address[2] memory strategies = [AAVE, STARGATE];
        vm.assume(_baseMintFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_baseRedeemFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_downsidePeg <= Helpers.MAX_PERCENTAGE);
        vm.assume(_colComp <= Helpers.MAX_PERCENTAGE);

        collateralSetUp(USDCe, _colComp, _baseMintFee, _baseRedeemFee, _downsidePeg);
        (,,,,,,,,, uint16 collateralCapacityUsedBfr,) = manager.collateralInfo(USDCe);
        assertEq(collateralCapacityUsedBfr, 0);

        for (uint8 i = 0; i < strategies.length; i++) {
            vm.expectEmit(true, true, false, true);
            emit CollateralStrategyAdded(USDCe, strategies[i]);

            manager.addCollateralStrategy(USDCe, strategies[i], 3500);
            (,,,,,,,,, uint16 collateralCapacityUsed,) = manager.collateralInfo(USDCe);
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

contract CollateralManager_removeCollateralStrategy_Test is CollateralManagerTest {
    function test_revertsWhen_strategyNotMapped(
        uint16 _baseMintFee,
        uint16 _baseRedeemFee,
        uint16 _downsidePeg,
        uint16 _colComp
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseMintFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_baseRedeemFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_downsidePeg <= Helpers.MAX_PERCENTAGE);
        vm.assume(_colComp <= Helpers.MAX_PERCENTAGE);

        collateralSetUp(USDCe, _colComp, _baseMintFee, _baseRedeemFee, _downsidePeg);
        vm.expectRevert(abi.encodeWithSelector(CollateralManager.CollateralStrategyNotMapped.selector));
        manager.removeCollateralStrategy(USDCe, STARGATE);
    }

    function test_removeCollateralStrategy(
        uint16 _baseMintFee,
        uint16 _baseRedeemFee,
        uint16 _downsidePeg,
        uint16 _colComp
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseMintFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_baseRedeemFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_downsidePeg <= Helpers.MAX_PERCENTAGE);
        vm.assume(_colComp <= Helpers.MAX_PERCENTAGE / 2);

        collateralSetUp(USDCe, _colComp, _baseMintFee, _baseRedeemFee, _downsidePeg);
        collateralSetUp(DAI, _colComp, _baseMintFee, _baseRedeemFee, _downsidePeg);
        manager.addCollateralStrategy(USDCe, STARGATE, 2000);
        manager.addCollateralStrategy(USDCe, AAVE, 2000);

        vm.expectEmit(true, true, false, true);
        emit CollateralStrategyRemoved(USDCe, AAVE);
        manager.removeCollateralStrategy(USDCe, AAVE);
    }

    function test_revertsWhen_strategyInUse(
        uint16 _baseMintFee,
        uint16 _baseRedeemFee,
        uint16 _downsidePeg,
        uint16 _colComp
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseMintFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_baseRedeemFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_downsidePeg <= Helpers.MAX_PERCENTAGE);
        vm.assume(_colComp <= Helpers.MAX_PERCENTAGE);

        collateralSetUp(USDCe, _colComp, _baseMintFee, _baseRedeemFee, _downsidePeg);
        manager.addCollateralStrategy(USDCe, STARGATE, 2000);
        vm.expectRevert(abi.encodeWithSelector(CollateralManager.CollateralStrategyInUse.selector));
        manager.removeCollateralStrategy(USDCe, STARGATE);
    }

    function test_revertsWhen_DefaultStrategy(
        uint16 _baseMintFee,
        uint16 _baseRedeemFee,
        uint16 _downsidePeg,
        uint16 _colComp
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseMintFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_baseRedeemFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_downsidePeg <= Helpers.MAX_PERCENTAGE);
        vm.assume(_colComp <= Helpers.MAX_PERCENTAGE);

        collateralSetUp(USDCe, _colComp, _baseMintFee, _baseRedeemFee, _downsidePeg);
        manager.addCollateralStrategy(USDCe, STARGATE, 2000);
        manager.updateCollateralDefaultStrategy(USDCe, STARGATE);
        vm.expectRevert(abi.encodeWithSelector(CollateralManager.IsDefaultStrategy.selector));
        manager.removeCollateralStrategy(USDCe, STARGATE);
    }

    function test_revertsWhen_DefaultStrategyNotExist(
        uint16 _baseMintFee,
        uint16 _baseRedeemFee,
        uint16 _downsidePeg,
        uint16 _colComp
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseMintFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_baseRedeemFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_downsidePeg <= Helpers.MAX_PERCENTAGE);
        vm.assume(_colComp <= Helpers.MAX_PERCENTAGE / 2);

        collateralSetUp(USDCe, _colComp, _baseMintFee, _baseRedeemFee, _downsidePeg);
        manager.addCollateralStrategy(USDCe, STARGATE, 2000);
        vm.expectRevert(abi.encodeWithSelector(CollateralManager.CollateralStrategyNotMapped.selector));
        manager.updateCollateralDefaultStrategy(VST, STARGATE);
    }
}

contract CollateralManager_validateAllocation_test is CollateralManagerTest {
    function test_RevertWhen_CollateralAllocationPaused(
        uint16 _baseMintFee,
        uint16 _baseRedeemFee,
        uint16 _downsidePeg,
        uint16 _colComp
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseMintFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_baseRedeemFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_downsidePeg <= Helpers.MAX_PERCENTAGE);
        vm.assume(_colComp <= Helpers.MAX_PERCENTAGE);

        ICollateralManager.CollateralBaseData memory _data = ICollateralManager.CollateralBaseData({
            mintAllowed: true,
            redeemAllowed: true,
            allocationAllowed: false,
            baseMintFee: _baseMintFee,
            baseRedeemFee: _baseRedeemFee,
            downsidePeg: _downsidePeg,
            desiredCollateralComposition: 1000
        });
        manager.addCollateral(USDT, _data);
        manager.addCollateralStrategy(USDT, USDT_TWO_POOL_STRATEGY, 2000);
        vm.expectRevert(abi.encodeWithSelector(CollateralManager.CollateralAllocationPaused.selector));
        manager.validateAllocation(USDT, USDT_TWO_POOL_STRATEGY, 1);
    }

    function test_RevertWhen_CollateralStrategyNotMapped() external useKnownActor(USDS_OWNER) {
        // Avoid fuzzing here as this is a revert test
        collateralSetUp(
            USDT, Helpers.MAX_PERCENTAGE, Helpers.MAX_PERCENTAGE, Helpers.MAX_PERCENTAGE, Helpers.MAX_PERCENTAGE
        );

        vm.expectRevert(abi.encodeWithSelector(CollateralManager.CollateralStrategyNotMapped.selector));
        manager.validateAllocation(USDT, USDT_TWO_POOL_STRATEGY, 1);
    }

    function test_validateAllocation(uint16 _baseMintFee, uint16 _baseRedeemFee, uint16 _downsidePeg, uint16 _colComp)
        external
        useKnownActor(USDS_OWNER)
    {
        vm.assume(_baseMintFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_baseRedeemFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_downsidePeg <= Helpers.MAX_PERCENTAGE);
        vm.assume(_colComp <= Helpers.MAX_PERCENTAGE);

        collateralSetUp(USDCe, _colComp, _baseMintFee, _baseRedeemFee, _downsidePeg);
        manager.addCollateralStrategy(USDCe, STARGATE, 2000);
        manager.validateAllocation(USDCe, STARGATE, 1000);
    }

    function test_validateAllocationMaxCollateralUsageSup(
        uint16 _baseMintFee,
        uint16 _baseRedeemFee,
        uint16 _downsidePeg,
        uint16 _colComp
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseMintFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_baseRedeemFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_downsidePeg <= Helpers.MAX_PERCENTAGE);
        vm.assume(_colComp <= Helpers.MAX_PERCENTAGE);

        collateralSetUp(USDCe, _colComp, _baseMintFee, _baseRedeemFee, _downsidePeg);
        manager.addCollateralStrategy(USDCe, STARGATE, 10000);
        manager.validateAllocation(USDCe, STARGATE, 11000000000);
    }

    function test_getAllCollaterals(
        uint16 _baseMintFee,
        uint16 _baseRedeemFee,
        uint16 _downsidePeg,
        uint16 _collateralComposition
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseMintFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_baseRedeemFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_downsidePeg <= Helpers.MAX_PERCENTAGE);
        vm.assume(_collateralComposition <= Helpers.MAX_PERCENTAGE);
        address[5] memory collaterals = [USDCe, USDT, VST, FRAX, DAI];

        ICollateralManager.CollateralBaseData memory _data = ICollateralManager.CollateralBaseData({
            mintAllowed: true,
            redeemAllowed: true,
            allocationAllowed: true,
            baseMintFee: _baseMintFee,
            baseRedeemFee: _baseRedeemFee,
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
        uint16 _baseMintFee,
        uint16 _baseRedeemFee,
        uint16 _downsidePeg,
        uint16 _colComp
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseMintFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_baseRedeemFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_downsidePeg <= Helpers.MAX_PERCENTAGE);
        vm.assume(_colComp <= Helpers.MAX_PERCENTAGE);
        address[2] memory strategies = [AAVE, STARGATE];

        collateralSetUp(USDCe, _colComp, _baseMintFee, _baseRedeemFee, _downsidePeg);
        for (uint8 i = 0; i < strategies.length; i++) {
            manager.addCollateralStrategy(USDCe, strategies[i], 2000);
        }
        manager.isValidStrategy(USDCe, AAVE);
        manager.isValidStrategy(USDT, USDCe);

        address[] memory collateralStrategiesList = manager.getCollateralStrategies(USDCe);
        for (uint8 i = 0; i < collateralStrategiesList.length; i++) {
            assertEq(collateralStrategiesList[i], strategies[i]);
        }
    }
}

contract CollateralManager_mintRedeemParams_test is CollateralManagerTest {
    function test_getMintParams(
        uint16 _baseMintFee,
        uint16 _baseRedeemFee,
        uint16 _downsidePeg,
        uint16 _collateralComposition
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseMintFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_baseRedeemFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_downsidePeg <= Helpers.MAX_PERCENTAGE);
        vm.assume(_collateralComposition <= Helpers.MAX_PERCENTAGE);

        ICollateralManager.CollateralBaseData memory _data = ICollateralManager.CollateralBaseData({
            mintAllowed: true,
            redeemAllowed: true,
            allocationAllowed: true,
            baseMintFee: _baseMintFee,
            baseRedeemFee: _baseRedeemFee,
            downsidePeg: _downsidePeg,
            desiredCollateralComposition: 1000
        });
        manager.addCollateral(USDCe, _data);
        manager.addCollateralStrategy(USDCe, STARGATE, 2000);
        manager.addCollateralStrategy(USDCe, AAVE, 2000);
        ICollateralManager.CollateralMintData memory mintData = manager.getMintParams(USDCe);
        assertEq(mintData.mintAllowed, _data.mintAllowed);
        assertEq(mintData.baseMintFee, _data.baseMintFee);
        assertEq(mintData.downsidePeg, _data.downsidePeg);
        assertEq(mintData.desiredCollateralComposition, _data.desiredCollateralComposition);
    }

    function test_revertsWhen_getMintParams_collateralDoesntExist() external useKnownActor(USDS_OWNER) {
        vm.expectRevert(abi.encodeWithSelector(CollateralManager.CollateralDoesNotExist.selector));
        manager.getMintParams(USDT);
    }

    function test_getRedeemParams(
        uint16 _baseMintFee,
        uint16 _baseRedeemFee,
        uint16 _downsidePeg,
        uint16 _collateralComposition
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(_baseMintFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_baseRedeemFee <= Helpers.MAX_PERCENTAGE);
        vm.assume(_downsidePeg <= Helpers.MAX_PERCENTAGE);
        vm.assume(_collateralComposition <= Helpers.MAX_PERCENTAGE);

        ICollateralManager.CollateralBaseData memory _data = ICollateralManager.CollateralBaseData({
            mintAllowed: true,
            redeemAllowed: true,
            allocationAllowed: true,
            baseMintFee: _baseMintFee,
            baseRedeemFee: _baseRedeemFee,
            downsidePeg: _downsidePeg,
            desiredCollateralComposition: 1000
        });
        manager.addCollateral(USDCe, _data);
        manager.addCollateral(DAI, _data);
        manager.addCollateralStrategy(USDCe, STARGATE, 2000);
        manager.addCollateralStrategy(USDCe, AAVE, 2000);
        manager.updateCollateralDefaultStrategy(USDCe, STARGATE);

        ICollateralManager.CollateralRedeemData memory redeemData = manager.getRedeemParams(USDCe);
        assertEq(redeemData.redeemAllowed, _data.redeemAllowed);
        assertEq(redeemData.baseRedeemFee, _data.baseRedeemFee);
        assertEq(redeemData.defaultStrategy, STARGATE);
        assertEq(redeemData.desiredCollateralComposition, _data.desiredCollateralComposition);
    }

    function test_revertsWhen_getRedeemParams_collateralDoesntExist() external useKnownActor(USDS_OWNER) {
        vm.expectRevert(abi.encodeWithSelector(CollateralManager.CollateralDoesNotExist.selector));
        manager.getRedeemParams(FRAX);
    }
}
