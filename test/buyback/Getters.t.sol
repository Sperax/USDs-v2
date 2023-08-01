// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {BuybackTestSetup} from "../setups/BuybackTestSetup.t.sol";

contract TestGetters is BuybackTestSetup {
    uint256 private usdsAmount;
    uint256 private spaReqd;

    function setUp() public override {
        super.setUp();
        usdsAmount = 100e18;
        spaIn = 100000e18;
    }

    function testGetSpaReqdForUSDs() public mockOracle {
        uint256 calculatedSpaReqd = _calculateSpaReqdForUSDs(usdsAmount);
        uint256 spaReqdByContract = spaBuyback.getSPAReqdForUSDs(usdsAmount);
        assertEq(calculatedSpaReqd, spaReqdByContract);
    }

    function testGetUsdsOutForSpa() public mockOracle {
        uint256 calculateUSDsOut = _calculateUSDsForSpaIn(spaIn);
        uint256 usdsOutByContract = spaBuyback.getUsdsOutForSpa(spaIn);
        assertEq(calculateUSDsOut, usdsOutByContract);
    }

    function testCannotIfInvalidAmount() public mockOracle {
        vm.expectRevert("Invalid Amount");
        spaBuyback.getUsdsOutForSpa(0);
    }
}
