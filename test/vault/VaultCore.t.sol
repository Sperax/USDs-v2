// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {VaultCore, Helpers} from "../../contracts/vault/VaultCore.sol";
import {PreMigrationSetup} from "../utils/DeploymentSetup.t.sol";
import {IAccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/IAccessControlUpgradeable.sol";
import {IStrategy} from "../../contracts/vault/interfaces/IStrategy.sol";
import {IVault} from "../../contracts/interfaces/IVault.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IOracle} from "../../contracts/interfaces/IOracle.sol";
import {IRebaseManager} from "../../contracts/interfaces/IRebaseManager.sol";
import {IDripper} from "../../contracts/interfaces/IDripper.sol";
import {ICollateralManager} from "../../contracts/vault/interfaces/ICollateralManager.sol";
import {FeeCalculator} from "../../contracts/vault/FeeCalculator.sol";
import {IUSDs} from "../../contracts/interfaces/IUSDs.sol";
import {console} from "forge-std/console.sol";
import {CollateralManager} from "../../contracts/vault/CollateralManager.sol";

contract VaultCoreTest is PreMigrationSetup {
    uint256 internal USDC_PRECISION;
    address internal _collateral;
    address internal defaultStrategy;
    address internal otherStrategy;

    modifier mockOracle(uint256 _price) {
        vm.mockCall(address(ORACLE), abi.encodeWithSignature("getPrice(address)", USDCe), abi.encode(_price, 1e8));
        _;
        vm.clearMockedCalls();
    }

    function setUp() public virtual override {
        super.setUp();
        USDC_PRECISION = 10 ** ERC20(USDCe).decimals();
        _collateral = USDCe;
        defaultStrategy = STARGATE_STRATEGY;
        otherStrategy = AAVE_STRATEGY;
    }

    function _updateCollateralData(ICollateralManager.CollateralBaseData memory _data) internal {
        vm.prank(USDS_OWNER);
        ICollateralManager(COLLATERAL_MANAGER).updateCollateralData(USDCe, _data);
    }

    function _allocateIntoStrategy(address __collateral, address _strategy, uint256 _amount) internal useActor(1) {
        deal(USDCe, VAULT, _amount * 4);
        IVault(VAULT).allocate(__collateral, _strategy, _amount);
    }

    function _redeemViewTest(uint256 _usdsAmt, address _strategyAddr)
        internal
        view
        returns (
            uint256 _calculatedCollateralAmt,
            uint256 _usdsBurnAmt,
            uint256 _feeAmt,
            uint256 _vaultAmt,
            uint256 _strategyAmt
        )
    {
        IStrategy _strategy;
        IOracle.PriceData memory collateralPriceData = IOracle(ORACLE).getPrice(_collateral);
        _feeAmt = FeeCalculator(FEE_CALCULATOR).getRedeemFee(USDCe);
        _usdsBurnAmt = _usdsAmt - _feeAmt;
        _calculatedCollateralAmt = _usdsBurnAmt;
        if (collateralPriceData.price >= collateralPriceData.precision) {
            _calculatedCollateralAmt = (_usdsBurnAmt * collateralPriceData.precision) / collateralPriceData.price;
        }
        _calculatedCollateralAmt = _calculatedCollateralAmt / 1e12;
        _vaultAmt = ERC20(_collateral).balanceOf(VAULT);
        if (_calculatedCollateralAmt > _vaultAmt) {
            _strategyAmt = _calculatedCollateralAmt - _vaultAmt;
            // Withdraw from default strategy
            if (_strategyAddr == address(0)) {
                _strategy = IStrategy(defaultStrategy);
            } else {
                require(
                    ICollateralManager(COLLATERAL_MANAGER).isValidStrategy(_collateral, _strategyAddr),
                    "Invalid strategy"
                );
                _strategy = IStrategy(_strategyAddr);
            }
            // require(
            //     _strategy.checkAvailableBalance(_collateral) >= _strategyAmt,
            //     "Insufficient collateral"
            // );
        } else {
            _vaultAmt = _calculatedCollateralAmt;
        }
    }
}

contract TestInit is VaultCoreTest {
    function test_Initialization() public useKnownActor(USDS_OWNER) {
        address _VAULT;
        // Deploy
        VaultCore vaultImpl = new VaultCore();
        _VAULT = upgradeUtil.deployErc1967Proxy(address(vaultImpl));

        VaultCore vault = VaultCore(_VAULT);
        vault.initialize();
        assertTrue(address(_VAULT) != address(0), "Vault not deployed");
        assertEq(vault.owner(), USDS_OWNER);
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
        vm.expectRevert("Ownable: caller is not the owner");
        IVault(VAULT).updateFeeVault(_newFeeVault);
        vm.expectRevert("Ownable: caller is not the owner");
        IVault(VAULT).updateYieldReceiver(_newYieldReceiver);
        vm.expectRevert("Ownable: caller is not the owner");
        IVault(VAULT).updateCollateralManager(_newCollateralManager);
        vm.expectRevert("Ownable: caller is not the owner");
        IVault(VAULT).updateRebaseManager(_newRebaseManager);
        vm.expectRevert("Ownable: caller is not the owner");
        IVault(VAULT).updateFeeCalculator(_newFeeCalculator);
        vm.expectRevert("Ownable: caller is not the owner");
        IVault(VAULT).updateOracle(_newOracle);
    }

    function test_revertIf_InvalidAddress() public useKnownActor(USDS_OWNER) {
        vm.expectRevert(abi.encodeWithSelector(Helpers.InvalidAddress.selector));
        IVault(VAULT).updateFeeVault(address(0));
        vm.expectRevert(abi.encodeWithSelector(Helpers.InvalidAddress.selector));
        IVault(VAULT).updateYieldReceiver(address(0));
        vm.expectRevert(abi.encodeWithSelector(Helpers.InvalidAddress.selector));
        IVault(VAULT).updateCollateralManager(address(0));
        vm.expectRevert(abi.encodeWithSelector(Helpers.InvalidAddress.selector));
        IVault(VAULT).updateRebaseManager(address(0));
        vm.expectRevert(abi.encodeWithSelector(Helpers.InvalidAddress.selector));
        IVault(VAULT).updateFeeCalculator(address(0));
        vm.expectRevert(abi.encodeWithSelector(Helpers.InvalidAddress.selector));
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
    address private _strategy;
    uint256 private _amount;

    event Allocated(address indexed collateral, address indexed strategy, uint256 amount);

    function setUp() public override {
        super.setUp();
        _collateral = USDCe;
        _strategy = AAVE_STRATEGY;
    }

    function test_revertIf_CollateralAllocationPaused() public useActor(1) {
        // DAI
        _collateral = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;
        vm.expectRevert(abi.encodeWithSelector(CollateralManager.CollateralAllocationPaused.selector));
        IVault(VAULT).allocate(_collateral, _strategy, _amount);
    }

    function test_revertIf_AllocationNotAllowed() public useActor(1) {
        uint16 cap = 3000;
        uint256 maxCollateralUsage = (
            cap
                * (
                    ERC20(_collateral).balanceOf(VAULT)
                        + ICollateralManager(IVault(VAULT).collateralManager()).getCollateralInStrategies(_collateral)
                )
        ) / 10000;

        uint256 _moreThanMaxCollateralUsage = maxCollateralUsage + 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                VaultCore.AllocationNotAllowed.selector, _collateral, _strategy, _moreThanMaxCollateralUsage
            )
        );
        IVault(VAULT).allocate(_collateral, _strategy, _moreThanMaxCollateralUsage);
    }

    function testFuzz_Allocate(uint256 __amount) public useActor(1) {
        __amount = bound(__amount, 0, _possibleAllocation());
        deal(USDCe, VAULT, __amount * 4);
        console.log("Value returned", _possibleAllocation());
        if (__amount > 0) {
            uint256 balBefore = ERC20(_collateral).balanceOf(VAULT);
            vm.expectEmit(true, true, true, true, VAULT);
            emit Allocated(_collateral, _strategy, __amount);
            IVault(VAULT).allocate(_collateral, _strategy, __amount);
            uint256 balAfter = ERC20(_collateral).balanceOf(VAULT);
            assertEq(balBefore - balAfter, __amount);
        }
    }

    function test_Allocate() public useActor(1) {
        _amount = 10000e6;
        deal(USDCe, VAULT, _amount * 4);
        uint256 balBefore = ERC20(_collateral).balanceOf(VAULT);
        vm.expectEmit(true, true, true, true, VAULT);
        emit Allocated(_collateral, _strategy, _amount);
        IVault(VAULT).allocate(_collateral, _strategy, _amount);
        uint256 balAfter = ERC20(_collateral).balanceOf(VAULT);
        assertEq(balBefore - balAfter, _amount);
    }

    function _possibleAllocation() internal view returns (uint256) {
        uint16 cap = 3000;
        uint256 maxCollateralUsage = (
            cap
                * (
                    ERC20(_collateral).balanceOf(VAULT)
                        + ICollateralManager(IVault(VAULT).collateralManager()).getCollateralInStrategies(_collateral)
                )
        ) / 10000;

        uint256 collateralBalance = IStrategy(_strategy).checkBalance(_collateral);
        if (maxCollateralUsage >= collateralBalance) {
            return maxCollateralUsage - collateralBalance;
        }

        return 0;
    }
}

