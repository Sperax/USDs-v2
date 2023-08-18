// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {VaultCore} from "../../contracts/vault/VaultCore.sol";
import {PreMigrationSetup} from "../utils/DeploymentSetup.sol";
import {IAccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/IAccessControlUpgradeable.sol";
import {IStrategy} from "../../contracts/vault/interfaces/IStrategy.sol";
import {IVault} from "../../contracts/interfaces/IVault.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IOracle} from "../../contracts/interfaces/IOracle.sol";
import {IRebaseManager} from "../../contracts/interfaces/IRebaseManager.sol";
import {IDripper} from "../../contracts/interfaces/IDripper.sol";
import {ICollateralManager} from "../../contracts/vault/interfaces/ICollateralManager.sol";
import {IFeeCalculator} from "../../contracts/vault/interfaces/IFeeCalculator.sol";
import {IUSDs} from "../../contracts/interfaces/IUSDs.sol";
import {console} from "forge-std/console.sol";

contract VaultCoreTest is PreMigrationSetup {
    uint256 internal USDC_PRECISION;
    address internal _collateral;
    address internal allocator;
    address internal defaultStrategy;
    address internal otherStrategy;

    modifier mockOracle(uint256 _price) {
        vm.mockCall(
            address(ORACLE),
            abi.encodeWithSignature("getPrice(address)", USDCe),
            abi.encode(_price, 1e8)
        );
        _;
        vm.clearMockedCalls();
    }

    function setUp() public virtual override {
        super.setUp();
        USDC_PRECISION = 10 ** ERC20(USDCe).decimals();
        _collateral = USDCe;
        allocator = actors[2];
        vm.prank(USDS_OWNER);
        IAccessControlUpgradeable(VAULT).grantRole(
            keccak256("ALLOCATOR_ROLE"),
            allocator
        );
        defaultStrategy = STARGATE_STRATEGY;
        otherStrategy = AAVE_STRATEGY;
    }

    function _updateCollateralData(
        ICollateralManager.CollateralBaseData memory _data
    ) internal {
        vm.prank(USDS_OWNER);
        ICollateralManager(COLLATERAL_MANAGER).updateCollateralData(
            USDCe,
            _data
        );
    }

    function _allocateIntoStrategy(
        address _collateral,
        address _strategy,
        uint256 _amount
    ) internal useKnownActor(allocator) {
        deal(USDCe, VAULT, _amount * 4);
        IVault(VAULT).allocate(_collateral, _strategy, _amount);
    }

    function _redeemViewTest(
        uint256 _usdsAmt,
        address _strategyAddr
    )
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
        IOracle.PriceData memory collateralPriceData = IOracle(ORACLE).getPrice(
            _collateral
        );
        _feeAmt = (_usdsAmt * 500) / 1e4; // feePerc = 500 and feePercPrecision = 1e4
        _usdsBurnAmt = _usdsAmt - _feeAmt;
        _calculatedCollateralAmt = _usdsBurnAmt;
        if (collateralPriceData.price >= collateralPriceData.precision) {
            _calculatedCollateralAmt =
                (_usdsBurnAmt * collateralPriceData.precision) /
                collateralPriceData.price;
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
                    ICollateralManager(COLLATERAL_MANAGER).isValidStrategy(
                        _collateral,
                        _strategyAddr
                    ),
                    "Invalid strategy"
                );
                _strategy = IStrategy(_strategyAddr);
            }
            require(
                _strategy.checkAvailableBalance(_collateral) >= _strategyAmt,
                "Insufficient collateral"
            );
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
        assertTrue(IAccessControlUpgradeable(_VAULT).hasRole(0x00, USDS_OWNER));
    }
}

contract TestAllocate is VaultCoreTest {
    address private _strategy;
    uint256 private _amount;

    event Deposit(address indexed asset, address pToken, uint256 amount);

    event Allocated(
        address indexed collateral,
        address indexed strategy,
        uint256 amount
    );

    function setUp() public override {
        super.setUp();
        _collateral = USDCe;
        _strategy = AAVE_STRATEGY;
    }

    function testFuzz_Allocate(
        uint256 __amount
    ) public useKnownActor(allocator) {
        __amount = bound(__amount, 0, _possibleAllocation());
        deal(USDCe, VAULT, __amount * 4);
        console.log("Value returned", _possibleAllocation());
        if (__amount > 0) {
            uint256 balBefore = ERC20(_collateral).balanceOf(VAULT);
            uint256 strategyBalBefore = IStrategy(_strategy).checkBalance(
                _collateral
            );
            uint256 strategyAvailableBalBefore = IStrategy(_strategy)
                .checkAvailableBalance(_collateral);
            address pToken = 0x625E7708f30cA75bfd92586e17077590C60eb4cD;
            vm.expectEmit(true, true, true, true, address(_strategy));
            emit Deposit(_collateral, pToken, _amount);
            vm.expectEmit(true, true, true, true, VAULT);
            emit Allocated(_collateral, _strategy, __amount);
            IVault(VAULT).allocate(_collateral, _strategy, __amount);
            uint256 balAfter = ERC20(_collateral).balanceOf(VAULT);
            uint256 strategyBalAfter = IStrategy(_strategy).checkBalance(
                _collateral
            );
            uint256 strategyAvailableBalAfter = IStrategy(_strategy)
                .checkAvailableBalance(_collateral);
            assertEq(balBefore - balAfter, __amount);
            assertEq(strategyBalAfter - strategyBalBefore, _amount);
            assertLe(
                strategyAvailableBalAfter - strategyAvailableBalBefore,
                _amount
            );
        }
    }

    function _possibleAllocation() internal view returns (uint256) {
        uint16 cap = 3000;
        uint256 maxCollateralUsage = (cap *
            (ERC20(_collateral).balanceOf(VAULT) +
                ICollateralManager(IVault(VAULT).collateralManager())
                    .getCollateralInStrategies(_collateral))) / 10000;

        uint256 collateralBalance = IStrategy(_strategy).checkBalance(
            _collateral
        );
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

    event Transfer(address from, address to, uint256 amount);
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
        _collateralAmt = 1000 * USDC_PRECISION;
        _deadline = block.timestamp + 300;
        feeVault = makeAddr("FEE_VAULT");
        vm.prank(USDS_OWNER);
        IVault(VAULT).updateFeeVault(feeVault);
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
        uint256 feeVaultBalBefore = ERC20(USDS).balanceOf(FEE_VAULT);
        uint256 totalSupplyBefore = ERC20(USDS).totalSupply();
        vm.expectEmit(true, true, true, true, VAULT);
        emit Minted(minter, USDCe, _minUSDSAmt, _collateralAmt, feeAmt);
        IVault(VAULT).mint(_collateral, _collateralAmt, _minUSDSAmt, _deadline);
        uint256 totalSupplyAfter = ERC20(USDS).totalSupply();
        uint256 feeVaultBalAfter = ERC20(USDS).balanceOf(FEE_VAULT);
        assertEq(totalSupplyAfter - totalSupplyBefore, _minUSDSAmt + feeAmt);
        assertEq(feeVaultBalAfter - feeVaultBalBefore, feeAmt);
        assertGe(ERC20(USDS).balanceOf(minter), _minUSDSAmt);
    }
}

