// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {BaseTest} from "../utils/BaseTest.sol";
import {UpgradeUtil} from "../utils/UpgradeUtil.sol";
import {USDs, Helpers} from "../../contracts/token/USDs.sol";
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
        uint256 totalSupply = USDs(USDS).totalSupply();
        (uint256 vaultBalance,) = USDs(USDS).creditsBalanceOf(VAULT);
        uint256 nonRebasingSupply = USDs(USDS).nonRebasingSupply();

        USDs usdsImpl = new USDs();
        vm.prank(ProxyAdmin(PROXY_ADMIN).owner());
        ProxyAdmin(PROXY_ADMIN).upgrade(ITransparentUpgradeableProxy(USDS), address(usdsImpl));

        vm.startPrank(USDS_OWNER);
        usds = USDs(USDS);

        (uint256 vaultBalanceModified,) = usds.creditsBalanceOf(VAULT);

        assertEq(totalSupply, usds.totalSupply());
        assertEq(vaultBalance, vaultBalanceModified);
        assertEq(nonRebasingSupply, usds.nonRebasingSupply());
    }
}

contract USDsTest is BaseTest {
    using StableMath for uint256;

    uint256 constant APPROX_ERROR_MARGIN = 1;
    uint256 constant FULL_SCALE = 1e18;
    uint256 MAX_SUPPLY = ~uint128(0);

    uint256 USDsPrecision;
    USDs internal usds;
    USDs internal impl;
    UpgradeUtil internal upgradeUtil;
    address internal proxyAddress;
    address internal OWNER;
    address internal USER1;
    address internal USER2;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    event TotalSupplyUpdated(uint256 totalSupply, uint256 rebasingCredits, uint256 rebasingCreditsPerToken);
    event Paused(bool isPaused);
    event VaultUpdated(address newVault);
    event RebaseOptIn(address indexed account);
    event RebaseOptOut(address indexed account);

    modifier testTransfer(uint256 amountToTransfer) {
        uint256 prevBalUser1 = usds.balanceOf(USER1);
        uint256 prevBalUser2 = usds.balanceOf(USER2);

        _;
        // @note account for precision error in USDs calculation for rebasing accounts
        assertApproxEqAbs(prevBalUser1 - amountToTransfer, usds.balanceOf(USER1), APPROX_ERROR_MARGIN);
        assertApproxEqAbs(prevBalUser2 + amountToTransfer, usds.balanceOf(USER2), APPROX_ERROR_MARGIN);
    }

    function setUp() public virtual override {
        super.setUp();
        setArbitrumFork();
        USER1 = actors[0];
        USER2 = actors[1];
        upgradeUtil = new UpgradeUtil();
        USDsPrecision = 10 ** ERC20(USDS).decimals();

        USDs usdsImpl = new USDs();
        vm.prank(ProxyAdmin(PROXY_ADMIN).owner());
        ProxyAdmin(PROXY_ADMIN).upgrade(ITransparentUpgradeableProxy(USDS), address(usdsImpl));

        vm.startPrank(USDS_OWNER);
        usds = USDs(USDS);
        usds.updateVault(VAULT);
        vm.stopPrank();
    }
}

contract TestInitialize is USDsTest {
    USDs internal newUsds;
    string internal tokenName = "TestToken";
    string internal tokenSymbol = "TT";
    uint256 internal EXPECTED_REBASING_CREDITS_PER_TOKEN = 1e27;

    error InvalidAddress();

    function setUp() public override {
        super.setUp();

        USDs usdsImpl = new USDs();
        newUsds = USDs(upgradeUtil.deployErc1967Proxy(address(usdsImpl)));
    }

    function test_revertWhen_InvalidAddress() public useKnownActor(USDS_OWNER) {
        vm.expectRevert(abi.encodeWithSelector(Helpers.InvalidAddress.selector));
        newUsds.initialize(tokenName, tokenSymbol, address(0));
    }

    function test_Initialize() public useKnownActor(USER1) {
        newUsds.initialize(tokenName, tokenSymbol, VAULT);

        assertEq(tokenName, newUsds.name());
        assertEq(tokenSymbol, newUsds.symbol());
        assertEq(VAULT, newUsds.vault());
        assertEq(EXPECTED_REBASING_CREDITS_PER_TOKEN, newUsds.rebasingCreditsPerToken());
        assertEq(currentActor, newUsds.owner());
    }

    function test_revertWhen_AlreadyInitialized() public useKnownActor(USDS_OWNER) {
        vm.expectRevert("Initializable: contract is already initialized");
        usds.initialize(tokenName, tokenSymbol, VAULT);
    }
}

