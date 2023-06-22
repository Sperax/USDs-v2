// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {BaseTest} from "../BaseTest.sol";
import {AaveStrategy} from "../../contracts/strategies/aave/AaveStrategy.sol";
import "forge-std/console.sol";



contract AaveStrategyTest is BaseTest { 
    AaveStrategy public aaveStrategy;

    event PTokenAdded(address indexed asset, address pToken);
    event IntLiqThresholdChanged(
        address indexed asset,
        uint256 intLiqThreshold
    );

    function setUp() override public {
        super.setUp();
        setArbitrumFork();
        aaveStrategy = deployAaveStratedgy();
        vm.startPrank(USDS_OWNER);
            aaveStrategy.initialize(
                0xa97684ead0e402dC232d5A977953DF7ECBaB3CDb, 
                0xa97684ead0e402dC232d5A977953DF7ECBaB3CDb
                );
        vm.stopPrank();
    }


    function test_revertsWhen_unAuthorized_SetPtoken() external useActor(0){
        vm.expectRevert("Ownable: caller is not the owner");
        aaveStrategy.setPTokenAddress(
            0x82aF49447D8a07e3bd95BD0d56f35241523fBab1, 
            0xe50fA9b3c56FfB159cB0FCA61F5c9D750e8128c8, 0
        );
    }


    function test_SetPtoken()  external useKnownActor(USDS_OWNER) {

        vm.expectEmit(true, false, false, false);

        emit PTokenAdded(address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1), address(0xe50fA9b3c56FfB159cB0FCA61F5c9D750e8128c8));

        aaveStrategy.setPTokenAddress(
            0x82aF49447D8a07e3bd95BD0d56f35241523fBab1, 
            0xe50fA9b3c56FfB159cB0FCA61F5c9D750e8128c8, 0
        );
    }


    function test_revertsWhen_unAuthorized_updateIntLiqThreshold() external useActor(0) {
        vm.expectRevert("Ownable: caller is not the owner");

        aaveStrategy.updateIntLiqThreshold(0xe50fA9b3c56FfB159cB0FCA61F5c9D750e8128c8, 2);
    }

    function test_revert_Collateral_not_supported_updateIntLiqThreshold() external useKnownActor(USDS_OWNER) {
        vm.expectRevert("Collateral not supported");

        aaveStrategy.updateIntLiqThreshold(0xe50fA9b3c56FfB159cB0FCA61F5c9D750e8128c8, 2);
    }

    function test_updateIntLiqThreshold() external useKnownActor(USDS_OWNER) {      
        aaveStrategy.setPTokenAddress(
            0x82aF49447D8a07e3bd95BD0d56f35241523fBab1, 
            0xe50fA9b3c56FfB159cB0FCA61F5c9D750e8128c8, 0
        );

        vm.expectEmit(true, false, false, false);

        emit IntLiqThresholdChanged(address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1), uint256(2));
        aaveStrategy.updateIntLiqThreshold(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1, 2);
    }

}