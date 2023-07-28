// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {BaseTest} from "../utils/BaseTest.sol";
import {UpgradeUtil} from "../utils/UpgradeUtil.sol";
import {USDs} from "../../contracts/token/USDs.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract USDsTest is BaseTest {
    USDs internal usds;
    USDs internal impl;
    UpgradeUtil internal upgradeUtil;
    address internal proxyAddress;

    function setUp() public virtual override {
        super.setUp();
        setArbitrumFork();
        vm.startPrank(USDS_OWNER);
        impl = new USDs();
        upgradeUtil = new UpgradeUtil();
        proxyAddress = upgradeUtil.deployErc1967Proxy(address(impl));

        usds = USDs(proxyAddress);
        usds.changeVault(VAULT);
        vm.stopPrank();
    }

    function test_mint() public useKnownActor(VAULT) {
        uint256 amount = 100000;
        usds.mint(USDS_OWNER, amount);

        assertEq(usds.balanceOf(USDS_OWNER), amount);
    }

    function test_burn() public useKnownActor(VAULT) {
        uint256 amount = 100000;
        usds.mint(VAULT, amount);
        usds.burn(amount);
    }

    function test_rebaseOptIn() public useKnownActor(USDS_OWNER) {
        usds.rebaseOptIn(USDS_OWNER);
    }

    function test_rebaseOptOut() public useKnownActor(USDS_OWNER) {
        usds.rebaseOptIn(USDS_OWNER);
        usds.rebaseOptOut(USDS_OWNER);
    }

    function test_pauseSwitch() public useKnownActor(USDS_OWNER) {
        usds.pauseSwitch(true);
        assertEq(usds.paused(), true);
    }

    function test_rebase() public useKnownActor(VAULT) {
        usds.rebase(10000);
    }
}