contract TestTransferFrom is USDsTest {
    uint256 amount;

    function setUp() public override {
        super.setUp();

        amount = 10 * USDsPrecision;
        vm.startPrank(VAULT);
        usds.mint(USER1, amount);
        vm.stopPrank();
    }

    function test_revertWhen_InsufficientAllowance() public useKnownActor(VAULT) {
        uint256 amountToTransfer = usds.balanceOf(USER1);

        vm.expectRevert(bytes("Insufficient allowance"));
        usds.transferFrom(USER1, USER2, amountToTransfer);
    }

    function test_revertWhen_TransferGreaterThanBal() public useKnownActor(VAULT) {
        uint256 amountToTransfer = usds.balanceOf(USER1) + 1;

        vm.expectRevert(
            abi.encodeWithSelector(USDs.TransferGreaterThanBal.selector, amountToTransfer, amountToTransfer - 1)
        );
        usds.transferFrom(USER1, USER2, amountToTransfer);
    }

    function test_revertWhen_TransferToZeroAddr() public useKnownActor(USER1) {
        uint256 amountToTransfer = usds.balanceOf(USER1);

        vm.expectRevert(abi.encodeWithSelector(USDs.TransferToZeroAddr.selector));
        usds.transferFrom(USER1, address(0), amountToTransfer);
    }

    function test_revertWhen_ContractPaused() public useKnownActor(USER1) {
        changePrank(USDS_OWNER);
        usds.pauseSwitch(true);
        changePrank(USER1);

        usds.approve(VAULT, amount);
        changePrank(VAULT);

        vm.expectRevert(abi.encodeWithSelector(USDs.ContractPaused.selector));
        usds.transferFrom(USER1, USER2, amount);
    }

    function testFuzz_transferFrom(uint256 amount1) public useKnownActor(USER1) {
        amount1 = bound(amount1, 1, usds.balanceOf(USER1));
        uint256 prevBalUser1 = usds.balanceOf(USER1);
        uint256 prevBalUser2 = usds.balanceOf(USER2);

        vm.expectEmit(address(usds));
        emit Approval(USER1, VAULT, amount1);
        usds.approve(VAULT, amount1);

        changePrank(VAULT);
        vm.expectEmit(address(usds));
        emit Transfer(USER1, USER2, amount1);
        usds.transferFrom(USER1, USER2, amount1);

        // @note account for precision error in USDs calculation for rebasing accounts
        assertApproxEqAbs(prevBalUser1 - amount1, usds.balanceOf(USER1), APPROX_ERROR_MARGIN);
        assertApproxEqAbs(prevBalUser2 + amount1, usds.balanceOf(USER2), APPROX_ERROR_MARGIN);
        assertEq(usds.allowance(USER1, VAULT), 0);
    }

    function test_increaseAllowance() public useKnownActor(USER1) {
        uint256 currentAllowance = usds.allowance(USER1, VAULT);
        usds.increaseAllowance(VAULT, amount);

        assertEq(currentAllowance + amount, usds.allowance(USER1, VAULT));
    }

    function test_decreaseAllowance() public useKnownActor(USER1) {
        uint256 increase_amount = 1000 * USDsPrecision;
        uint256 decrease_amount = 100 * USDsPrecision;

        usds.increaseAllowance(VAULT, increase_amount);

        uint256 currentAllowance = usds.allowance(USER1, VAULT);
        usds.decreaseAllowance(VAULT, decrease_amount);

        assertEq(currentAllowance - decrease_amount, usds.allowance(USER1, VAULT));

        currentAllowance = usds.allowance(USER1, VAULT);
        usds.decreaseAllowance(VAULT, currentAllowance);

        assertEq(0, usds.allowance(USER1, VAULT));
    }
}

