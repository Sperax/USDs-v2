// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {PreMigrationSetup} from "../utils/DeploymentSetup.sol";
import {BaseStrategy} from "./BaseStrategy.t.sol";
import {CamelotStrategy} from "../../contracts/strategies/camelot/CamelotStrategy.sol";
import {IRouter, INFTPool} from "../../contracts/strategies/camelot/interfaces/ICamelot.sol";
import {InitializableAbstractStrategy, Helpers} from "../../contracts/strategies/InitializableAbstractStrategy.sol";
import {IERC20, ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract CamelotStrategyTestSetup is PreMigrationSetup, BaseStrategy {
    CamelotStrategy internal camelotStrategy;
    address internal ASSET_A = USDT;
    address internal ASSET_B = USDCe;

    function setUp() public virtual override {
        super.setUp();
        CamelotStrategy.StrategyData memory _sData = CamelotStrategy.StrategyData({
            tokenA: ASSET_A,
            tokenB: ASSET_B,
            router: 0xc873fEcbd354f5A56E00E710B90EF4201db2448d,
            positionHelper: 0xe458018Ad4283C90fB7F5460e24C4016F81b8175,
            factory: 0x6EcCab422D763aC031210895C81787E87B43A652,
            nftPool: 0xcC9f28dAD9b85117AB5237df63A5EE6fC50B02B7
        });
        vm.startPrank(USDS_OWNER);
        CamelotStrategy camelotStrategyImpl = new CamelotStrategy();
        address camelotStrategyProxy = upgradeUtil.deployErc1967Proxy(address(camelotStrategyImpl));
        camelotStrategy = CamelotStrategy(camelotStrategyProxy);
        camelotStrategy.initialize(_sData, VAULT, 100, 100);
        vm.stopPrank();
    }
}

contract TestInitialization is CamelotStrategyTestSetup {
    CamelotStrategy private camelotStrategy2;
    CamelotStrategy private camelotStrategyImpl2;

    function setUp() public override {
        super.setUp();
        vm.startPrank(USDS_OWNER);
        camelotStrategyImpl2 = new CamelotStrategy();
        address camelotStrategyProxy2 = upgradeUtil.deployErc1967Proxy(address(camelotStrategyImpl2));
        camelotStrategy2 = CamelotStrategy(camelotStrategyProxy2);
        vm.stopPrank();
    }

    function initializeStrategy() private useKnownActor(USDS_OWNER) {
        CamelotStrategy.StrategyData memory _sData = CamelotStrategy.StrategyData({
            tokenA: ASSET_A,
            tokenB: ASSET_B,
            router: 0xc873fEcbd354f5A56E00E710B90EF4201db2448d,
            positionHelper: 0xe458018Ad4283C90fB7F5460e24C4016F81b8175,
            factory: 0x6EcCab422D763aC031210895C81787E87B43A652,
            nftPool: 0xcC9f28dAD9b85117AB5237df63A5EE6fC50B02B7
        });
        camelotStrategy2.initialize(_sData, VAULT, 100, 100);
    }

    function testImplementationInitialization() public {
        initializeStrategy();
        assertTrue(camelotStrategyImpl2.vault() == address(0));
        assertTrue(camelotStrategyImpl2.withdrawSlippage() == 0);
        assertTrue(camelotStrategyImpl2.depositSlippage() == 0);
        assertTrue(camelotStrategyImpl2.owner() == address(0));
    }

    function testInitialization() public {
        initializeStrategy();
        assertTrue(camelotStrategy2.vault() == VAULT);
        assertTrue(camelotStrategy2.withdrawSlippage() == 100);
        assertTrue(camelotStrategy2.depositSlippage() == 100);
        assertTrue(camelotStrategy2.owner() == USDS_OWNER);
        assertTrue(camelotStrategy2.supportsCollateral(ASSET_B));
        assertTrue(camelotStrategy2.supportsCollateral(ASSET_A));
    }

    function testInitializationTwice() public {
        initializeStrategy();
        CamelotStrategy.StrategyData memory _sData = CamelotStrategy.StrategyData({
            tokenA: ASSET_A,
            tokenB: ASSET_B,
            router: 0xc873fEcbd354f5A56E00E710B90EF4201db2448d,
            positionHelper: 0xe458018Ad4283C90fB7F5460e24C4016F81b8175,
            factory: 0x6EcCab422D763aC031210895C81787E87B43A652,
            nftPool: 0xcC9f28dAD9b85117AB5237df63A5EE6fC50B02B7
        });
        vm.expectRevert("Initializable: contract is already initialized");
        vm.prank(USDS_OWNER);
        camelotStrategy2.initialize(_sData, VAULT, 100, 100);
    }
}

contract DepositTest is CamelotStrategyTestSetup {
    function _depositAssetsToStrategy(uint256 amountA, uint256 amountB) internal {
        uint256 depositAmountAssetA = amountA;
        uint256 depositAmountAssetB = amountB;

        vm.startPrank(VAULT);

        deal(address(ASSET_A), VAULT, depositAmountAssetA);
        deal(address(ASSET_B), VAULT, depositAmountAssetB);

        IERC20(ASSET_A).approve(address(camelotStrategy), depositAmountAssetA);
        IERC20(ASSET_B).approve(address(camelotStrategy), depositAmountAssetB);

        vm.expectEmit(true, false, false, true, address(camelotStrategy));
        emit Deposit(ASSET_A, depositAmountAssetA);

        camelotStrategy.deposit(ASSET_A, depositAmountAssetA);

        vm.expectEmit(true, false, false, true, address(camelotStrategy));
        emit Deposit(ASSET_B, depositAmountAssetB);

        camelotStrategy.deposit(ASSET_B, depositAmountAssetB);

        vm.stopPrank();
    }

    function test_Deposit_Assets_To_Strategy() public {
        uint256 depositAmountAssetA = 1000 * 10 ** ERC20(ASSET_A).decimals();
        uint256 depositAmountAssetB = 1000 * 10 ** ERC20(ASSET_B).decimals();

        uint256 currentAmountAssetA = IERC20(ASSET_A).balanceOf(address(camelotStrategy));
        uint256 currentAmountAssetB = IERC20(ASSET_B).balanceOf(address(camelotStrategy));

        _depositAssetsToStrategy(depositAmountAssetA, depositAmountAssetB);

        assert(IERC20(ASSET_A).balanceOf(address(camelotStrategy)) == currentAmountAssetA + depositAmountAssetA);
        assert(IERC20(ASSET_B).balanceOf(address(camelotStrategy)) == currentAmountAssetB + depositAmountAssetB);
    }
}

contract AllocationTest is DepositTest {
    event IncreaseLiquidity(uint256 liquidity, uint256 amountA, uint256 amountB);

    error InvalidAmount();

    function test_Revert_When_Amount_Zero() public {
        vm.startPrank(USDS_OWNER);

        vm.expectRevert(InvalidAmount.selector);
        camelotStrategy.allocate([uint256(0), uint256(0)]);

        vm.expectRevert(InvalidAmount.selector);
        camelotStrategy.allocate([uint256(1000), uint256(0)]);

        vm.expectRevert(InvalidAmount.selector);
        camelotStrategy.allocate([uint256(0), uint256(1000)]);

        vm.stopPrank();
    }

    function test_First_Allocation() public {
        uint256 depositAmountAssetA = 1000 * 10 ** ERC20(ASSET_A).decimals();
        uint256 depositAmountAssetB = 1000 * 10 ** ERC20(ASSET_B).decimals();
        _depositAssetsToStrategy(depositAmountAssetA, depositAmountAssetB);

        (address _tokenA, address _tokenB, address _router,,, address _nftPool) = camelotStrategy.strategyData();

        uint256 amountAllocationAssetA = 1000 * 10 ** ERC20(ASSET_A).decimals();
        uint256 amountAllocationAssetB = 1000 * 10 ** ERC20(ASSET_B).decimals();

        address pair = IRouter(_router).getPair(_tokenA, _tokenB);

        (amountAllocationAssetA, amountAllocationAssetB) =
            camelotStrategy.getDepositAmounts(amountAllocationAssetA, amountAllocationAssetB);

        uint256 numOfSpNFTsBeforeAllocation = IERC721(_nftPool).balanceOf(address(camelotStrategy));
        uint256 amountAllocatedBeforeAllocation = camelotStrategy.allocatedAmount();

        vm.prank(USDS_OWNER);
        camelotStrategy.allocate([uint256(amountAllocationAssetA), uint256(amountAllocationAssetB)]);
        vm.stopPrank();

        uint256 spNFTId = camelotStrategy.spNFTId();
        (uint256 liquidityBalance,,,,,,,) = INFTPool(_nftPool).getStakingPosition(spNFTId);

        uint256 numOfSpNFTsAfterAllocation = IERC721(_nftPool).balanceOf(address(camelotStrategy));
        uint256 amountAllocatedAfterAllocation = camelotStrategy.allocatedAmount();

        assertEq(numOfSpNFTsBeforeAllocation + 1, numOfSpNFTsAfterAllocation);
        assertEq(IERC20(pair).balanceOf(address(camelotStrategy)), 0);
        assert(amountAllocatedAfterAllocation > amountAllocatedBeforeAllocation);
        assertEq(liquidityBalance, amountAllocatedAfterAllocation);
    }

    function test_Multiple_Allocations() public {
        test_First_Allocation(); // Added this to maintain state for multiple allocations.

        uint256 depositAmountAssetA = 100 * 10 ** ERC20(ASSET_A).decimals();
        uint256 depositAmountAssetB = 100 * 10 ** ERC20(ASSET_B).decimals();
        _depositAssetsToStrategy(depositAmountAssetA, depositAmountAssetB);

        (address _tokenA, address _tokenB, address _router,,, address _nftPool) = camelotStrategy.strategyData();

        uint256 amountAllocationAssetA = 10 * 10 ** ERC20(ASSET_A).decimals();
        uint256 amountAllocationAssetB = 10 * 10 ** ERC20(ASSET_B).decimals();
        address pair = IRouter(_router).getPair(_tokenA, _tokenB);
        uint256 spNFTId = camelotStrategy.spNFTId();

        (amountAllocationAssetA, amountAllocationAssetB) =
            camelotStrategy.getDepositAmounts(amountAllocationAssetA, amountAllocationAssetB);

        uint256 amountAllocatedBeforeIncreaseAllocation = camelotStrategy.allocatedAmount();

        vm.prank(USDS_OWNER);
        camelotStrategy.allocate([uint256(amountAllocationAssetA), uint256(amountAllocationAssetB)]);
        vm.stopPrank();

        uint256 amountAllocatedAfterIncreaseAllocation = camelotStrategy.allocatedAmount();

        (uint256 liquidityBalance,,,,,,,) = INFTPool(_nftPool).getStakingPosition(spNFTId);

        assert(amountAllocatedAfterIncreaseAllocation > amountAllocatedBeforeIncreaseAllocation);
        assertEq(IERC20(pair).balanceOf(address(camelotStrategy)), 0);
        assertEq(liquidityBalance, amountAllocatedAfterIncreaseAllocation);
    }
}

contract RedeemTest is AllocationTest {
    // Need to write one more test case to check the amount of assets returned on full redeem to make sure we are getting back enough/correct amount back.
    // Need to test the above by rolling and warping a few blocks and timestamp using simulation.

    function test_Full_Redeem_After_Multiple_Allocations() public {
        test_Multiple_Allocations();

        (,,,,, address _nftPool) = camelotStrategy.strategyData();
        uint256 spNFTId = camelotStrategy.spNFTId();

        (uint256 liquidityBalanceBeforeRedeem,,,,,,,) = INFTPool(_nftPool).getStakingPosition(spNFTId);
        uint256 allocatedAmountBeforeRedeem = camelotStrategy.allocatedAmount();

        uint256 assetABalanceInContractBeforeRedeem = IERC20(ASSET_A).balanceOf(address(camelotStrategy));
        uint256 assetBBalanceInContractBeforeRedeem = IERC20(ASSET_B).balanceOf(address(camelotStrategy));

        vm.prank(USDS_OWNER);
        camelotStrategy.redeem(liquidityBalanceBeforeRedeem);
        vm.stopPrank();

        (uint256 liquidityBalanceAfterRedeem,,,,,,,) = INFTPool(_nftPool).getStakingPosition(spNFTId);
        uint256 allocatedAmountAfterRedeem = camelotStrategy.allocatedAmount();

        uint256 assetABalanceInContractAfterRedeem = IERC20(ASSET_A).balanceOf(address(camelotStrategy));
        uint256 assetBBalanceInContractAfterRedeem = IERC20(ASSET_B).balanceOf(address(camelotStrategy));

        assert(assetABalanceInContractAfterRedeem > assetABalanceInContractBeforeRedeem);
        assert(assetBBalanceInContractAfterRedeem > assetBBalanceInContractBeforeRedeem);
        assertEq(liquidityBalanceBeforeRedeem, allocatedAmountBeforeRedeem);
        assertEq(liquidityBalanceAfterRedeem, 0);
        assertEq(allocatedAmountAfterRedeem, 0);
    }

    function test_Partial_Redeem_After_Multiple_Allocations() public {
        test_Multiple_Allocations();

        (,,,,, address _nftPool) = camelotStrategy.strategyData();
        uint256 spNFTId = camelotStrategy.spNFTId();

        (uint256 liquidityBalanceBeforeRedeem,,,,,,,) = INFTPool(_nftPool).getStakingPosition(spNFTId);
        uint256 allocatedAmountBeforeRedeem = camelotStrategy.allocatedAmount();
        uint256 partialRedeemAmount = liquidityBalanceBeforeRedeem - 1000;

        uint256 assetABalanceInContractBeforeRedeem = IERC20(ASSET_A).balanceOf(address(camelotStrategy));
        uint256 assetBBalanceInContractBeforeRedeem = IERC20(ASSET_B).balanceOf(address(camelotStrategy));

        vm.prank(USDS_OWNER);
        camelotStrategy.redeem(partialRedeemAmount);
        vm.stopPrank();

        (uint256 liquidityBalanceAfterRedeem,,,,,,,) = INFTPool(_nftPool).getStakingPosition(spNFTId);
        uint256 allocatedAmountAfterRedeem = camelotStrategy.allocatedAmount();

        uint256 assetABalanceInContractAfterRedeem = IERC20(ASSET_A).balanceOf(address(camelotStrategy));
        uint256 assetBBalanceInContractAfterRedeem = IERC20(ASSET_B).balanceOf(address(camelotStrategy));

        assert(assetABalanceInContractAfterRedeem > assetABalanceInContractBeforeRedeem);
        assert(assetBBalanceInContractAfterRedeem > assetBBalanceInContractBeforeRedeem);
        assertEq(liquidityBalanceBeforeRedeem, allocatedAmountBeforeRedeem);
        assertEq(liquidityBalanceAfterRedeem, 1000);
        assertEq(allocatedAmountAfterRedeem, 1000);
    }

    function test_Full_Redeem_After_First_Allocation() public {
        test_First_Allocation();

        (,,,,, address _nftPool) = camelotStrategy.strategyData();
        uint256 spNFTId = camelotStrategy.spNFTId();

        (uint256 liquidityBalanceBeforeRedeem,,,,,,,) = INFTPool(_nftPool).getStakingPosition(spNFTId);
        uint256 allocatedAmountBeforeRedeem = camelotStrategy.allocatedAmount();

        uint256 assetABalanceInContractBeforeRedeem = IERC20(ASSET_A).balanceOf(address(camelotStrategy));
        uint256 assetBBalanceInContractBeforeRedeem = IERC20(ASSET_B).balanceOf(address(camelotStrategy));

        vm.prank(USDS_OWNER);
        camelotStrategy.redeem(liquidityBalanceBeforeRedeem);
        vm.stopPrank();

        (uint256 liquidityBalanceAfterRedeem,,,,,,,) = INFTPool(_nftPool).getStakingPosition(spNFTId);
        uint256 allocatedAmountAfterRedeem = camelotStrategy.allocatedAmount();

        uint256 assetABalanceInContractAfterRedeem = IERC20(ASSET_A).balanceOf(address(camelotStrategy));
        uint256 assetBBalanceInContractAfterRedeem = IERC20(ASSET_B).balanceOf(address(camelotStrategy));

        assert(assetABalanceInContractAfterRedeem > assetABalanceInContractBeforeRedeem);
        assert(assetBBalanceInContractAfterRedeem > assetBBalanceInContractBeforeRedeem);
        assertEq(liquidityBalanceBeforeRedeem, allocatedAmountBeforeRedeem);
        assertEq(liquidityBalanceAfterRedeem, 0);
        assertEq(allocatedAmountAfterRedeem, 0);
    }

    function test_Partial_Redeem_After_First_Allocation() public {
        test_First_Allocation();

        (,,,,, address _nftPool) = camelotStrategy.strategyData();
        uint256 spNFTId = camelotStrategy.spNFTId();

        (uint256 liquidityBalanceBeforeRedeem,,,,,,,) = INFTPool(_nftPool).getStakingPosition(spNFTId);
        uint256 allocatedAmountBeforeRedeem = camelotStrategy.allocatedAmount();
        uint256 partialRedeemAmount = liquidityBalanceBeforeRedeem - 1000;

        uint256 assetABalanceInContractBeforeRedeem = IERC20(ASSET_A).balanceOf(address(camelotStrategy));
        uint256 assetBBalanceInContractBeforeRedeem = IERC20(ASSET_B).balanceOf(address(camelotStrategy));

        vm.prank(USDS_OWNER);
        camelotStrategy.redeem(partialRedeemAmount);
        vm.stopPrank();

        (uint256 liquidityBalanceAfterRedeem,,,,,,,) = INFTPool(_nftPool).getStakingPosition(spNFTId);
        uint256 allocatedAmountAfterRedeem = camelotStrategy.allocatedAmount();

        uint256 assetABalanceInContractAfterRedeem = IERC20(ASSET_A).balanceOf(address(camelotStrategy));
        uint256 assetBBalanceInContractAfterRedeem = IERC20(ASSET_B).balanceOf(address(camelotStrategy));

        assert(assetABalanceInContractAfterRedeem > assetABalanceInContractBeforeRedeem);
        assert(assetBBalanceInContractAfterRedeem > assetBBalanceInContractBeforeRedeem);
        assertEq(liquidityBalanceBeforeRedeem, allocatedAmountBeforeRedeem);
        assertEq(liquidityBalanceAfterRedeem, 1000);
        assertEq(allocatedAmountAfterRedeem, 1000);
    }
}

contract WithdrawAssetsToVaultTests is RedeemTest {
    function test_Withdraw_Assets_To_Vault_After_Deposit_Caller_UsdsOwner() public {
        uint256 depositAmountAssetA = 1000 * 10 ** ERC20(ASSET_A).decimals();
        uint256 depositAmountAssetB = 1000 * 10 ** ERC20(ASSET_B).decimals();
        _depositAssetsToStrategy(depositAmountAssetA, depositAmountAssetB);

        uint256 withdrawAmountAssetA = 100 * 10 ** ERC20(ASSET_A).decimals();
        uint256 withdrawAmountAssetB = 100 * 10 ** ERC20(ASSET_B).decimals();

        uint256 assetABalanceInVaultBeforeWithdraw = IERC20(ASSET_A).balanceOf(VAULT);
        uint256 assetABalanceInStrategyBeforeWithdraw = IERC20(ASSET_A).balanceOf(address(camelotStrategy));

        vm.expectEmit(true, false, false, true, address(camelotStrategy));
        emit Withdrawal(ASSET_A, withdrawAmountAssetA);

        vm.prank(USDS_OWNER);
        camelotStrategy.withdrawToVault(ASSET_A, withdrawAmountAssetA);
        vm.stopPrank();

        uint256 assetABalanceInVaultAfterWithdraw = IERC20(ASSET_A).balanceOf(VAULT);
        uint256 assetABalanceInStrategyAfterWithdraw = IERC20(ASSET_A).balanceOf(address(camelotStrategy));

        assertEq(assetABalanceInVaultAfterWithdraw, assetABalanceInVaultBeforeWithdraw + withdrawAmountAssetA);
        assertEq(assetABalanceInStrategyAfterWithdraw, assetABalanceInStrategyBeforeWithdraw - withdrawAmountAssetA);

        uint256 assetBBalanceInVaultBeforeWithdraw = IERC20(ASSET_B).balanceOf(VAULT);
        uint256 assetBBalanceInStrategyBeforeWithdraw = IERC20(ASSET_B).balanceOf(address(camelotStrategy));

        vm.expectEmit(true, false, false, true, address(camelotStrategy));
        emit Withdrawal(ASSET_B, withdrawAmountAssetB);

        vm.prank(USDS_OWNER);
        camelotStrategy.withdrawToVault(ASSET_B, withdrawAmountAssetB);
        vm.stopPrank();

        uint256 assetBBalanceInVaultAfterWithdraw = IERC20(ASSET_B).balanceOf(VAULT);
        uint256 assetBBalanceInStrategyAfterWithdraw = IERC20(ASSET_B).balanceOf(address(camelotStrategy));

        assertEq(assetBBalanceInVaultAfterWithdraw, assetBBalanceInVaultBeforeWithdraw + withdrawAmountAssetB);
        assertEq(assetBBalanceInStrategyAfterWithdraw, assetBBalanceInStrategyBeforeWithdraw - withdrawAmountAssetB);
    }

    function test_Withdraw_Assets_To_Vault_After_Deposit_Caller_Vault() public {
        uint256 depositAmountAssetA = 1000 * 10 ** ERC20(ASSET_A).decimals();
        uint256 depositAmountAssetB = 1000 * 10 ** ERC20(ASSET_B).decimals();
        _depositAssetsToStrategy(depositAmountAssetA, depositAmountAssetB);

        uint256 withdrawAmountAssetA = 100 * 10 ** ERC20(ASSET_A).decimals();
        uint256 withdrawAmountAssetB = 100 * 10 ** ERC20(ASSET_B).decimals();

        uint256 assetABalanceInVaultBeforeWithdraw = IERC20(ASSET_A).balanceOf(VAULT);
        uint256 assetABalanceInStrategyBeforeWithdraw = IERC20(ASSET_A).balanceOf(address(camelotStrategy));

        vm.expectEmit(true, false, false, true, address(camelotStrategy));
        emit Withdrawal(ASSET_A, withdrawAmountAssetA);

        vm.prank(VAULT);
        camelotStrategy.withdraw(VAULT, ASSET_A, withdrawAmountAssetA);
        vm.stopPrank();

        uint256 assetABalanceInVaultAfterWithdraw = IERC20(ASSET_A).balanceOf(VAULT);
        uint256 assetABalanceInStrategyAfterWithdraw = IERC20(ASSET_A).balanceOf(address(camelotStrategy));

        assertEq(assetABalanceInVaultAfterWithdraw, assetABalanceInVaultBeforeWithdraw + withdrawAmountAssetA);
        assertEq(assetABalanceInStrategyAfterWithdraw, assetABalanceInStrategyBeforeWithdraw - withdrawAmountAssetA);

        uint256 assetBBalanceInVaultBeforeWithdraw = IERC20(ASSET_B).balanceOf(VAULT);
        uint256 assetBBalanceInStrategyBeforeWithdraw = IERC20(ASSET_B).balanceOf(address(camelotStrategy));

        vm.expectEmit(true, false, false, true, address(camelotStrategy));
        emit Withdrawal(ASSET_B, withdrawAmountAssetB);

        vm.prank(VAULT);
        camelotStrategy.withdraw(VAULT, ASSET_B, withdrawAmountAssetB);
        vm.stopPrank();

        uint256 assetBBalanceInVaultAfterWithdraw = IERC20(ASSET_B).balanceOf(VAULT);
        uint256 assetBBalanceInStrategyAfterWithdraw = IERC20(ASSET_B).balanceOf(address(camelotStrategy));

        assertEq(assetBBalanceInVaultAfterWithdraw, assetBBalanceInVaultBeforeWithdraw + withdrawAmountAssetB);
        assertEq(assetBBalanceInStrategyAfterWithdraw, assetBBalanceInStrategyBeforeWithdraw - withdrawAmountAssetB);
    }

    function test_Withdraw_Assets_To_Vault_After_Redeem_Caller_UsdsOwner() public {
        test_Full_Redeem_After_Multiple_Allocations();

        uint256 withdrawAmountAssetA = 100 * 10 ** ERC20(ASSET_A).decimals();
        uint256 withdrawAmountAssetB = 100 * 10 ** ERC20(ASSET_B).decimals();

        uint256 assetABalanceInVaultBeforeWithdraw = IERC20(ASSET_A).balanceOf(VAULT);
        uint256 assetABalanceInStrategyBeforeWithdraw = IERC20(ASSET_A).balanceOf(address(camelotStrategy));

        vm.prank(USDS_OWNER);
        camelotStrategy.withdrawToVault(ASSET_A, withdrawAmountAssetA);
        vm.stopPrank();

        uint256 assetABalanceInVaultAfterWithdraw = IERC20(ASSET_A).balanceOf(VAULT);
        uint256 assetABalanceInStrategyAfterWithdraw = IERC20(ASSET_A).balanceOf(address(camelotStrategy));

        assertEq(assetABalanceInVaultAfterWithdraw, assetABalanceInVaultBeforeWithdraw + withdrawAmountAssetA);
        assertEq(assetABalanceInStrategyAfterWithdraw, assetABalanceInStrategyBeforeWithdraw - withdrawAmountAssetA);

        uint256 assetBBalanceInVaultBeforeWithdraw = IERC20(ASSET_B).balanceOf(VAULT);
        uint256 assetBBalanceInStrategyBeforeWithdraw = IERC20(ASSET_B).balanceOf(address(camelotStrategy));

        vm.prank(USDS_OWNER);
        camelotStrategy.withdrawToVault(ASSET_B, withdrawAmountAssetB);
        vm.stopPrank();

        uint256 assetBBalanceInVaultAfterWithdraw = IERC20(ASSET_B).balanceOf(VAULT);
        uint256 assetBBalanceInStrategyAfterWithdraw = IERC20(ASSET_B).balanceOf(address(camelotStrategy));

        assertEq(assetBBalanceInVaultAfterWithdraw, assetBBalanceInVaultBeforeWithdraw + withdrawAmountAssetB);
        assertEq(assetBBalanceInStrategyAfterWithdraw, assetBBalanceInStrategyBeforeWithdraw - withdrawAmountAssetB);
    }

    function test_Withdraw_Assets_To_Vault_After_Redeem_Caller_Vault() public {
        test_Full_Redeem_After_Multiple_Allocations();

        uint256 withdrawAmountAssetA = 100 * 10 ** ERC20(ASSET_A).decimals();
        uint256 withdrawAmountAssetB = 100 * 10 ** ERC20(ASSET_B).decimals();

        uint256 assetABalanceInVaultBeforeWithdraw = IERC20(ASSET_A).balanceOf(VAULT);
        uint256 assetABalanceInStrategyBeforeWithdraw = IERC20(ASSET_A).balanceOf(address(camelotStrategy));

        vm.prank(VAULT);
        camelotStrategy.withdraw(VAULT, ASSET_A, withdrawAmountAssetA);
        vm.stopPrank();

        uint256 assetABalanceInVaultAfterWithdraw = IERC20(ASSET_A).balanceOf(VAULT);
        uint256 assetABalanceInStrategyAfterWithdraw = IERC20(ASSET_A).balanceOf(address(camelotStrategy));

        assertEq(assetABalanceInVaultAfterWithdraw, assetABalanceInVaultBeforeWithdraw + withdrawAmountAssetA);
        assertEq(assetABalanceInStrategyAfterWithdraw, assetABalanceInStrategyBeforeWithdraw - withdrawAmountAssetA);

        uint256 assetBBalanceInVaultBeforeWithdraw = IERC20(ASSET_B).balanceOf(VAULT);
        uint256 assetBBalanceInStrategyBeforeWithdraw = IERC20(ASSET_B).balanceOf(address(camelotStrategy));

        vm.prank(VAULT);
        camelotStrategy.withdraw(VAULT, ASSET_B, withdrawAmountAssetB);
        vm.stopPrank();

        uint256 assetBBalanceInVaultAfterWithdraw = IERC20(ASSET_B).balanceOf(VAULT);
        uint256 assetBBalanceInStrategyAfterWithdraw = IERC20(ASSET_B).balanceOf(address(camelotStrategy));

        assertEq(assetBBalanceInVaultAfterWithdraw, assetBBalanceInVaultBeforeWithdraw + withdrawAmountAssetB);
        assertEq(assetBBalanceInStrategyAfterWithdraw, assetBBalanceInStrategyBeforeWithdraw - withdrawAmountAssetB);
    }
}

contract collectRewardTest is AllocationTest {}

contract UpdateStrategyDataTest is CamelotStrategyTestSetup {
    event StrategyDataUpdated(CamelotStrategy.StrategyData);

    function test_Update_Strategy_Data() public {
        address newAssetA = address(0x1);
        address newAssetB = address(0x2);
        CamelotStrategy.StrategyData memory _newStrategyData = CamelotStrategy.StrategyData({
            tokenA: newAssetA,
            tokenB: newAssetB,
            router: 0xc873fEcbd354f5A56E00E710B90EF4201db2448d,
            positionHelper: 0xe458018Ad4283C90fB7F5460e24C4016F81b8175,
            factory: 0x6EcCab422D763aC031210895C81787E87B43A652,
            nftPool: 0xcC9f28dAD9b85117AB5237df63A5EE6fC50B02B7
        });

        vm.expectEmit(false, false, false, true, address(camelotStrategy));

        emit StrategyDataUpdated(_newStrategyData);

        vm.startPrank(USDS_OWNER);
        camelotStrategy.updateStrategyData(_newStrategyData);
        vm.stopPrank();

        (address _tokenA, address _tokenB, address _router, address _positionHelper, address _factory, address _nftPool)
        = camelotStrategy.strategyData();

        CamelotStrategy.StrategyData memory _updatedStrategyData = CamelotStrategy.StrategyData({
            tokenA: _tokenA,
            tokenB: _tokenB,
            router: _router,
            positionHelper: _positionHelper,
            factory: _factory,
            nftPool: _nftPool
        });

        bytes memory actualData = abi.encode(_updatedStrategyData);
        bytes memory expectedData = abi.encode(_newStrategyData);

        assertEq(keccak256(actualData), keccak256(expectedData));
    }
}

contract MiscellaneousTests is AllocationTest {
    error NotCamelotNFTPool();
    error InvalidAsset();

    function test_Supports_Collateral() public {
        bool result1 = camelotStrategy.supportsCollateral(ASSET_A);
        assertEq(result1, true);

        bool result2 = camelotStrategy.supportsCollateral(ASSET_B);
        assertEq(result2, true);

        address randomToken = address(0x1);

        bool result3 = camelotStrategy.supportsCollateral(randomToken);
        assertEq(result3, false);
    }

    function test_Collect_Interest() public {
        address addressToCollectInterest = address(0x1);
        vm.expectRevert(abi.encodeWithSelector(Helpers.CustomError.selector, "Operation not permitted"));
        camelotStrategy.collectInterest(addressToCollectInterest);
    }

    function test_Interest_Earned() public {
        address addressToCollectInterest = address(0x1);
        uint256 interestEarned = camelotStrategy.checkInterestEarned(addressToCollectInterest);
        assertEq(interestEarned, 0);
    }

    function test_Revert_When_Random_onERC721Received_Caller() public {
        address randomCaller = address(0x1);
        vm.expectRevert(abi.encodeWithSelector(NotCamelotNFTPool.selector));
        vm.startPrank(randomCaller);
        camelotStrategy.onERC721Received(address(0x1), address(0x2), 1, "");
        vm.stopPrank();
    }

    function test_RevertWhen_Random_onNFTHarvest_Caller() public {
        address randomCaller = address(0x1);
        vm.expectRevert(abi.encodeWithSelector(NotCamelotNFTPool.selector));
        vm.startPrank(randomCaller);
        camelotStrategy.onNFTHarvest(address(0x1), address(0x2), 1, 1, 1);
        vm.stopPrank();
    }

    function test_RevertWhen_Random_onNFTAddToPosition_Caller() public {
        address randomCaller = address(0x1);
        vm.expectRevert(abi.encodeWithSelector(NotCamelotNFTPool.selector));
        vm.startPrank(randomCaller);
        camelotStrategy.onNFTAddToPosition(address(0x1), 1, 1);
        vm.stopPrank();
    }

    function test_RevertWhen_Random_onNFTWithdraw_Caller() public {
        address randomCaller = address(0x1);
        vm.expectRevert(abi.encodeWithSelector(NotCamelotNFTPool.selector));
        vm.startPrank(randomCaller);
        camelotStrategy.onNFTWithdraw(address(0x1), 1, 1);
        vm.stopPrank();
    }

    function test_checkLPTokenBalance() public {
        test_Multiple_Allocations();

        (,,,,, address _nftPool) = camelotStrategy.strategyData();
        uint256 spNFTId = camelotStrategy.spNFTId();

        (uint256 liquidityBalance,,,,,,,) = INFTPool(_nftPool).getStakingPosition(spNFTId);

        uint256 balance = camelotStrategy.checkLPTokenBalance(ASSET_A);

        assertEq(balance, liquidityBalance);

        balance = camelotStrategy.checkLPTokenBalance(ASSET_B);

        assertEq(balance, liquidityBalance);

        address randomAsset = address(0x1);

        vm.expectRevert(abi.encodeWithSelector(InvalidAsset.selector));
        camelotStrategy.checkLPTokenBalance(randomAsset);
    }

    function test_checkRewardEarned() public {
        test_Multiple_Allocations();

        (,,,,, address _nftPool) = camelotStrategy.strategyData();
        uint256 spNFTId = camelotStrategy.spNFTId();

        uint256 rewardsBefore = INFTPool(_nftPool).pendingRewards(spNFTId);
        uint256 rewardsBeforeContractState = camelotStrategy.checkRewardEarned();

        vm.warp(block.timestamp + 10 days);
        vm.roll(block.number + 1000);

        uint256 rewardsAfter = INFTPool(_nftPool).pendingRewards(spNFTId);
        uint256 rewardsAfterContractState = camelotStrategy.checkRewardEarned();

        assertEq(rewardsBefore, rewardsBeforeContractState);
        assertEq(rewardsAfter, rewardsAfterContractState);
        assert(rewardsAfterContractState > rewardsBeforeContractState);
    }
}