contract TestRebase is VaultCoreTest {
    event RebasedUSDs(uint256 rebaseAmt);

    function test_Rebase() public useKnownActor(VAULT) {
        IRebaseManager(REBASE_MANAGER).fetchRebaseAmt();
        skip(1 days);
        IUSDs(USDS).mint(DRIPPER, 1e22);
        IDripper(DRIPPER).collect();
        skip(1 days);
        (uint256 min, uint256 max) = IRebaseManager(REBASE_MANAGER)
            .getMinAndMaxRebaseAmt();
        vm.expectEmit(true, true, true, true, VAULT);
        emit RebasedUSDs(max);
        uint256 prevSupply = ERC20(USDS).totalSupply();
        IVault(VAULT).rebase();
        (min, max) = IRebaseManager(REBASE_MANAGER).getMinAndMaxRebaseAmt();
        assertEq(min, 0);
        assertEq(max, 0);
        assertEq(prevSupply, ERC20(USDS).totalSupply());
    }
}

contract TestRedeem is VaultCoreTest {
    address private redeemer;
    uint256 private _usdsAmt;
    uint256 private _minCollAmt;
    uint256 private _deadline;

    event Redeemed(
        address indexed wallet,
        address indexed collateralAddr,
        uint256 usdsAmt,
        uint256 collateralAmt,
        uint256 feeAmt
    );

    function setUp() public override {
        super.setUp();
        redeemer = actors[1];
        _usdsAmt = 1000e18;
        _collateral = USDCe;
        _deadline = block.timestamp + 120;
    }

    function test_RedeemFromDefaultStrategy() public {
        deal(USDCe, VAULT, (_usdsAmt / 2) / 1e12);
        _allocateIntoStrategy(
            _collateral,
            defaultStrategy,
            (_usdsAmt / 2) / 1e12
        );
        (
            uint256 _calculatedCollateralAmt,
            uint256 _usdsBurnAmt,
            uint256 _feeAmt,
            uint256 _vaultAmt,
            uint256 _strategyAmt
        ) = _redeemViewTest(_usdsAmt, address(0));
        vm.prank(VAULT);
        IUSDs(USDS).mint(redeemer, _usdsAmt);
        vm.prank(redeemer);
        ERC20(USDS).approve(VAULT, _usdsAmt);
        uint256 balBeforeFeeVault = ERC20(USDS).balanceOf(FEE_VAULT);
        uint256 balBeforeUSDsRedeemer = ERC20(USDS).balanceOf(redeemer);
        uint256 balBeforeUSDCeRedeemer = ERC20(USDCe).balanceOf(redeemer);
        uint256 balBeforeStrategy = IStrategy(defaultStrategy).checkBalance(
            _collateral
        );
        vm.expectEmit(true, true, true, true, VAULT);
        emit Redeemed(
            redeemer,
            _collateral,
            _usdsBurnAmt,
            _calculatedCollateralAmt,
            _feeAmt
        );
        vm.prank(redeemer);
        IVault(VAULT).redeem(
            _collateral,
            _usdsAmt,
            _calculatedCollateralAmt,
            _deadline
        );
        uint256 balAfterFeeVault = ERC20(USDS).balanceOf(FEE_VAULT);
        uint256 balAfterUSDsRedeemer = ERC20(USDS).balanceOf(redeemer);
        uint256 balAfterUSDCeRedeemer = ERC20(USDCe).balanceOf(redeemer);
        uint256 balAfterStrategy = IStrategy(defaultStrategy).checkBalance(
            _collateral
        );
        assertEq(balAfterFeeVault - balBeforeFeeVault, _feeAmt);
        assertEq(balBeforeUSDsRedeemer - balAfterUSDsRedeemer, _usdsAmt);
        assertEq(
            balAfterUSDCeRedeemer - balBeforeUSDCeRedeemer,
            _calculatedCollateralAmt
        );
        assertEq(balBeforeStrategy - balAfterStrategy, _strategyAmt);
    }
}