contract TestTransfer is USDsTest {
    uint256 amount;

    function setUp() public override {
        super.setUp();
        amount = 1000 * USDsPrecision;
        vm.startPrank(VAULT);
        usds.mint(USER1, amount);
        vm.stopPrank();
    }

    function test_revertWhen_TransferGreaterThanBal() public useKnownActor(USER1) {
        uint256 bal = usds.balanceOf(USER1);
        uint256 amountToTransfer = bal + 1;

        vm.expectRevert(abi.encodeWithSelector(USDs.TransferGreaterThanBal.selector, amountToTransfer, bal));
        usds.transfer(USER2, amountToTransfer);
    }

    function test_revertWhen_TransferToZeroAddr() public useKnownActor(USER1) {
        uint256 amountToTransfer = usds.balanceOf(USER1);

        vm.expectRevert(abi.encodeWithSelector(USDs.TransferToZeroAddr.selector));
        usds.transfer(address(0), amountToTransfer);
    }

    function test_revertWhen_ContractPaused() public {
        changePrank(USDS_OWNER);
        usds.pauseSwitch(true);
        changePrank(USER1);

        vm.expectRevert(abi.encodeWithSelector(USDs.ContractPaused.selector));
        usds.transfer(USER2, amount);
    }

    function testFuzz_transfer(uint256 amount1) public useKnownActor(USER1) {
        amount1 = bound(amount1, 1, usds.balanceOf(USER1));
        uint256 prevBalUser1 = usds.balanceOf(USER1);
        uint256 prevBalUser2 = usds.balanceOf(USER2);

        vm.expectEmit(address(usds));
        emit Transfer(USER1, USER2, amount1);
        usds.transfer(USER2, amount1);

        // @note account for precision error in USDs calculation for rebasing accounts
        assertApproxEqAbs(prevBalUser1 - amount1, usds.balanceOf(USER1), APPROX_ERROR_MARGIN);
        assertApproxEqAbs(prevBalUser2 + amount1, usds.balanceOf(USER2), APPROX_ERROR_MARGIN);
    }

    function test_transfer_sender_non_rebasing_from()
        public
        useKnownActor(USDS_OWNER)
        testTransfer(usds.balanceOf(USER1))
    {
        changePrank(USER1);
        usds.rebaseOptOut();
        usds.rebaseOptIn();

        usds.transfer(USER2, usds.balanceOf(USER1));
    }

    function test_transfer_sender_non_rebasing_to_and_from_v1()
        public
        useKnownActor(USDS_OWNER)
        testTransfer(usds.balanceOf(USER1))
    {
        changePrank(USER2);
        usds.rebaseOptOut();
        usds.rebaseOptIn();

        changePrank(USER1);
        usds.rebaseOptOut();

        usds.transfer(USER2, usds.balanceOf(USER1));
    }

    function test_transfer_sender_non_rebasing_to_and_from_v2()
        public
        useKnownActor(USDS_OWNER)
        testTransfer(usds.balanceOf(USER1))
    {
        changePrank(USER2);
        usds.rebaseOptOut();

        changePrank(USER1);
        usds.rebaseOptOut();
        usds.rebaseOptIn();

        usds.transfer(USER2, usds.balanceOf(USER1));
    }

    function test_transfer_both_non_rebasing() public useKnownActor(USDS_OWNER) testTransfer(usds.balanceOf(USER1)) {
        changePrank(USER2);
        usds.rebaseOptOut();

        changePrank(USER1);
        usds.rebaseOptOut();

        usds.transfer(USER2, usds.balanceOf(USER1));
    }
}

