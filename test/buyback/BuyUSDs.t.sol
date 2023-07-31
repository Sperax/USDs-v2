// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {BuybackTestSetup} from "../setups/BuybackTestSetup.t.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IUSDs} from "../../contracts/interfaces/IUSDs.sol";
import {IOracle} from "../../contracts/interfaces/IOracle.sol";

contract TestBuyUSDs is BuybackTestSetup {
    struct BalComparison {
        uint256 balBefore;
        uint256 balAfter;
    }

    BalComparison private spaTotalSupply;
    BalComparison private spaBal;

    event BoughtBack(
        address indexed receiverOfUSDs,
        address indexed senderOfSPA,
        uint256 spaPrice,
        uint256 spaAmount,
        uint256 usdsAmount
    );
    event SPARewarded(uint256 spaAmount);
    event SPABurned(uint256 spaAmount);
    event Transfer(address from, address to, uint256 amount);

    function setUp() public override {
        super.setUp();
        spaIn = 100000e18;
        minUSDsOut = 1;
    }

    function testCannotIfSpaAmountTooLow() public mockOracle {
        spaIn = 100;
        vm.expectRevert("SPA Amount too low");
        spaBuyback.buyUSDs(spaIn, minUSDsOut);
    }

    function testCannotIfSlippageMoreThanExpected() public mockOracle {
        minUSDsOut = 10000e18;
        vm.expectRevert("Slippage more than expected");
        spaBuyback.buyUSDs(spaIn, minUSDsOut);
    }

    function testCannotIfInsufficientUSDsBalance() public mockOracle {
        vm.expectRevert("Insufficient USDs balance");
        spaBuyback.buyUSDs(spaIn, minUSDsOut);
    }

    function testBuyUSDs() public mockOracle {
        minUSDsOut = _calculateUSDsForSpaIn(spaIn);
        vm.prank(VAULT);
        IUSDs(USDS).mint(address(spaBuyback), minUSDsOut + 10E18);
        spaTotalSupply.balBefore = IERC20(SPA).totalSupply();
        spaBal.balBefore = IERC20(SPA).balanceOf(VESPA_REWARDER);
        vm.startPrank(SPA_FUNDER);
        IERC20(SPA).approve(address(spaBuyback), spaIn);
        spaData = IOracle(ORACLE).getPrice(SPA);
        vm.expectEmit(true, true, false, true, address(spaBuyback));
        emit BoughtBack(
            SPA_FUNDER,
            SPA_FUNDER,
            spaData.price,
            spaIn,
            minUSDsOut
        );
        vm.expectEmit(true, true, true, true, address(spaBuyback));
        emit SPARewarded(spaIn / 2);
        vm.expectEmit(true, true, true, true, address(spaBuyback));
        emit SPABurned(spaIn / 2);
        spaBuyback.buyUSDs(spaIn, minUSDsOut);
        vm.stopPrank();
        spaTotalSupply.balAfter = IERC20(SPA).totalSupply();
        spaBal.balAfter = IERC20(SPA).balanceOf(VESPA_REWARDER);
        assertEq(spaBal.balAfter - spaBal.balBefore, spaIn / 2);
        assertEq(spaTotalSupply.balBefore - spaTotalSupply.balAfter, spaIn / 2);
    }

    // @todo check and fix reverts on fuzzing
    // Testing with fuzzing
    // function testBuyUSDs(
    //     uint256 spaIn,
    //     uint256 spaPrice,
    //     uint256 usdsPrice
    // ) public {
    //     uint256 spaBalance = IERC20(SPA).balanceOf(SPA_FUNDER);
    //     emit log_named_uint("SPA Balance", spaBalance);
    //     uint256 usdsBalance = IERC20(USDS).balanceOf(USDS_FUNDER);
    //     emit log_named_uint("USDs Balance", usdsBalance);
    //     bound(usdsPrice, 7e17, 13e17);
    //     bound(spaPrice, 1e15, 1e20);
    //     bound(spaIn, 50e18, spaBalance);
    //     if (((spaIn * spaPrice) / 1e18) > 1e18) {
    //         // bound(usdsOut, min, max);
    //         vm.mockCall(
    //             address(ORACLE),
    //             abi.encodeWithSignature("getPrice(address)", USDS),
    //             abi.encode(usdsPrice, 1e18)
    //         );
    //         vm.mockCall(
    //             address(ORACLE),
    //             abi.encodeWithSignature("getPrice(address)", SPA),
    //             abi.encode(spaPrice, 1e18)
    //         );
    //         minUSDsOut = spaBuyback.getUsdsOutForSpa(spaIn);
    //         vm.prank(USDS_FUNDER);
    //         IERC20(USDS).transfer(address(spaBuyback), minUSDsOut + 10E18);
    //         uint256 usdsBal.balBefore = IERC20(USDS).balanceOf(SPA_FUNDER);
    //         spaData = IOracle(ORACLE).getPrice(SPA);
    //         usdsData = IOracle(ORACLE).getPrice(USDS);
    //         vm.startPrank(SPA_FUNDER);
    //         IERC20(SPA).approve(address(spaBuyback), 100000e18);
    //         vm.expectEmit(true, true, true, false, address(spaBuyback));
    //         emit BoughtBack(
    //             SPA_FUNDER,
    //             SPA_FUNDER,
    //             spaData.price,
    //             spaIn,
    //             minUSDsOut
    //         );
    //         spaBuyback.buyUSDs(100000e18, 1);
    //         vm.stopPrank();
    //         vm.clearMockedCalls();
    //         uint256 usdsBal.balAfter = IERC20(USDS).balanceOf(SPA_FUNDER);
    //         emit log_named_uint("SPA spent", spaIn);
    //         emit log_named_uint("USDS received", usdsBal.balAfter - usdsBal.balBefore);
    //     }
    // }
}