contract TestMint is VaultCoreTest {
    address private minter;
    uint256 private _collateralAmt;
    uint256 private _minUSDSAmt;
    uint256 private _deadline;
    address private feeVault;

    event Minted(
        address indexed wallet, address indexed collateralAddr, uint256 usdsAmt, uint256 collateralAmt, uint256 feeAmt
    );

    function setUp() public override {
        super.setUp();
        minter = actors[1];
        _collateral = USDCe;
        _collateralAmt = 1000 * USDC_PRECISION;
        _deadline = block.timestamp + 300;
        feeVault = makeAddr("FEE_VAULT");
        vm.prank(USDS_OWNER);
        IVault(VAULT).updateFeeVault(feeVault);
    }

    function testFuzz_RevertsIf_DeadlinePassed(uint256 __deadline) public useKnownActor(minter) {
        uint256 _latestDeadline = block.timestamp - 1;
        _deadline = bound(__deadline, 0, _latestDeadline);
        vm.expectRevert(abi.encodeWithSelector(Helpers.CustomError.selector, "Deadline passed"));
        IVault(VAULT).mint(_collateral, _collateralAmt, _minUSDSAmt, _deadline);
    }

    function test_RevertsIf_MintFailed() public useKnownActor(minter) {
        _collateralAmt = 0;
        vm.expectRevert(abi.encodeWithSelector(VaultCore.MintFailed.selector));
        IVault(VAULT).mint(_collateral, _collateralAmt, _minUSDSAmt, _deadline);
    }

    function test_RevertsIf_SlippageScrewsYou() public useKnownActor(minter) {
        (_minUSDSAmt,) = IVault(VAULT).mintView(_collateral, _collateralAmt);
        uint256 _expectedMinAmt = _minUSDSAmt + 10e18;
        vm.expectRevert(abi.encodeWithSelector(Helpers.MinSlippageError.selector, _minUSDSAmt, _expectedMinAmt));
        IVault(VAULT).mint(_collateral, _collateralAmt, _expectedMinAmt, _deadline);
    }

    function test_Mint() public useKnownActor(minter) {
        deal(USDCe, minter, _collateralAmt);
        assertEq(ERC20(USDCe).balanceOf(minter), _collateralAmt);
        assertEq(ERC20(USDS).balanceOf(minter), 0);
        ERC20(USDCe).approve(VAULT, _collateralAmt);
        uint256 feeAmt;
        (_minUSDSAmt, feeAmt) = IVault(VAULT).mintView(_collateral, _collateralAmt);
        vm.expectEmit(true, true, true, true, VAULT);
        emit Minted(minter, USDCe, _minUSDSAmt, _collateralAmt, feeAmt);
        IVault(VAULT).mint(_collateral, _collateralAmt, _minUSDSAmt, _deadline);
        // _minUSDSAmt -= 1; //@todo report precision bug
        assertApproxEqAbs(ERC20(USDS).balanceOf(minter), _minUSDSAmt, 1);
    }

    function test_MintBySpecifyingCollateralAmt() public {
        ICollateralManager.CollateralBaseData memory _data = ICollateralManager.CollateralBaseData({
            mintAllowed: true,
            redeemAllowed: true,
            allocationAllowed: true,
            baseMintFee: 10,
            baseRedeemFee: 500,
            downsidePeg: 9800,
            desiredCollateralComposition: 5000
        });
        _updateCollateralData(_data);
        uint256 _maxSPAburnt = 1e18; // This doesn't have any effect on mint
        deal(USDCe, minter, _collateralAmt);
        assertEq(ERC20(USDCe).balanceOf(minter), _collateralAmt);
        assertEq(ERC20(USDS).balanceOf(minter), 0);
        vm.prank(minter);
        ERC20(USDCe).approve(VAULT, _collateralAmt);
        uint256 feeAmt;
        (_minUSDSAmt, feeAmt) = IVault(VAULT).mintView(_collateral, _collateralAmt);
        vm.expectEmit(true, true, true, true, VAULT);
        emit Minted(minter, USDCe, _minUSDSAmt, _collateralAmt, feeAmt);
        vm.prank(minter);
        IVault(VAULT).mintBySpecifyingCollateralAmt(_collateral, _collateralAmt, _minUSDSAmt, _maxSPAburnt, _deadline);
        assertApproxEqAbs(ERC20(USDS).balanceOf(minter), _minUSDSAmt, 1);
    }
}

