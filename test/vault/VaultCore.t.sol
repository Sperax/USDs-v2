// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {PreMigrationSetup} from "../utils/DeploymentSetup.sol";
import {IAccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/IAccessControlUpgradeable.sol";
import {IVault} from "../../contracts/interfaces/IVault.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract VaultCoreTest is PreMigrationSetup {
    function setUp() public virtual override {
        super.setUp();
    }
}

contract TestInit is VaultCoreTest {
    function test_Initialization() public {
        assertTrue(address(VAULT) != address(0), "Vault not deployed");
        assertTrue(IAccessControlUpgradeable(VAULT).hasRole(0x00, USDS_OWNER));
    }
}

contract TestSetters is VaultCoreTest {
    address private _newFeeVault;
    address private _newYieldReceiver;
    address private _newCollateralManager;
    address private _newRebaseManager;
    address private _newFeeCalculator;
    address private _newOracle;

    event FeeVaultUpdated(address newFeeVault);
    event YieldReceiverUpdated(address newYieldReceiver);
    event CollateralManagerUpdated(address newCollateralManager);
    event FeeCalculatorUpdated(address newFeeCalculator);
    event RebaseManagerUpdated(address newRebaseManager);
    event OracleUpdated(address newOracle);

    function setUp() public override {
        super.setUp();
        _newFeeVault = makeAddr("_newFeeVault");
        _newYieldReceiver = makeAddr("_newYieldReceiver");
        _newCollateralManager = makeAddr("_newCollateralManager");
        _newRebaseManager = makeAddr("_newRebaseManager");
        _newFeeCalculator = makeAddr("_newFeeCalculator");
        _newOracle = makeAddr("_newOracle");
    }

    function test_revertIf_callerIsNotOwner() public useActor(1) {
        vm.expectRevert("Unauthorized caller");
        IVault(VAULT).updateFeeVault(_newFeeVault);
        vm.expectRevert("Unauthorized caller");
        IVault(VAULT).updateYieldReceiver(_newYieldReceiver);
        vm.expectRevert("Unauthorized caller");
        IVault(VAULT).updateCollateralManager(_newCollateralManager);
        vm.expectRevert("Unauthorized caller");
        IVault(VAULT).updateRebaseManager(_newRebaseManager);
        vm.expectRevert("Unauthorized caller");
        IVault(VAULT).updateFeeCalculator(_newFeeCalculator);
        vm.expectRevert("Unauthorized caller");
        IVault(VAULT).updateOracle(_newOracle);
    }

    function test_revertIf_InvalidAddress() public useKnownActor(USDS_OWNER) {
        vm.expectRevert("Zero address");
        IVault(VAULT).updateFeeVault(address(0));
        vm.expectRevert("Zero address");
        IVault(VAULT).updateYieldReceiver(address(0));
        vm.expectRevert("Zero address");
        IVault(VAULT).updateCollateralManager(address(0));
        vm.expectRevert("Zero address");
        IVault(VAULT).updateRebaseManager(address(0));
        vm.expectRevert("Zero address");
        IVault(VAULT).updateFeeCalculator(address(0));
        vm.expectRevert("Zero address");
        IVault(VAULT).updateOracle(address(0));
    }

    function test_updateFeeVault() public useKnownActor(USDS_OWNER) {
        vm.expectEmit(true, true, true, true, VAULT);
        emit FeeVaultUpdated(_newFeeVault);
        IVault(VAULT).updateFeeVault(_newFeeVault);
        assertEq(_newFeeVault, IVault(VAULT).feeVault());
    }

    function test_updateYieldReceiver() public useKnownActor(USDS_OWNER) {
        vm.expectEmit(true, true, true, true, VAULT);
        emit YieldReceiverUpdated(_newYieldReceiver);
        IVault(VAULT).updateYieldReceiver(_newYieldReceiver);
        assertEq(_newYieldReceiver, IVault(VAULT).yieldReceiver());
    }

    function test_updateCollateralManager() public useKnownActor(USDS_OWNER) {
        vm.expectEmit(true, true, true, true, VAULT);
        emit CollateralManagerUpdated(_newCollateralManager);
        IVault(VAULT).updateCollateralManager(_newCollateralManager);
        assertEq(_newCollateralManager, IVault(VAULT).collateralManager());
    }

    function test_updateRebaseManager() public useKnownActor(USDS_OWNER) {
        vm.expectEmit(true, true, true, true, VAULT);
        emit RebaseManagerUpdated(_newRebaseManager);
        IVault(VAULT).updateRebaseManager(_newRebaseManager);
        assertEq(_newRebaseManager, IVault(VAULT).rebaseManager());
    }

    function test_updateFeeCalculator() public useKnownActor(USDS_OWNER) {
        vm.expectEmit(true, true, true, true, VAULT);
        emit FeeCalculatorUpdated(_newFeeCalculator);
        IVault(VAULT).updateFeeCalculator(_newFeeCalculator);
        assertEq(_newFeeCalculator, IVault(VAULT).feeCalculator());
    }

    function test_updateOracle() public useKnownActor(USDS_OWNER) {
        vm.expectEmit(true, true, true, true, VAULT);
        emit OracleUpdated(_newOracle);
        IVault(VAULT).updateOracle(_newOracle);
        assertEq(_newOracle, IVault(VAULT).oracle());
    }
}

