// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {BuybackTestSetup} from "../setups/BuybackTestSetup.t.sol";

contract TestSetters is BuybackTestSetup {
    event RewardPercentageUpdated(
        uint256 oldRewardPercentage,
        uint256 newRewardPercentage
    );
    event VeSpaRewarderUpdated(
        address oldVeSpaRewarder,
        address newVeSpaRewarder
    );

    function testCannotIfCallerNotOwner() external useActor(0) {
        vm.expectRevert("Ownable: caller is not the owner");
        spaBuyback.updateRewardPercentage(9000);
        vm.expectRevert("Ownable: caller is not the owner");
        spaBuyback.updateVeSpaRewarder(actors[0]);
    }

    // function updateRewardPercentage
    function testCannotIfPercentageIsZero() external useKnownActor(USDS_OWNER) {
        vm.expectRevert("Reward percentage cannot be zero");
        spaBuyback.updateRewardPercentage(0);
    }

    function testCannotIfPercentageMoreThanMax()
        external
        useKnownActor(USDS_OWNER)
    {
        vm.expectRevert("Reward percentage cannot be > 100%");
        spaBuyback.updateRewardPercentage(10001);
    }

    function testUpdateRewardPercentage() external useKnownActor(USDS_OWNER) {
        uint256 oldRewardPercentage = spaBuyback.rewardPercentage();
        uint256 newRewardPercentage = 8000;
        vm.expectEmit(true, true, true, true, address(spaBuyback));
        emit RewardPercentageUpdated(oldRewardPercentage, newRewardPercentage);
        spaBuyback.updateRewardPercentage(8000);
        assertEq(spaBuyback.rewardPercentage(), newRewardPercentage);
    }

    // function updateVeSpaRewarder
    function testCannotIfInvalidAddress() external useKnownActor(USDS_OWNER) {
        vm.expectRevert("Invalid Address");
        spaBuyback.updateVeSpaRewarder(address(0));
    }

    function testUpdateVeSpaRewarder() external useKnownActor(USDS_OWNER) {
        address oldRewarder = spaBuyback.veSpaRewarder();
        address newRewarder = actors[1];
        vm.expectEmit(true, true, true, true, address(spaBuyback));
        emit VeSpaRewarderUpdated(oldRewarder, newRewarder);
        spaBuyback.updateVeSpaRewarder(newRewarder);
        assertEq(spaBuyback.veSpaRewarder(), newRewarder);
    }
}