contract TestMintView is VaultCoreTest {
    uint256 private _collateralAmt;
    uint256 private _toMinter;
    uint256 private _fee;

    function setUp() public override {
        super.setUp();
        _collateral = USDCe;
        _collateralAmt = 10000 * USDC_PRECISION;
        ICollateralManager.CollateralBaseData memory _data = ICollateralManager.CollateralBaseData({
            mintAllowed: true,
            redeemAllowed: true,
            allocationAllowed: true,
            baseMintFee: 10,
            baseRedeemFee: 500,
            downsidePeg: 9800,
            desiredCollateralComposition: 5000
        });
        _updateCollateralData(_data);
    }

    function test_MintView_Returns0When_PriceLowerThanDownsidePeg() public mockOracle(99e6) {
        ICollateralManager.CollateralBaseData memory _data = ICollateralManager.CollateralBaseData({
            mintAllowed: true,
            redeemAllowed: true,
            allocationAllowed: true,
            baseMintFee: 0,
            baseRedeemFee: 500,
            downsidePeg: 1e4,
            desiredCollateralComposition: 5000
        });
        vm.prank(USDS_OWNER);
        ICollateralManager(COLLATERAL_MANAGER).updateCollateralData(USDCe, _data);
        (_toMinter, _fee) = IVault(VAULT).mintView(_collateral, _collateralAmt);
        assertEq(_toMinter, 0);
        assertEq(_fee, 0);
    }

    function test_MintView_Returns0When_MintIsNotAllowed() public {
        ICollateralManager.CollateralBaseData memory _data = ICollateralManager.CollateralBaseData({
            mintAllowed: false,
            redeemAllowed: true,
            allocationAllowed: true,
            baseMintFee: 0,
            baseRedeemFee: 500,
            downsidePeg: 9800,
            desiredCollateralComposition: 5000
        });
        _updateCollateralData(_data);
        (_toMinter, _fee) = IVault(VAULT).mintView(_collateral, _collateralAmt);
        assertEq(_toMinter, 0);
        assertEq(_fee, 0);
    }

    function test_Fee0If_CallerHasFacilitatorRole() public {
        vm.prank(USDS_OWNER);
        (_toMinter, _fee) = IVault(VAULT).mintView(_collateral, _collateralAmt);
        assertTrue(_toMinter > 98e20);
        assertEq(_fee, 0);
    }

    function test_MintView() public mockOracle(101e6) {
        uint256 expectedFee;
        uint256 expectedToMinter;
        ICollateralManager.CollateralBaseData memory _data = ICollateralManager.CollateralBaseData({
            mintAllowed: true,
            redeemAllowed: true,
            allocationAllowed: true,
            baseMintFee: 450,
            baseRedeemFee: 0,
            downsidePeg: 9800,
            desiredCollateralComposition: 1000
        });
        vm.prank(USDS_OWNER);
        ICollateralManager(COLLATERAL_MANAGER).updateCollateralData(_collateral, _data);
        vm.warp(block.timestamp + 2 days);
        FeeCalculator(FEE_CALCULATOR).calibrateFee(_collateral);
        (_toMinter, _fee) = IVault(VAULT).mintView(_collateral, _collateralAmt);
        ICollateralManager.CollateralMintData memory _mintData =
            ICollateralManager(COLLATERAL_MANAGER).getMintParams(_collateral);
        IOracle.PriceData memory priceData = IOracle(ORACLE).getPrice(_collateral);
        uint256 downsidePeg = (priceData.precision * 9800) / 1e4;
        uint256 feeIn = FeeCalculator(FEE_CALCULATOR).getMintFee(_collateral);
        uint256 normalizedCollateralAmt = _collateralAmt * _mintData.conversionFactor;
        uint256 usdsAmt = normalizedCollateralAmt;
        if (priceData.price < downsidePeg) {
            expectedFee = 0;
            expectedToMinter = 0;
            usdsAmt = (normalizedCollateralAmt * priceData.price) / priceData.precision;
        } else {
            normalizedCollateralAmt = _collateralAmt * _mintData.conversionFactor;
            usdsAmt = normalizedCollateralAmt;
            expectedFee = (usdsAmt * feeIn) / Helpers.MAX_PERCENTAGE;
            expectedToMinter = usdsAmt - expectedFee;
        }
        assertEq(_toMinter, expectedToMinter);
        assertEq(_fee, expectedFee);
        assertTrue(_toMinter != 0);
        assertTrue(_fee != 0);
    }
}

