// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {BaseTest} from "./BaseTest.sol";
import {CollateralManager} from "../contracts/vault/CollateralManager.sol";
import {ICollateralManager} from "../contracts/vault/interfaces/ICollateralManager.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract CollateralManagerTest is BaseTest {
    address public constant USDCe = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    
    //  Init Variables.
    CollateralManager public manager;

    // Events from the actual contract.
    // event CollateralAdded(address collateral, CollateralBaseData data);
    // event CollateralRemoved(address collateral);
    // event CollateralInfoUpdated(address collateral, CollateralBaseData data);
    // event CollateralStrategyAdded(address collateral, address strategy);
    // event CollateralStrategyUpdated(address collateral, address strategy);
    // event CollateralStrategyRemoved(address collateral, address strategy);
    function setUp() override public{
        super.setUp();
        setArbitrumFork();
        manager = new CollateralManager();
        manager.transferOwnership(USDS_OWNER);
    }

    

}

contract CollateralManager_AddCollateral_Test is CollateralManagerTest {
    function test_revertsWhen_baseFeeExceedsMax(uint16 _baseFeeIn, uint16 _baseFeeOut, uint16 _downsidePeg) external useKnownActor(USDS_OWNER){
        
        
        vm.assume(_baseFeeIn > manager.PERC_PRECISION());
        vm.assume(_baseFeeOut > manager.PERC_PRECISION());
        vm.assume(_downsidePeg > manager.PERC_PRECISION());

        ICollateralManager.CollateralBaseData memory _data = ICollateralManager.CollateralBaseData(
            {
                mintAllowed: true,
                redeemAllowed: true,
                allocationAllowed: true,
                baseFeeIn: _baseFeeIn,
                baseFeeOut: _baseFeeOut,
                downsidePeg: _downsidePeg,
                collateralCompostion: 2000
            }
        );
        vm.expectRevert("Illegal PERC input");
        manager.addCollateral(USDCe,_data);
    }

    function test_revertsWhen_addSameCollateral(uint16 _baseFeeIn, uint16 _baseFeeOut, uint16 _downsidePeg) external useKnownActor(USDS_OWNER){
        vm.assume(_baseFeeIn <= manager.PERC_PRECISION());
        vm.assume(_baseFeeOut <= manager.PERC_PRECISION());
        vm.assume(_downsidePeg <= manager.PERC_PRECISION());

        ICollateralManager.CollateralBaseData memory _data = ICollateralManager.CollateralBaseData(
            {
                mintAllowed: true,
                redeemAllowed: true,
                allocationAllowed: true,
                baseFeeIn: _baseFeeIn,
                baseFeeOut: _baseFeeOut,
                downsidePeg: _downsidePeg,
                collateralCompostion: 2000
            }
        );
        manager.addCollateral(USDCe,_data);
        vm.expectRevert("Collateral already exists");
        manager.addCollateral(USDCe,_data);
    }
    function test_addCollateral(uint16 _baseFeeIn, uint16 _baseFeeOut, uint16 _downsidePeg,uint16 _collateralCompostion) external useKnownActor(USDS_OWNER){
        vm.assume(_baseFeeIn <= manager.PERC_PRECISION());
        vm.assume(_baseFeeOut <= manager.PERC_PRECISION());
        vm.assume(_downsidePeg <= manager.PERC_PRECISION());
        vm.assume(_collateralCompostion <= manager.PERC_PRECISION());

        ICollateralManager.CollateralBaseData memory _data = ICollateralManager.CollateralBaseData(
            {
                mintAllowed: true,
                redeemAllowed: true,
                allocationAllowed: true,
                baseFeeIn: _baseFeeIn,
                baseFeeOut: _baseFeeOut,
                downsidePeg: _downsidePeg,
                collateralCompostion: _collateralCompostion
            }
        );
        manager.addCollateral(USDCe,_data);
    }
    

}

 
