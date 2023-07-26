// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {BuybackTestSetup} from "../setups/BuybackTestSetup.t.sol";

contract TestInit is BuybackTestSetup {
    function testCannotInitializeTwice() external useKnownActor(USDS_OWNER) {
        vm.expectRevert("Initializable: contract is already initialized");
        spaBuyback.initialize(VESPA_REWARDER, rewardPercentage);
    }

    function testCannotInitializeImplementation()
        external
        useKnownActor(USDS_OWNER)
    {
        vm.expectRevert("Initializable: contract is already initialized");
        spaBuybackImpl.initialize(VESPA_REWARDER, rewardPercentage);
    }

    function testInit() external {
        assertEq(spaBuyback.veSpaRewarder(), VESPA_REWARDER);
        assertEq(spaBuyback.rewardPercentage(), rewardPercentage);
    }
}
