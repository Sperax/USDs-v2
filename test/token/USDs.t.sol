// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {BaseTest} from "../utils/BaseTest.sol";
import {UpgradeUtil} from "../utils/UpgradeUtil.sol";
import {USDs} from "../../contracts/token/USDs.sol";
import {IERC20, ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {SafeMathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import {StableMath} from "../../contracts/libraries/StableMath.sol";
import {IUSDs} from "../../contracts/interfaces/IUSDs.sol";
import "forge-std/console.sol";

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

    uint256 USDsPrecision;
    USDs internal usds;
    USDs internal impl;
    UpgradeUtil internal upgradeUtil;
    address internal proxyAddress;
    address internal OWNER;
    address internal USER1;
    address internal USER2;

    modifier testTransfer(uint256 amountToTransfer) {
        uint256 prevBalUser1 = usds.balanceOf(USER1);
        uint256 prevBalUser2 = usds.balanceOf(USER2);

        _;
        // @note account for precision error in USDs calculation for rebasing accounts
        assertApproxEqAbs(prevBalUser1 - amountToTransfer, usds.balanceOf(USER1), 1);
        assertApproxEqAbs(prevBalUser2 + amountToTransfer, usds.balanceOf(USER2), 1);
    }

    function setUp() public virtual override {
        super.setUp();
        setArbitrumFork();
        USER1 = actors[0];
        USER2 = actors[1];

        USDsPrecision = 10 ** ERC20(USDS).decimals();

        USDs usdsImpl = new USDs();
        vm.prank(ProxyAdmin(PROXY_ADMIN).owner());
        ProxyAdmin(PROXY_ADMIN).upgrade(ITransparentUpgradeableProxy(USDS), address(usdsImpl));

        vm.startPrank(USDS_OWNER);
        usds = USDs(USDS);
        usds.updateVault(VAULT);
        vm.stopPrank();
    }

    function test_change_vault() public useKnownActor(USDS_OWNER) {
        usds.updateVault(USER1);
        assertEq(USER1, usds.vault());
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

    function test_transfer_from(uint256 amount1) public useKnownActor(USER1) {
        amount1 = bound(amount1, 1, usds.balanceOf(USER1));
        uint256 prevBalUser1 = usds.balanceOf(USER1);
        uint256 prevBalUser2 = usds.balanceOf(USER2);
        usds.approve(VAULT, amount1);

        changePrank(VAULT);
        usds.transferFrom(USER1, USER2, amount1);

        // @note account for precision error in USDs calculation for rebasing accounts
        assertApproxEqAbs(prevBalUser1 - amount1, usds.balanceOf(USER1), 1);
        assertApproxEqAbs(prevBalUser2 + amount1, usds.balanceOf(USER2), 1);
    }

    function test_transfer_from_without_approval() public useKnownActor(VAULT) {
        uint256 amountToTransfer = usds.balanceOf(USER1);

        vm.expectRevert(bytes("Insufficient allowance"));
        usds.transferFrom(USER1, USER2, amountToTransfer);
    }

    function test_revert_balance() public useKnownActor(VAULT) {
        uint256 amountToTransfer = usds.balanceOf(USER1) + 1;

        vm.expectRevert(
            abi.encodeWithSelector(USDs.TransferGreaterThanBal.selector, amountToTransfer, amountToTransfer - 1)
        );
        usds.transferFrom(USER1, USER2, amountToTransfer);
    }

    function test_revert_invalid_input() public useKnownActor(USER1) {
        uint256 amountToTransfer = usds.balanceOf(USER1);

        vm.expectRevert(abi.encodeWithSelector(USDs.TransferToZeroAddr.selector));
        usds.transferFrom(USER1, address(0), amountToTransfer);
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

    function test_allowance() public useKnownActor(USER1) {
        usds.allowance(USER1, VAULT);
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

    function test_transfer(uint256 amount1) public useKnownActor(USER1) {
        amount1 = bound(amount1, 1, usds.balanceOf(USER1));
        uint256 prevBalUser1 = usds.balanceOf(USER1);
        uint256 prevBalUser2 = usds.balanceOf(USER2);

        usds.transfer(USER2, amount1);

        // @note account for precision error in USDs calculation for rebasing accounts
        assertApproxEqAbs(prevBalUser1 - amount1, usds.balanceOf(USER1), 1);
        assertApproxEqAbs(prevBalUser2 + amount1, usds.balanceOf(USER2), 1);
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

    function test_revert_balance() public useKnownActor(USER1) {
        uint256 bal = usds.balanceOf(USER1);
        uint256 amountToTransfer = bal + 1;

        vm.expectRevert(abi.encodeWithSelector(USDs.TransferGreaterThanBal.selector, amountToTransfer, bal));
        usds.transfer(USER2, amountToTransfer);
    }

    function test_revert_invalid_input() public useKnownActor(USER1) {
        uint256 amountToTransfer = usds.balanceOf(USER1);

        vm.expectRevert(abi.encodeWithSelector(USDs.TransferToZeroAddr.selector));
        usds.transfer(address(0), amountToTransfer);
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
        vm.expectRevert(abi.encodeWithSelector(USDs.CallerNotVault.selector, actors[0]));
        usds.mint(USDS_OWNER, amount);
    }

    function test_mint_to_the_zero() public useKnownActor(VAULT) {
        vm.expectRevert(abi.encodeWithSelector(USDs.MintToZeroAddr.selector));
        usds.mint(address(0), amount);
    }

    function test_max_supply() public useKnownActor(VAULT) {
        uint256 MAX_SUPPLY = ~uint128(0);
        vm.expectRevert(abi.encodeWithSelector(USDs.MaxSupplyReached.selector, MAX_SUPPLY + usds.totalSupply()));
        usds.mint(USDS_OWNER, MAX_SUPPLY);
    }

    function test_mint_paused() public useKnownActor(USDS_OWNER) {
        usds.pauseSwitch(true);
        changePrank(VAULT);

        vm.expectRevert(abi.encodeWithSelector(USDs.ContractPaused.selector));
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
        changePrank(VAULT);
        usds.rebaseOptIn();
        usds.rebaseOptOut();

        usds.mint(VAULT, amount);

        uint256 prevSupply = usds.totalSupply();
        uint256 prevNonRebasingSupply = usds.nonRebasingSupply();
        uint256 preBalance = usds.balanceOf(VAULT);

        usds.burn(amount);
        assertEq(usds.totalSupply(), prevSupply - amount);
        assertEq(usds.nonRebasingSupply(), prevNonRebasingSupply - amount);
        assertEq(usds.balanceOf(VAULT), preBalance - amount);
    }

    function test_credit_amount_changes_case1() public useKnownActor(USDS_OWNER) {
        changePrank(VAULT);
        usds.rebaseOptIn();
        usds.mint(VAULT, amount);
        uint256 creditAmount = amount.mulTruncate(usds.rebasingCreditsPerToken());

        (uint256 currentCredits,) = usds.creditsBalanceOf(VAULT);
        usds.burn(amount);

        (uint256 newCredits,) = usds.creditsBalanceOf(VAULT);

        assertEq(newCredits, currentCredits - creditAmount);
    }

    function test_burn_case2() public useKnownActor(USDS_OWNER) {
        changePrank(VAULT);
        usds.rebaseOptIn();

        usds.transfer(USER1, usds.balanceOf(VAULT));
        usds.mint(VAULT, amount);

        uint256 bal = usds.balanceOf(VAULT);
        usds.burn(amount);

        // account for mathematical
        assertApproxEqAbs(amount - bal, usds.balanceOf(VAULT), 1);
    }

    function test_burn_case3() public useKnownActor(USDS_OWNER) {
        changePrank(VAULT);
        usds.rebaseOptIn();

        vm.expectRevert("Insufficient balance");
        amount = 1000000000 * USDsPrecision;
        usds.burn(amount);
    }

    function test_burn() public useKnownActor(VAULT) {
        usds.mint(VAULT, amount);
        uint256 prevSupply = usds.totalSupply();
        usds.burn(amount);
        assertEq(usds.totalSupply(), prevSupply - amount);
    }
}

contract TestRebase is USDsTest {
    function setUp() public override {
        super.setUp();
    }

    function test_revertIf_IsAlreadyRebasingAccount() public useKnownActor(USDS_OWNER) {
        usds.rebaseOptIn();
        vm.expectRevert(abi.encodeWithSelector(USDs.IsAlreadyRebasingAccount.selector, USDS_OWNER));
        usds.rebaseOptIn();
    }

    function test_rebaseOptIn() public useKnownActor(USDS_OWNER) {
        usds.rebaseOptIn();

        assertEq(usds.nonRebasingCreditsPerToken(USDS_OWNER), 0);
    }

    function test_revertIf_IsAlreadyNonRebasingAccount() public useKnownActor(USDS_OWNER) {
        // usds.rebaseOptOut();
        vm.expectRevert(abi.encodeWithSelector(USDs.IsAlreadyNonRebasingAccount.selector, USDS_OWNER));
        usds.rebaseOptOut();
    }

    function test_rebaseOptOut() public useKnownActor(USDS_OWNER) {
        usds.rebaseOptIn();
        usds.rebaseOptOut();

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

    function test_rebase_no_supply_change() public useKnownActor(VAULT) {
        uint256 prevSupply = usds.totalSupply();

        uint256 amount = 0;
        usds.rebase(amount);

        assertEq(prevSupply, usds.totalSupply());
    }

    function test_rebase_opt_in() public useKnownActor(USDS_OWNER) {
        changePrank(VAULT);
        usds.rebaseOptIn();
        uint256 amount = 100000;
        usds.mint(VAULT, amount);
        uint256 prevSupply = usds.totalSupply();
        usds.rebase(amount);
        assertEq(prevSupply, usds.totalSupply());
    }

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
