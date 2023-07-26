// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {BuybackTestSetup} from "../setups/BuybackTestSetup.t.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestWithdraw is BuybackTestSetup {
    address private token;
    address private receiver;
    uint256 private amount;

    event Withdrawn(
        address indexed token,
        address indexed receiver,
        uint256 amount
    );

    function setUp() public override {
        super.setUp();
        token = USDS;
        receiver = actors[0];
        amount = 100e18;
        vm.prank(USDS_FUNDER);
        IERC20(USDS).transfer(address(spaBuyback), amount);
    }

    function testCannotIfCallerNotOwner() public useActor(0) {
        vm.expectRevert("Ownable: caller is not the owner");
        spaBuyback.withdraw(token, receiver, amount);
    }

    function testCannotWithdrawSPA() public useKnownActor(USDS_OWNER) {
        token = SPA;
        vm.expectRevert("SPA Buyback: Cannot withdraw SPA");
        spaBuyback.withdraw(token, receiver, amount);
    }

    function testCannotWithdrawMoreThanBalance()
        public
        useKnownActor(USDS_OWNER)
    {
        amount = IERC20(USDS).balanceOf(address(spaBuyback));
        amount = amount + 100e18;
        vm.expectRevert("Transfer greater than balance");
        spaBuyback.withdraw(token, receiver, amount);
    }

    function testWithdraw() public useKnownActor(USDS_OWNER) {
        uint256 balBefore = IERC20(USDS).balanceOf(receiver);
        vm.expectEmit(true, true, true, true, address(spaBuyback));
        emit Withdrawn(token, receiver, amount);
        spaBuyback.withdraw(token, receiver, amount);
        uint256 balAfter = IERC20(USDS).balanceOf(receiver);
        assertEq(balAfter - balBefore, amount);
    }
}