contract TestRebase is VaultCoreTest {
    event RebasedUSDs(uint256 rebaseAmt);

    function test_Rebase() public {
        vm.startPrank(VAULT);
        IRebaseManager(REBASE_MANAGER).fetchRebaseAmt();
        IUSDs(USDS).mint(actors[1], 1e22);
        changePrank(actors[1]);
        ERC20(USDS).approve(DRIPPER, 1e22);
        IDripper(DRIPPER).addUSDs(1e22);
        changePrank(VAULT);
        skip(1 days);
        IDripper(DRIPPER).collect();
        skip(1 days);
        (uint256 min, uint256 max) = IRebaseManager(REBASE_MANAGER).getMinAndMaxRebaseAmt();
        vm.expectEmit(true, true, true, true, VAULT);
        emit RebasedUSDs(max);
        IVault(VAULT).rebase();
        (min, max) = IRebaseManager(REBASE_MANAGER).getMinAndMaxRebaseAmt();
        assertEq(min, 0);
        assertEq(max, 0);
        vm.stopPrank();
    }

    function test_Rebase0Amount() public {
        IVault(VAULT).rebase();
    }
}

contract TestRedeemView is VaultCoreTest {
    address private redeemer;
    uint256 private usdsAmt;

    function setUp() public override {
        super.setUp();
        redeemer = actors[1];
        usdsAmt = 1000e18;
        _collateral = USDCe;
        vm.prank(VAULT);
        IUSDs(USDS).mint(redeemer, usdsAmt);
        ICollateralManager.CollateralBaseData memory _data = ICollateralManager.CollateralBaseData({
            mintAllowed: true,
            redeemAllowed: true,
            allocationAllowed: true,
            baseMintFee: 10,
            baseRedeemFee: 500,
            downsidePeg: 9800,
            desiredCollateralComposition: 5000
        });
        _updateCollateralData(_data);
    }

    function test_RevertsIf_RedeemNotAllowed() public {
        ICollateralManager.CollateralBaseData memory _data = ICollateralManager.CollateralBaseData({
            mintAllowed: true,
            redeemAllowed: false,
            allocationAllowed: true,
            baseMintFee: 10,
            baseRedeemFee: 500,
            downsidePeg: 9800,
            desiredCollateralComposition: 5000
        });
        _updateCollateralData(_data);
        vm.expectRevert(abi.encodeWithSelector(VaultCore.RedemptionPausedForCollateral.selector, _collateral));
        vm.prank(redeemer);
        IVault(VAULT).redeemView(_collateral, usdsAmt);
    }

    function test_RedeemViewFee0IfCallerIsFacilitator() public {
        deal(USDCe, VAULT, (usdsAmt * 2) / 1e12);
        vm.prank(USDS_OWNER);
        (,, uint256 fee,,) = IVault(VAULT).redeemView(_collateral, usdsAmt);
        assertEq(fee, 0);
    }

    function test_RedeemViewFee0AndCollAmtDownsidePegged() public mockOracle(99e6) {
        deal(USDCe, VAULT, (usdsAmt * 2) / 1e12);
        vm.prank(USDS_OWNER);
        (uint256 calculatedCollateralAmt,, uint256 fee,,) = IVault(VAULT).redeemView(_collateral, usdsAmt);
        assertEq(fee, 0);
        assertEq(calculatedCollateralAmt, usdsAmt / 1e12);
    }

    function test_RedeemViewFee0AndCollAmtNotDownsidePegged() public mockOracle(101e4) {
        deal(USDCe, VAULT, (usdsAmt * 2) / 1e12);
        vm.prank(USDS_OWNER);
        (uint256 calculatedCollateralAmt,, uint256 fee,,) = IVault(VAULT).redeemView(_collateral, usdsAmt);
        assertEq(fee, 0);
        assertGe(calculatedCollateralAmt, ((usdsAmt * 1e8) / 101e6) / 1e12);
    }

    function test_RedeemViewApplyDownsidePeg() public mockOracle(101e6) {
        deal(USDCe, VAULT, (usdsAmt * 2) / 1e12);
        (uint256 _calculatedCollateralAmt, uint256 _usdsBurnAmt, uint256 _feeAmt, uint256 _vaultAmt,) =
            _redeemViewTest(usdsAmt, address(0));
        (uint256 calculatedCollateralAmt, uint256 usdsBurnAmt, uint256 feeAmt, uint256 vaultAmt, uint256 strategyAmt) =
            IVault(VAULT).redeemView(_collateral, usdsAmt);
        assertEq(_calculatedCollateralAmt, calculatedCollateralAmt);
        assertEq(_usdsBurnAmt, usdsBurnAmt);
        assertEq(_feeAmt, feeAmt);
        assertEq(_vaultAmt, vaultAmt);
        assertEq(strategyAmt, 0);
    }

    function test_RedeemViewWithoutDownsidePeg() public mockOracle(99e6) {
        deal(USDCe, VAULT, (usdsAmt * 2) / 1e12);
        (uint256 _calculatedCollateralAmt, uint256 _usdsBurnAmt, uint256 _feeAmt, uint256 _vaultAmt,) =
            _redeemViewTest(usdsAmt, address(0));
        (uint256 calculatedCollateralAmt, uint256 usdsBurnAmt, uint256 feeAmt, uint256 vaultAmt, uint256 strategyAmt) =
            IVault(VAULT).redeemView(_collateral, usdsAmt);
        assertEq(_calculatedCollateralAmt, calculatedCollateralAmt);
        assertEq(_usdsBurnAmt, usdsBurnAmt);
        assertEq(_feeAmt, feeAmt);
        assertEq(_vaultAmt, vaultAmt);
        assertEq(strategyAmt, 0);
    }

    function test_RevertsIf_CollateralAmtMoreThanVaultAmtAndDefaultStrategyNotSet() public {
        deal(USDCe, VAULT, (usdsAmt / 2) / 1e12);
        vm.prank(USDS_OWNER);
        ICollateralManager(COLLATERAL_MANAGER).updateCollateralDefaultStrategy(USDCe, address(0));
        (uint256 _calculatedCollateralAmt,,,,) = _redeemViewTest(usdsAmt, defaultStrategy);
        uint256 _availableAmount =
            ERC20(_collateral).balanceOf(VAULT) + IStrategy(defaultStrategy).checkAvailableBalance(_collateral);
        vm.expectRevert(
            abi.encodeWithSelector(
                VaultCore.InsufficientCollateral.selector,
                _collateral,
                address(0),
                _calculatedCollateralAmt,
                _availableAmount
            )
        );
        IVault(VAULT).redeemView(_collateral, usdsAmt);
    }

    function test_RedeemView_WhenDefaultStrategySetButBalanceIsNotAvailable() public {
        deal(USDCe, VAULT, (usdsAmt / 2) / 1e12);
        (uint256 _calculatedCollateralAmt,,,,) = _redeemViewTest(usdsAmt, defaultStrategy);
        uint256 _availableAmount =
            ERC20(_collateral).balanceOf(VAULT) + IStrategy(defaultStrategy).checkAvailableBalance(_collateral);
        vm.expectRevert(
            abi.encodeWithSelector(
                VaultCore.InsufficientCollateral.selector,
                _collateral,
                defaultStrategy,
                _calculatedCollateralAmt,
                _availableAmount
            )
        );
        IVault(VAULT).redeemView(_collateral, usdsAmt, defaultStrategy);
    }

    function test_RedeemView_FromDefaultStrategy() public {
        deal(USDCe, VAULT, (usdsAmt / 2) / 1e12);
        _allocateIntoStrategy(_collateral, defaultStrategy, (usdsAmt / 2) / 1e12);
        (
            uint256 _calculatedCollateralAmt,
            uint256 _usdsBurnAmt,
            uint256 _feeAmt,
            uint256 _vaultAmt,
            uint256 _strategyAmt
        ) = _redeemViewTest(usdsAmt, address(0));
        (uint256 calculatedCollateralAmt, uint256 usdsBurnAmt, uint256 feeAmt, uint256 vaultAmt, uint256 strategyAmt) =
            IVault(VAULT).redeemView(_collateral, usdsAmt);
        assertEq(_calculatedCollateralAmt, calculatedCollateralAmt);
        assertEq(_usdsBurnAmt, usdsBurnAmt);
        assertEq(_feeAmt, feeAmt);
        assertEq(_vaultAmt, vaultAmt);
        assertEq(_strategyAmt, strategyAmt);
    }

    function test_RedeemView_valueLessThanVaultBal() public {
        deal(USDCe, VAULT, (usdsAmt + 100e18) / 1e12);
        (
            uint256 _calculatedCollateralAmt,
            uint256 _usdsBurnAmt,
            uint256 _feeAmt,
            uint256 _vaultAmt,
            uint256 _strategyAmt
        ) = _redeemViewTest(usdsAmt, address(0));
        (uint256 calculatedCollateralAmt, uint256 usdsBurnAmt, uint256 feeAmt,,) =
            IVault(VAULT).redeemView(_collateral, usdsAmt);
        assertEq(_calculatedCollateralAmt, calculatedCollateralAmt);
        assertEq(_usdsBurnAmt, usdsBurnAmt);
        assertEq(_feeAmt, feeAmt);
        assertEq(_vaultAmt, calculatedCollateralAmt);
        assertEq(_strategyAmt, 0);
    }

    function test_RedeemView_RevertsIf_InvalidStrategy() public {
        vm.expectRevert(abi.encodeWithSelector(VaultCore.InvalidStrategy.selector, _collateral, COLLATERAL_MANAGER));
        IVault(VAULT).redeemView(_collateral, usdsAmt, COLLATERAL_MANAGER);
    }

    function test_RedeemView_RevertsIf_InsufficientCollateral() public {
        (uint256 _calculatedCollateralAmt,,,,) = _redeemViewTest(usdsAmt, otherStrategy);
        uint256 _availableAmount =
            ERC20(_collateral).balanceOf(VAULT) + IStrategy(otherStrategy).checkAvailableBalance(_collateral);
        vm.expectRevert(
            abi.encodeWithSelector(
                VaultCore.InsufficientCollateral.selector,
                _collateral,
                otherStrategy,
                _calculatedCollateralAmt,
                _availableAmount
            )
        );
        IVault(VAULT).redeemView(_collateral, usdsAmt, otherStrategy);
    }

    function test_RedeemView_FromOtherStrategy() public {
        deal(USDCe, VAULT, (usdsAmt / 2) / 1e12);
        _allocateIntoStrategy(_collateral, otherStrategy, (usdsAmt / 2) / 1e12);
        (uint256 calculatedCollateralAmt, uint256 usdsBurnAmt, uint256 feeAmt, uint256 vaultAmt, uint256 strategyAmt) =
            IVault(VAULT).redeemView(_collateral, usdsAmt, otherStrategy);
        (
            uint256 _calculatedCollateralAmt,
            uint256 _usdsBurnAmt,
            uint256 _feeAmt,
            uint256 _vaultAmt,
            uint256 _strategyAmt
        ) = _redeemViewTest(usdsAmt, otherStrategy);
        assertEq(_calculatedCollateralAmt, calculatedCollateralAmt);
        assertEq(_usdsBurnAmt, usdsBurnAmt);
        assertEq(_feeAmt, feeAmt);
        assertEq(_vaultAmt, vaultAmt);
        assertEq(_strategyAmt, strategyAmt);
    }
}