contract TestMint is USDsTest {
    uint256 amount;

    function setUp() public override {
        super.setUp();
        amount = 10 * USDsPrecision;
    }

    function test_revertWhen_CallerNotVault() public useKnownActor(USER1) {
        vm.expectRevert(abi.encodeWithSelector(USDs.CallerNotVault.selector, USER1));
        usds.mint(USDS_OWNER, amount);
    }

    function test_revertWhen_ContractPaused() public useKnownActor(USDS_OWNER) {
        usds.pauseSwitch(true);
        changePrank(VAULT);

        vm.expectRevert(abi.encodeWithSelector(USDs.ContractPaused.selector));
        usds.mint(USDS_OWNER, amount);
    }

    function test_revertWhen_MintToZeroAddr() public useKnownActor(VAULT) {
        vm.expectRevert(abi.encodeWithSelector(USDs.MintToZeroAddr.selector));
        usds.mint(address(0), amount);
    }

    function test_revertWhen_MaxSupplyReached() public useKnownActor(VAULT) {
        vm.expectRevert(abi.encodeWithSelector(USDs.MaxSupplyReached.selector, MAX_SUPPLY + usds.totalSupply()));
        usds.mint(USDS_OWNER, MAX_SUPPLY);
    }

    function testFuzz_mint_nonRebasing(uint256 _amount) public useKnownActor(VAULT) {
        amount = bound(_amount, 1, MAX_SUPPLY - usds.totalSupply());

        address account = USDS_OWNER; // USDS_OWNER is non-rebasing
        uint256 prevTotalSupply = usds.totalSupply();
        uint256 prevNonRebasingSupply = usds.nonRebasingSupply();

        vm.expectEmit(address(usds));
        emit Transfer(address(0), account, amount);
        usds.mint(account, amount);

        assertEq(usds.balanceOf(account), amount);
        assertEq(usds.totalSupply(), prevTotalSupply + amount);

        (uint256 creditBalance, uint256 creditPerToken) = usds.creditsBalanceOf(account);
        assertEq(usds.nonRebasingCreditsPerToken(account), 1);
        assertEq(usds.nonRebasingSupply(), prevNonRebasingSupply + amount);
        assertEq(creditBalance, amount);
        assertEq(creditPerToken, 1);
    }

    function testFuzz_mint_rebasing(uint256 _amount) public useKnownActor(VAULT) {
        amount = bound(_amount, 1, MAX_SUPPLY - usds.totalSupply());
        address account = USER1;

        uint256 prevTotalSupply = usds.totalSupply();
        uint256 prevNonRebasingSupply = usds.nonRebasingSupply();
        uint256 rebasingCreditsPerToken = usds.rebasingCreditsPerToken();

        vm.expectEmit(address(usds));
        emit Transfer(address(0), account, amount);
        usds.mint(account, amount);

        assertApproxEqAbs(usds.balanceOf(account), amount, APPROX_ERROR_MARGIN);
        assertEq(usds.totalSupply(), prevTotalSupply + amount);

        // Checks as USDS_OWNER is rebasing
        (uint256 creditBalance, uint256 creditPerToken) = usds.creditsBalanceOf(account);
        assertEq(usds.nonRebasingCreditsPerToken(account), 0);
        assertEq(usds.nonRebasingSupply(), prevNonRebasingSupply);
        assertApproxEqAbs(creditBalance, (amount * rebasingCreditsPerToken) / FULL_SCALE, APPROX_ERROR_MARGIN);
        assertEq(creditPerToken, rebasingCreditsPerToken);
    }
}

