// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {BaseTest} from "../utils/BaseTest.sol";
import {UpgradeUtil} from "../utils/UpgradeUtil.sol";
import {USDs} from "../../contracts/token/USDs.sol";
import {IERC20, ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {SafeMathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import {StableMath} from "../../contracts/libraries/StableMath.sol";
import {IUSDs} from "../../contracts/interfaces/IUSDs.sol";

contract USDsUpgradabilityTest is BaseTest {
    USDs internal usds;

    function setUp() public virtual override {
        super.setUp();
        setArbitrumFork();
    }

    function test_data() public {
        address USER = 0x9c140BE63db897E8D8b6AA42B6c1B5e5a37ce28c;
        uint256 totalSupply = USDs(USDS).totalSupply();
        (uint256 vaultBalance, ) = USDs(USDS).creditsBalanceOf(VAULT);
        uint256 nonRebasingSupply = USDs(USDS).nonRebasingSupply();

        USDs usdsImpl = new USDs();
        vm.prank(ProxyAdmin(PROXY_ADMIN).owner());
        ProxyAdmin(PROXY_ADMIN).upgrade(
            ITransparentUpgradeableProxy(USDS),
            address(usdsImpl)
        );

        vm.startPrank(USDS_OWNER);
        usds = USDs(USDS);

        (uint256 vaultBalanceModified, ) = usds.creditsBalanceOf(VAULT);

        assertEq(totalSupply, usds.totalSupply());
        assertEq(vaultBalance, vaultBalanceModified);
        assertEq(nonRebasingSupply, usds.nonRebasingSupply());
    }
}

contract USDsTest is BaseTest {
    using StableMath for uint256;
    uint256 USDsPrecision;
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
        USDsPrecision = 10 ** ERC20(USDS).decimals();

        USDs usdsImpl = new USDs();
        vm.prank(ProxyAdmin(PROXY_ADMIN).owner());
        ProxyAdmin(PROXY_ADMIN).upgrade(
            ITransparentUpgradeableProxy(USDS),
            address(usdsImpl)
        );

        vm.startPrank(USDS_OWNER);
        usds = USDs(USDS);
        usds.changeVault(VAULT);
        vm.stopPrank();
    }

    function test_change_vault() public useKnownActor(USDS_OWNER) {
        usds.changeVault(USER1);
        assertEq(USER1, usds.vaultAddress());
    }
}

contract TestTransfer is USDsTest {
    uint256 amount;

    function setUp() public override {
        super.setUp();

        amount = 10 * USDsPrecision;
        vm.startPrank(VAULT);
        usds.mint(USER1, amount);
        vm.stopPrank();
    }

    function test_transfer() public useKnownActor(USER1) {
        uint amountToTransfer = usds.balanceOf(USER1);
        uint256 prevBalUser1 = usds.balanceOf(USER1);
        uint256 prevBalUser2 = usds.balanceOf(USER2);

        usds.transfer(USER2, amountToTransfer);

        assertEq(prevBalUser1 - amountToTransfer, usds.balanceOf(USER1));
        assertEq(prevBalUser2 + amountToTransfer, usds.balanceOf(USER2));
    }

    function test_transfer_from() public useKnownActor(USER1) {
        usds.approve(VAULT, amount);

        changePrank(VAULT);

        uint amountToTransfer = usds.balanceOf(USER1);
        uint256 prevBalUser1 = usds.balanceOf(USER1);
        uint256 prevBalUser2 = usds.balanceOf(USER2);

        usds.transferFrom(USER1, USER2, amountToTransfer);

        assertEq(prevBalUser1 - amountToTransfer, usds.balanceOf(USER1));
        assertEq(prevBalUser2 + amountToTransfer, usds.balanceOf(USER2));
    }

    function test_transfer_from_without_approval() public useKnownActor(VAULT) {
        vm.expectRevert(bytes("Insufficient allowance"));

        usds.transferFrom(USER1, USER2, usds.balanceOf(USER1));
    }

    function test_transfer_sender_non_rebasing_from()
        public
        useKnownActor(USDS_OWNER)
    {
        usds.rebaseOptOut(USER1);
        usds.rebaseOptIn(USER1);

        changePrank(USER1);

        uint amountToTransfer = usds.balanceOf(USER1);
        uint256 prevBalUser1 = usds.balanceOf(USER1);
        uint256 prevBalUser2 = usds.balanceOf(USER2);

        usds.transfer(USER2, amountToTransfer);

        assertEq(prevBalUser1 - amountToTransfer, usds.balanceOf(USER1));
        assertEq(prevBalUser2 + amountToTransfer, usds.balanceOf(USER2));

        vm.expectRevert("Transfer greater than balance");
        usds.transfer(USER2, amountToTransfer);
    }

    function test_transfer_sender_non_rebasing_to_and_from_v1()
        public
        useKnownActor(USDS_OWNER)
    {
        usds.rebaseOptOut(USER1);

        usds.rebaseOptOut(USER2);
        usds.rebaseOptIn(USER2);

        changePrank(USER1);

        uint amountToTransfer = usds.balanceOf(USER1);
        uint256 prevBalUser1 = usds.balanceOf(USER1);
        uint256 prevBalUser2 = usds.balanceOf(USER2);

        usds.transfer(USER2, amountToTransfer);

        assertEq(prevBalUser1 - amountToTransfer, usds.balanceOf(USER1));
        assertEq(prevBalUser2 + amountToTransfer, usds.balanceOf(USER2));

        vm.expectRevert("Transfer greater than balance");
        usds.transfer(USER2, amountToTransfer);
    }

    function test_transfer_sender_non_rebasing_to_and_from_v2()
        public
        useKnownActor(USDS_OWNER)
    {
        usds.rebaseOptOut(USER1);
        usds.rebaseOptIn(USER1);

        usds.rebaseOptOut(USER2);

        changePrank(USER1);

        uint amountToTransfer = usds.balanceOf(USER1);
        uint256 prevBalUser1 = usds.balanceOf(USER1);
        uint256 prevBalUser2 = usds.balanceOf(USER2);

        usds.transfer(USER2, amountToTransfer);

        assertEq(prevBalUser1 - amountToTransfer, usds.balanceOf(USER1));
        assertEq(prevBalUser2 + amountToTransfer, usds.balanceOf(USER2));

        vm.expectRevert("Transfer greater than balance");
        usds.transfer(USER2, amountToTransfer);
    }

    function test_increaseAllowance() public useKnownActor(USER1) {
        uint256 currentAllownace = usds.allowance(USER1, VAULT);
        usds.increaseAllowance(VAULT, amount);

        assertEq(currentAllownace + amount, usds.allowance(USER1, VAULT));
    }

    function test_decreaseAllowance() public useKnownActor(USER1) {
        uint256 increase_amount = 1000 * USDsPrecision;
        uint256 decrease_amount = 100 * USDsPrecision;

        usds.increaseAllowance(VAULT, increase_amount);

        uint256 currentAllownace = usds.allowance(USER1, VAULT);
        usds.decreaseAllowance(VAULT, decrease_amount);

        assertEq(
            currentAllownace - decrease_amount,
            usds.allowance(USER1, VAULT)
        );
    }

    function test_allowance() public useKnownActor(USER1) {
        usds.allowance(USER1, VAULT);
    }

    function test_creditsBalanceOf() public useKnownActor(USER1) {
        usds.creditsBalanceOf(USER1);
    }
}

contract TestMint is USDsTest {
    uint256 amount;

    function setUp() public override {
        super.setUp();
        amount = 10 * USDsPrecision;
    }

    function test_mint_owner_check() public useActor(0) {
        vm.expectRevert("Caller is not the Vault");
        usds.mint(USDS_OWNER, amount);
    }

    function test_mint_to_the_zero() public useKnownActor(VAULT) {
        vm.expectRevert("Mint to the zero address");
        usds.mint(address(0), amount);
    }

    function test_max_supply() public useKnownActor(VAULT) {
        vm.expectRevert("Max supply");
        uint256 MAX_SUPPLY = ~uint128(0);
        usds.mint(USDS_OWNER, MAX_SUPPLY);
    }

    function test_mint_puased() public useKnownActor(USDS_OWNER) {
        usds.pauseSwitch(true);
        changePrank(VAULT);

        vm.expectRevert("Contract paused");
        usds.mint(USDS_OWNER, amount);

        changePrank(USDS_OWNER);
        usds.pauseSwitch(false);

        changePrank(VAULT);
        usds.mint(USDS_OWNER, amount);
        assertEq(usds.balanceOf(USDS_OWNER), amount);
    }

    function test_mint() public useKnownActor(VAULT) {
        usds.mint(USDS_OWNER, amount);

        assertEq(usds.balanceOf(USDS_OWNER), amount);
    }
}

contract TestBurn is USDsTest {
    using StableMath for uint256;
    uint256 amount;

    function setUp() public override {
        super.setUp();
        amount = 100000;
    }

    function test_burn_opt_in() public useKnownActor(USDS_OWNER) {
        usds.rebaseOptIn(VAULT);
        usds.rebaseOptOut(VAULT);

        uint256 prevSupply = usds.totalSupply();
        uint256 prevNonRebasingSupply = usds.nonRebasingSupply();
        uint256 preBalance = usds.balanceOf(VAULT);

        changePrank(VAULT);

        usds.burn(amount);
        assertEq(usds.totalSupply(), prevSupply - amount);
        assertEq(usds.nonRebasingSupply(), prevNonRebasingSupply - amount);
        assertEq(usds.balanceOf(VAULT), preBalance - amount);
    }

    function test_creadit_amount_changes_case1()
        public
        useKnownActor(USDS_OWNER)
    {
        usds.rebaseOptIn(VAULT);
        changePrank(VAULT);

        uint256 creditAmount = amount.mulTruncate(
            usds.rebasingCreditsPerToken()
        );

        (uint256 currentCredits, ) = usds.creditsBalanceOf(VAULT);
        usds.burn(amount);

        (uint256 newCredits, ) = usds.creditsBalanceOf(VAULT);

        assertEq(newCredits, currentCredits - creditAmount);
    }

    function test_burn_case2() public useKnownActor(USDS_OWNER) {
        usds.rebaseOptIn(VAULT);
        changePrank(VAULT);

        usds.transfer(USER1, usds.balanceOf(VAULT));
        usds.mint(VAULT, amount);

        usds.burn(amount);

        (uint256 currentCredits, ) = usds.creditsBalanceOf(VAULT);
        assertEq(currentCredits, 0);
    }

    function test_burn_case3() public useKnownActor(USDS_OWNER) {
        usds.rebaseOptIn(VAULT);
        changePrank(VAULT);

        vm.expectRevert("Remove exceeds balance");
        amount = 1000000000 * USDsPrecision;
        usds.burn(amount);
    }

    function test_burn() public useKnownActor(VAULT) {
        uint256 prevSupply = usds.totalSupply();
        usds.burn(amount);
        assertEq(usds.totalSupply(), prevSupply - amount);
    }
}

contract TestRebase is USDsTest {
    function setUp() public override {
        super.setUp();
    }

    function test_rebaseOptIn() public useKnownActor(USDS_OWNER) {
        usds.rebaseOptIn(USDS_OWNER);

        assertEq(usds.nonRebasingCreditsPerToken(USDS_OWNER), 0);
    }

    function test_rebaseOptOut() public useKnownActor(USDS_OWNER) {
        usds.rebaseOptIn(USDS_OWNER);
        usds.rebaseOptOut(USDS_OWNER);

        assertEq(usds.nonRebasingCreditsPerToken(USDS_OWNER), 1);
    }

    function test_pauseSwitch() public useKnownActor(USDS_OWNER) {
        usds.pauseSwitch(true);
        assertEq(usds.paused(), true);
    }

    function test_rebase() public useKnownActor(VAULT) {
        uint256 amount = 1000000000 * USDsPrecision;
        usds.mint(VAULT, amount);

        uint256 prevSupply = usds.totalSupply();
        usds.rebase(100000 * USDsPrecision);

        assertEq(prevSupply, usds.totalSupply());
    }

    function test_rebase_no_suuply_change() public useKnownActor(VAULT) {
        uint256 prevSupply = usds.totalSupply();

        uint256 amount = 0;
        usds.rebase(amount);

        assertEq(prevSupply, usds.totalSupply());
    }

    function test_rebase_opt_in() public useKnownActor(USDS_OWNER) {
        usds.rebaseOptIn(VAULT);
        uint256 amount = 100000;
        changePrank(VAULT);

        uint256 prevSupply = usds.totalSupply();
        usds.rebase(amount);
        assertEq(prevSupply, usds.totalSupply());
    }
}
