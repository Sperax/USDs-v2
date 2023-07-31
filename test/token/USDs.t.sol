// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {BaseTest} from "../utils/BaseTest.sol";
import {UpgradeUtil} from "../utils/UpgradeUtil.sol";
import {USDs} from "../../contracts/token/USDs.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract USDsTest is BaseTest {
    USDs internal usds;
    USDs internal impl;
    UpgradeUtil internal upgradeUtil;
    address internal proxyAddress;
    address internal OWNER;
    address internal USER1 = 0xFb09ED8F4bd4C4D7D06Ad229cEb18e7CCB900A4c;
    address internal USER2 = 0xde627cDeD2A7241B1f3679821588dB42B62f7699;

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
        uint256 amount = 100000;
        usds.mint(VAULT, amount);
        usds.rebase(10000);
    }

    function test_transfer() public useKnownActor(VAULT) {
        uint256 amount = 100000;
        usds.mint(USER1, amount);
        changePrank(USER1);
        usds.balanceOf(USER1);
        usds.transfer(USER1, amount);
    }

    function test_transfer_from() public useKnownActor(VAULT) {
        uint256 amount = 100000;
        usds.mint(USER1, amount);
        usds.approve(VAULT, amount);
        usds.transferFrom(USER1, USER2, amount);
    }
}