contract TestBurn is USDsTest {
    using StableMath for uint256;

    uint256 amount;

    function setUp() public override {
        super.setUp();
        amount = 100000;
    }

    function test_revertWhen_ContractPaused() public useKnownActor(USDS_OWNER) {
        usds.pauseSwitch(true);
        changePrank(VAULT);

        vm.expectRevert(abi.encodeWithSelector(USDs.ContractPaused.selector));
        usds.burn(amount);
    }

    function test_revertWhen_InsufficientBalance() public useKnownActor(USDS_OWNER) {
        changePrank(VAULT);
        usds.rebaseOptIn();

        vm.expectRevert("Insufficient balance");
        amount = 1000000000 * USDsPrecision;
        usds.burn(amount);
    }

    function test_burn_noChange() public useKnownActor(USDS_OWNER) {
        uint256 prevSupply = usds.totalSupply();
        usds.burn(0);
        assertEq(usds.totalSupply(), prevSupply);
    }

    function test_burn_nonRebasing(uint256 _amount) public useKnownActor(USDS_OWNER) {
        amount = bound(_amount, 1, MAX_SUPPLY - usds.totalSupply());
        address account = VAULT; // VAULT is rebasing and has some existing USDs.

        changePrank(account);
        usds.mint(account, amount);

        uint256 prevSupply = usds.totalSupply();
        uint256 prevNonRebasingSupply = usds.nonRebasingSupply();
        uint256 preBalance = usds.balanceOf(account);
        (uint256 prevCreditBalance,) = usds.creditsBalanceOf(account);

        vm.expectEmit(address(usds));
        emit Transfer(account, address(0), amount);
        usds.burn(amount);

        assertEq(usds.balanceOf(account), preBalance - amount);
        assertEq(usds.totalSupply(), prevSupply - amount);
        (uint256 creditBalance, uint256 creditPerToken) = usds.creditsBalanceOf(account);
        assertEq(usds.nonRebasingCreditsPerToken(account), 1);
        assertEq(usds.nonRebasingSupply(), prevNonRebasingSupply - amount);
        assertEq(creditBalance, prevCreditBalance - amount);
        assertEq(creditPerToken, 1);
    }

    function test_burn_rebasing(uint256 _amount) public useKnownActor(USDS_OWNER) {
        amount = bound(_amount, 1, MAX_SUPPLY - usds.totalSupply());
        address account = VAULT; // VAULT is rebasing and has some existing USDs.
        changePrank(account);
        usds.rebaseOptIn();
        usds.mint(account, amount);

        uint256 prevSupply = usds.totalSupply();
        uint256 prevNonRebasingSupply = usds.nonRebasingSupply();
        uint256 preBalance = usds.balanceOf(account);
        (uint256 prevCreditBalance,) = usds.creditsBalanceOf(account);
        uint256 rebasingCreditsPerToken = usds.rebasingCreditsPerToken();
        uint256 creditAmount = amount.mulTruncate(rebasingCreditsPerToken);

        vm.expectEmit(address(usds));
        emit Transfer(account, address(0), amount);
        usds.burn(amount);

        assertApproxEqAbs(usds.balanceOf(account), amount - preBalance, APPROX_ERROR_MARGIN);
        assertEq(usds.totalSupply(), prevSupply - amount);
        (uint256 creditBalance, uint256 creditPerToken) = usds.creditsBalanceOf(account);
        assertEq(usds.nonRebasingCreditsPerToken(account), 0);
        assertEq(usds.nonRebasingSupply(), prevNonRebasingSupply);
        assertApproxEqAbs(
            creditBalance, prevCreditBalance - (amount * rebasingCreditsPerToken) / FULL_SCALE, APPROX_ERROR_MARGIN
        );
        assertEq(creditBalance, prevCreditBalance - creditAmount);
        assertEq(creditPerToken, rebasingCreditsPerToken);
    }
}

contract TestRebaseOptIn is USDsTest {
    function test_revertIf_IsAlreadyRebasingAccount() public useKnownActor(USDS_OWNER) {
        usds.rebaseOptIn();
        vm.expectRevert(abi.encodeWithSelector(USDs.IsAlreadyRebasingAccount.selector, USDS_OWNER));
        usds.rebaseOptIn();
    }

    function test_revertWhen_CallerNotOwner() public useKnownActor(VAULT) {
        vm.expectRevert("Ownable: caller is not the owner");
        usds.rebaseOptIn(currentActor);
    }

    function test_rebaseOptIn() public useKnownActor(USDS_OWNER) {
        vm.expectEmit(address(usds));
        emit RebaseOptIn(USDS_OWNER);
        usds.rebaseOptIn();

        assertEq(usds.nonRebasingCreditsPerToken(USDS_OWNER), 0);
    }

    function test_rebaseOptIn_with_account_param() public useKnownActor(USDS_OWNER) {
        address account = VAULT;
        vm.expectEmit(address(usds));
        emit RebaseOptIn(account);
        usds.rebaseOptIn(account);

        assertEq(usds.nonRebasingCreditsPerToken(account), 0);
    }
}