contract TestRedeem is VaultCoreTest {
    address private redeemer;
    uint256 private _usdsAmt;
    uint256 private _minCollAmt;
    uint256 private _deadline;

    event Redeemed(
        address indexed wallet, address indexed collateralAddr, uint256 usdsAmt, uint256 collateralAmt, uint256 feeAmt
    );

    function setUp() public override {
        super.setUp();
        redeemer = actors[1];
        _usdsAmt = 1000e18;
        _collateral = USDCe;
        _deadline = block.timestamp + 120;
    }

    function test_RedeemFromVault_RevertsIf_SlippageMoreThanExpected() public useKnownActor(redeemer) {
        deal(_collateral, VAULT, (_usdsAmt * 2) / 1e12);
        (_minCollAmt,,,,) = _redeemViewTest(_usdsAmt, address(0));
        emit log_named_uint("_minCollAmt", _minCollAmt);
        uint256 _expectedCollAmt = _minCollAmt + 10 * USDC_PRECISION;
        vm.expectRevert(abi.encodeWithSelector(Helpers.MinSlippageError.selector, _minCollAmt, _expectedCollAmt));
        IVault(VAULT).redeem(_collateral, _usdsAmt, _expectedCollAmt, _deadline);
    }

    function test_RedeemFromVault() public {
        deal(_collateral, VAULT, (_usdsAmt * 2) / 1e12);
        vm.prank(VAULT);
        IUSDs(USDS).mint(redeemer, _usdsAmt);
        vm.prank(redeemer);
        ERC20(USDS).approve(VAULT, _usdsAmt);
        (uint256 _calculatedCollateralAmt, uint256 _usdsBurnAmt, uint256 _feeAmt,,) =
            _redeemViewTest(_usdsAmt, otherStrategy);
        uint256 balBeforeFeeVault = ERC20(USDS).balanceOf(FEE_VAULT);
        uint256 balBeforeUSDsRedeemer = ERC20(USDS).balanceOf(redeemer);
        uint256 balBeforeUSDCeRedeemer = ERC20(USDCe).balanceOf(redeemer);
        vm.expectEmit(true, true, true, true, VAULT);
        emit Redeemed(redeemer, _collateral, _usdsBurnAmt, _calculatedCollateralAmt, _feeAmt);
        vm.prank(redeemer);
        IVault(VAULT).redeem(_collateral, _usdsAmt, _calculatedCollateralAmt, _deadline);
        uint256 balAfterFeeVault = ERC20(USDS).balanceOf(FEE_VAULT);
        uint256 balAfterUSDsRedeemer = ERC20(USDS).balanceOf(redeemer);
        uint256 balAfterUSDCeRedeemer = ERC20(USDCe).balanceOf(redeemer);
        assertEq(balAfterFeeVault - balBeforeFeeVault, _feeAmt);
        assertEq(balBeforeUSDsRedeemer - balAfterUSDsRedeemer, _usdsAmt);
        assertEq(balAfterUSDCeRedeemer - balBeforeUSDCeRedeemer, _calculatedCollateralAmt);
    }

    function test_RedeemFromDefaultStrategy() public {
        deal(USDCe, VAULT, (_usdsAmt / 2) / 1e12);
        _allocateIntoStrategy(_collateral, defaultStrategy, (_usdsAmt / 2) / 1e12);
        (uint256 _calculatedCollateralAmt, uint256 _usdsBurnAmt, uint256 _feeAmt,,) =
            _redeemViewTest(_usdsAmt, address(0));
        vm.prank(VAULT);
        IUSDs(USDS).mint(redeemer, _usdsAmt);
        vm.prank(redeemer);
        ERC20(USDS).approve(VAULT, _usdsAmt);
        uint256 balBeforeFeeVault = ERC20(USDS).balanceOf(FEE_VAULT);
        uint256 balBeforeUSDsRedeemer = ERC20(USDS).balanceOf(redeemer);
        uint256 balBeforeUSDCeRedeemer = ERC20(USDCe).balanceOf(redeemer);
        vm.expectEmit(true, true, true, true, VAULT);
        emit Redeemed(redeemer, _collateral, _usdsBurnAmt, _calculatedCollateralAmt, _feeAmt);
        vm.prank(redeemer);
        IVault(VAULT).redeem(_collateral, _usdsAmt, _calculatedCollateralAmt, _deadline);
        uint256 balAfterFeeVault = ERC20(USDS).balanceOf(FEE_VAULT);
        uint256 balAfterUSDsRedeemer = ERC20(USDS).balanceOf(redeemer);
        uint256 balAfterUSDCeRedeemer = ERC20(USDCe).balanceOf(redeemer);
        assertEq(balAfterFeeVault - balBeforeFeeVault, _feeAmt);
        assertEq(balBeforeUSDsRedeemer - balAfterUSDsRedeemer, _usdsAmt);
        assertEq(balAfterUSDCeRedeemer - balBeforeUSDCeRedeemer, _calculatedCollateralAmt);
    }

    function test_RedeemFromSpecificOtherStrategy() public {
        deal(USDCe, VAULT, (_usdsAmt / 2) / 1e12);
        _allocateIntoStrategy(_collateral, otherStrategy, (_usdsAmt / 2) / 1e12);
        (uint256 _calculatedCollateralAmt, uint256 _usdsBurnAmt, uint256 _feeAmt,,) =
            _redeemViewTest(_usdsAmt, otherStrategy);
        vm.prank(VAULT);
        IUSDs(USDS).mint(redeemer, _usdsAmt);
        vm.prank(redeemer);
        ERC20(USDS).approve(VAULT, _usdsAmt);
        uint256 balBeforeFeeVault = ERC20(USDS).balanceOf(FEE_VAULT);
        uint256 balBeforeUSDsRedeemer = ERC20(USDS).balanceOf(redeemer);
        uint256 balBeforeUSDCeRedeemer = ERC20(USDCe).balanceOf(redeemer);
        vm.expectEmit(true, true, true, true, VAULT);
        emit Redeemed(redeemer, _collateral, _usdsBurnAmt, _calculatedCollateralAmt, _feeAmt);
        vm.prank(redeemer);
        IVault(VAULT).redeem(_collateral, _usdsAmt, _calculatedCollateralAmt, _deadline, otherStrategy);
        uint256 balAfterFeeVault = ERC20(USDS).balanceOf(FEE_VAULT);
        uint256 balAfterUSDsRedeemer = ERC20(USDS).balanceOf(redeemer);
        uint256 balAfterUSDCeRedeemer = ERC20(USDCe).balanceOf(redeemer);
        assertEq(balAfterFeeVault - balBeforeFeeVault, _feeAmt);
        assertEq(balBeforeUSDsRedeemer - balAfterUSDsRedeemer, _usdsAmt);
        assertEq(balAfterUSDCeRedeemer - balBeforeUSDCeRedeemer, _calculatedCollateralAmt);
    }

    function test_RedeemFromSpecifiedDefaultStrategy() public {
        deal(USDCe, VAULT, (_usdsAmt / 2) / 1e12);
        _allocateIntoStrategy(_collateral, defaultStrategy, (_usdsAmt / 2) / 1e12);
        (uint256 _calculatedCollateralAmt, uint256 _usdsBurnAmt, uint256 _feeAmt,,) =
            _redeemViewTest(_usdsAmt, defaultStrategy);
        vm.prank(VAULT);
        IUSDs(USDS).mint(redeemer, _usdsAmt);
        vm.prank(redeemer);
        ERC20(USDS).approve(VAULT, _usdsAmt);
        uint256 balBeforeFeeVault = ERC20(USDS).balanceOf(FEE_VAULT);
        uint256 balBeforeUSDsRedeemer = ERC20(USDS).balanceOf(redeemer);
        uint256 balBeforeUSDCeRedeemer = ERC20(USDCe).balanceOf(redeemer);
        vm.expectEmit(true, true, true, true, VAULT);
        emit Redeemed(redeemer, _collateral, _usdsBurnAmt, _calculatedCollateralAmt, _feeAmt);
        vm.prank(redeemer);
        IVault(VAULT).redeem(_collateral, _usdsAmt, _calculatedCollateralAmt, _deadline, defaultStrategy);
        uint256 balAfterFeeVault = ERC20(USDS).balanceOf(FEE_VAULT);
        uint256 balAfterUSDsRedeemer = ERC20(USDS).balanceOf(redeemer);
        uint256 balAfterUSDCeRedeemer = ERC20(USDCe).balanceOf(redeemer);
        assertEq(balAfterFeeVault - balBeforeFeeVault, _feeAmt);
        assertEq(balBeforeUSDsRedeemer - balAfterUSDsRedeemer, _usdsAmt);
        assertEq(balAfterUSDCeRedeemer - balBeforeUSDCeRedeemer, _calculatedCollateralAmt);
    }
}