contract TestAllocate is VaultCoreTest {
    address private allocator;
    address private _collateral;
    address private _strategy;
    uint256 private _amount;

    function setUp() public override {
        super.setUp();
        allocator = actors[2];
        _collateral = USDCe;
        _strategy = STARGATE;
        vm.prank(USDS_OWNER);
        IAccessControlUpgradeable(VAULT).grantRole(
            keccak256("ALLOCATOR_ROLE"),
            allocator
        );
    }

    function test_revertIf_CallerIsNowAllocator() public useActor(1) {
        vm.expectRevert("Unauthorized caller");
        IVault(VAULT).allocate(_collateral, _strategy, _amount);
    }

    function test_revertIf_AllocationNotAllowed()
        public
        useKnownActor(allocator)
    {
        // DAI
        _collateral = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;
        vm.expectRevert("Allocation not allowed");
        IVault(VAULT).allocate(_collateral, _strategy, _amount);
    }

    // function test_Allocate() public useKnownActor(allocator) {
    //     _amount = 10000e18;
    //     deal(USDCe, VAULT, _amount);
    //     IVault(VAULT).allocate(_collateral, _strategy, _amount);
    // }
}

contract TestMint is VaultCoreTest {
    address private minter;
    address private _collateral;
    uint256 private _collateralAmt;
    uint256 private _minUSDSAmt;
    uint256 private _deadline;

    event Minted(
        address indexed wallet,
        address indexed collateralAddr,
        uint256 usdsAmt,
        uint256 collateralAmt,
        uint256 feeAmt
    );

    function setUp() public override {
        super.setUp();
        minter = actors[1];
        _collateral = USDCe;
        _collateralAmt = 1000e18;
        _deadline = block.timestamp + 300;
    }

    function testFuzz_RevertsIf_DeadlinePassed(
        uint256 __deadline
    ) public useKnownActor(minter) {
        uint256 _latestDeadline = block.timestamp - 1;
        _deadline = bound(__deadline, 0, _latestDeadline);
        vm.expectRevert("Deadline passed");
        IVault(VAULT).mint(_collateral, _collateralAmt, _minUSDSAmt, _deadline);
    }

    function test_RevertsIf_MintFailed() public useKnownActor(minter) {
        _collateralAmt = 0;
        vm.expectRevert("Mint failed");
        IVault(VAULT).mint(_collateral, _collateralAmt, _minUSDSAmt, _deadline);
    }

    function test_RevertsIf_SlippageScrewsYou() public useKnownActor(minter) {
        _minUSDSAmt = 1100e18;
        vm.expectRevert("Slippage screwed you");
        IVault(VAULT).mint(_collateral, _collateralAmt, _minUSDSAmt, _deadline);
    }

    function test_Mint() public useKnownActor(minter) {
        deal(USDCe, minter, _collateralAmt);
        assertEq(ERC20(USDCe).balanceOf(minter), _collateralAmt);
        assertEq(ERC20(USDS).balanceOf(minter), 0);
        ERC20(USDCe).approve(VAULT, _collateralAmt);
        uint256 feeAmt;
        (_minUSDSAmt, feeAmt) = IVault(VAULT).mintView(
            _collateral,
            _collateralAmt
        );
        vm.expectEmit(true, true, true, true, VAULT);
        emit Minted(minter, USDCe, _minUSDSAmt, _collateralAmt, feeAmt);
        IVault(VAULT).mint(_collateral, _collateralAmt, _minUSDSAmt, _deadline);
        assertGe(ERC20(USDS).balanceOf(minter), _minUSDSAmt);
    }

    function test_MintBySpecifyingCollateralAmt() public useKnownActor(minter) {
        uint256 _maxSPAburnt = 1e18; // This doesn't have any effect on mint
        deal(USDCe, minter, _collateralAmt);
        assertEq(ERC20(USDCe).balanceOf(minter), _collateralAmt);
        assertEq(ERC20(USDS).balanceOf(minter), 0);
        ERC20(USDCe).approve(VAULT, _collateralAmt);
        uint256 feeAmt;
        (_minUSDSAmt, feeAmt) = IVault(VAULT).mintView(
            _collateral,
            _collateralAmt
        );
        vm.expectEmit(true, true, true, true, VAULT);
        emit Minted(minter, USDCe, _minUSDSAmt, _collateralAmt, feeAmt);
        IVault(VAULT).mintBySpecifyingCollateralAmt(
            _collateral,
            _collateralAmt,
            _minUSDSAmt,
            _maxSPAburnt,
            _deadline
        );
        assertGe(ERC20(USDS).balanceOf(minter), _minUSDSAmt);
    }
}