contract TestRebaseOptOut is USDsTest {
    function test_revertIf_IsAlreadyNonRebasingAccount() public useKnownActor(USDS_OWNER) {
        vm.expectRevert(abi.encodeWithSelector(USDs.IsAlreadyNonRebasingAccount.selector, USDS_OWNER));
        usds.rebaseOptOut();
    }

    function test_revertWhen_CallerNotOwner() public useKnownActor(USER1) {
        vm.expectRevert("Ownable: caller is not the owner");
        usds.rebaseOptOut(currentActor);
    }

    function test_rebaseOptOut() public useKnownActor(USDS_OWNER) {
        usds.rebaseOptIn();

        vm.expectEmit(address(usds));
        emit RebaseOptOut(USDS_OWNER);
        usds.rebaseOptOut();

        assertEq(usds.nonRebasingCreditsPerToken(USDS_OWNER), 1);
    }

    function test_rebaseOptOut_with_account_param() public useKnownActor(USDS_OWNER) {
        address account = VAULT;
        changePrank(account);
        usds.rebaseOptIn();
        changePrank(USDS_OWNER);

        vm.expectEmit(address(usds));
        emit RebaseOptOut(account);
        usds.rebaseOptOut(account);

        assertEq(usds.nonRebasingCreditsPerToken(account), 1);
    }
}

contract TestRebase is USDsTest {
    using StableMath for uint256;

    function test_revertWhen_CallerNotVault() public useKnownActor(USER1) {
        vm.expectRevert(abi.encodeWithSelector(USDs.CallerNotVault.selector, USER1));
        usds.rebase(1);
    }

    function test_revertWhen_CannotIncreaseZeroSupply() public {
        address account = VAULT;
        changePrank(account);
        USDs usdsImpl = new USDs();
        USDs newUsds = USDs(upgradeUtil.deployErc1967Proxy(address(usdsImpl)));
        newUsds.initialize("a", "b", account);
        uint256 amount = 100000 * USDsPrecision;
        newUsds.mint(account, amount);
        assert(newUsds.totalSupply() == amount);
        assert(newUsds.balanceOf(account) == amount);

        vm.expectRevert(abi.encodeWithSelector(USDs.CannotIncreaseZeroSupply.selector));
        newUsds.rebase(amount);
    }

    function test_rebase(uint256 amount) public useKnownActor(VAULT) {
        amount = bound(amount, 1, MAX_SUPPLY - usds.totalSupply());

        address account = VAULT;
        usds.mint(account, amount);
        uint256 prevSupply = usds.totalSupply();
        uint256 prevNonRebasingSupply = usds.nonRebasingSupply();
        uint256 newNonRebasingSupply = prevNonRebasingSupply - amount;
        uint256 rebasingCredits = (prevSupply - prevNonRebasingSupply).mulTruncate(usds.rebasingCreditsPerToken());
        uint256 rebasingCreditsPerToken = rebasingCredits.divPrecisely(prevSupply - newNonRebasingSupply);

        vm.expectEmit(address(usds));
        emit Transfer(account, address(0), amount);
        vm.expectEmit(address(usds));
        emit TotalSupplyUpdated(prevSupply, rebasingCredits, rebasingCreditsPerToken);
        usds.rebase(amount);

        assertEq(prevSupply, usds.totalSupply());
        assertEq(rebasingCreditsPerToken, usds.rebasingCreditsPerToken());
        assertEq(newNonRebasingSupply, usds.nonRebasingSupply());
    }

    function test_rebase_no_supply_change() public useKnownActor(VAULT) {
        uint256 amount = 0;
        uint256 prevSupply = usds.totalSupply();
        uint256 nonRebasingSupply = usds.nonRebasingSupply();
        uint256 rebasingCreditsPerToken = usds.rebasingCreditsPerToken();
        uint256 rebasingCredits = (prevSupply - nonRebasingSupply).mulTruncate(rebasingCreditsPerToken);

        vm.expectEmit(address(usds));
        emit TotalSupplyUpdated(prevSupply, rebasingCredits, rebasingCreditsPerToken);
        usds.rebase(amount);

        assertEq(prevSupply, usds.totalSupply());
    }

    // TODO remove test?
    function test_rebase_opt_in() public useKnownActor(USDS_OWNER) {
        changePrank(VAULT);
        usds.rebaseOptIn();
        uint256 amount = 100000;
        usds.mint(VAULT, amount);
        uint256 prevSupply = usds.totalSupply();
        usds.rebase(amount);
        assertEq(prevSupply, usds.totalSupply());
    }

    // TODO remove test?
    function test_rebase_opt_out() public useKnownActor(USDS_OWNER) {
        changePrank(VAULT);
        usds.rebaseOptIn();
        usds.rebaseOptOut();
        uint256 amount = 100000;
        usds.mint(VAULT, amount);
        uint256 prevSupply = usds.totalSupply();
        usds.rebase(amount);
        assertEq(prevSupply, usds.totalSupply());
    }
}

contract TestUpdateVault is USDsTest {
    function test_revert_CallerNotOwner() public useKnownActor(USER1) {
        vm.expectRevert("Ownable: caller is not the owner");
        usds.updateVault(USER1);
    }

    function testFuzz_change_vault(address _newVault) public useKnownActor(USDS_OWNER) {
        vm.assume(_newVault != address(0));
        vm.expectEmit(address(usds));
        emit VaultUpdated(_newVault);
        usds.updateVault(_newVault);
        assertEq(_newVault, usds.vault());
    }
}

contract TestPauseSwitch is USDsTest {
    function test_revertWhen_CallerNotOwner() public useKnownActor(USER1) {
        vm.expectRevert("Ownable: caller is not the owner");
        usds.pauseSwitch(true);
    }

    function testFuzz_pauseSwitch(bool _bool) public useKnownActor(USDS_OWNER) {
        vm.expectEmit(address(usds));
        emit Paused(_bool);
        usds.pauseSwitch(_bool);
        assertEq(usds.paused(), _bool);
    }
}

contract TestEnsureRebasingMigration is USDsTest {
    using StableMath for uint256;

    uint256 amount;

    function setUp() public override {
        super.setUp();
        amount = 10 * 10 ** ERC20(USDS).decimals();
    }

    function test_nocode_to_code() public {
        uint256 salt = 123;
        bytes memory bytecode = type(USDs).creationCode;

        // Predict address using create2
        address predictedAddress = _getAddress(bytecode, salt);

        // Mint to predicted address
        vm.prank(VAULT);
        usds.mint(predictedAddress, amount);

        // Predicted address should be rebasing
        uint256 prevBalance = usds.balanceOf(predictedAddress);
        uint256 prevNonRebasingSupply = usds.nonRebasingSupply();
        assertEq(usds.nonRebasingCreditsPerToken(predictedAddress), 0);

        // Deploy contract at predicted address
        _deploy(bytecode, salt);

        // Trigger _isNonRebasingAccount by sending amount2 to any non-rebasing account
        vm.prank(msg.sender);
        usds.rebaseOptOut();
        uint256 transferAmount = amount / 2;
        vm.prank(predictedAddress);
        usds.transfer(msg.sender, transferAmount);

        // Predicted address should be non-rebasing
        uint256 newBalance = usds.balanceOf(predictedAddress);
        uint256 newNonRebasingSupply = usds.nonRebasingSupply();
        assertEq(newBalance, prevBalance - transferAmount);
        assertEq(newNonRebasingSupply, amount + prevNonRebasingSupply);
        assertEq(usds.nonRebasingCreditsPerToken(predictedAddress), 1);
    }

    function _deploy(bytes memory _bytecode, uint256 _salt) internal {
        address addr;

        /*
        NOTE: How to call create2

        create2(v, p, n, s)
        create new contract with code at memory p to p + n
        and send v wei
        and return the new address
        where new address = first 20 bytes of keccak256(0xff + address(this) + s + keccak256(mem[p…(p+n)))
              s = big-endian 256-bit value
        */
        assembly {
            addr :=
                create2(
                    callvalue(), // wei sent with current call
                    // Actual code starts after skipping the first 32 bytes
                    add(_bytecode, 0x20),
                    mload(_bytecode), // Load the size of code contained in the first 32 bytes
                    _salt // Salt from function arguments
                )

            if iszero(extcodesize(addr)) { revert(0, 0) }
        }
    }

    function _getAddress(bytes memory bytecode, uint256 _salt) internal view returns (address) {
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), _salt, keccak256(bytecode)));

        // NOTE: cast last 20 bytes of hash to address
        return address(uint160(uint256(hash)));
    }
}
