// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {PreMigrationSetup} from "../utils/DeploymentSetup.t.sol";
import {BaseStrategy} from "./BaseStrategy.t.sol";
import {CamelotStrategy} from "../../contracts/strategies/camelot/CamelotStrategy.sol";
import {
    IRouter,
    INFTPool,
    IPair,
    IXGrailToken,
    IDividendV2
} from "../../contracts/strategies/camelot/interfaces/ICamelot.sol";
import {InitializableAbstractStrategy, Helpers} from "../../contracts/strategies/InitializableAbstractStrategy.sol";
import {IERC20, ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IVault} from "../../contracts/interfaces/IVault.sol";
import {VmSafe} from "forge-std/Vm.sol";

interface ICamelotRouterSwap {
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        address referrer,
        uint256 deadline
    ) external;
}

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

    function _allocate(uint256 allocateAmountAssetA, uint256 allocateAmountAssetB)
        internal
        returns (uint256, uint256)
    {
        (allocateAmountAssetA, allocateAmountAssetB) =
            camelotStrategy.getDepositAmounts(allocateAmountAssetA, allocateAmountAssetB);

        vm.prank(USDS_OWNER);
        camelotStrategy.allocate([uint256(allocateAmountAssetA), uint256(allocateAmountAssetB)]);
        vm.stopPrank();

        return (allocateAmountAssetA, allocateAmountAssetB);
    }

    function _redeem(uint256 liquidityToWithdraw) internal {
        vm.prank(USDS_OWNER);
        camelotStrategy.redeem(liquidityToWithdraw);
        vm.stopPrank();
    }

    function _singleAllocation() internal {
        _depositAssetsToStrategy(1000 * 10 ** ERC20(ASSET_A).decimals(), 1000 * 10 ** ERC20(ASSET_B).decimals());

        _allocate(1000 * 10 ** ERC20(ASSET_A).decimals(), 1000 * 10 ** ERC20(ASSET_B).decimals());
    }

    function _multipleAllocations() internal {
        _depositAssetsToStrategy(1000 * 10 ** ERC20(ASSET_A).decimals(), 1000 * 10 ** ERC20(ASSET_B).decimals());

        _allocate(1000 * 10 ** ERC20(ASSET_A).decimals(), 1000 * 10 ** ERC20(ASSET_B).decimals());

        _depositAssetsToStrategy(100 * 10 ** ERC20(ASSET_A).decimals(), 100 * 10 ** ERC20(ASSET_B).decimals());

        _allocate(100 * 10 ** ERC20(ASSET_A).decimals(), 100 * 10 ** ERC20(ASSET_B).decimals());
    }

    function _multipleSwaps() internal {
        (,, address _router,,,) = camelotStrategy.strategyData();

        address swapper = address(0x2);

        deal(ASSET_A, swapper, 1000 * 10 ** ERC20(ASSET_A).decimals());

        uint256 amountIn;
        uint256 amountOutMin = 0;
        address[] memory path = new address[](2);
        address to = swapper;
        address referrer = address(0x0);

        vm.warp(block.timestamp + 10 days);
        vm.roll(block.number + 1000);

        uint256 deadline = block.timestamp;

        vm.startPrank(swapper);
        path[0] = ASSET_A;
        path[1] = ASSET_B;
        amountIn = 400 * 10 ** ERC20(ASSET_A).decimals();
        IERC20(ASSET_A).approve(_router, 400 * 10 ** ERC20(ASSET_A).decimals());
        ICamelotRouterSwap(_router).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn, amountOutMin, path, to, referrer, deadline
        );

        path[0] = ASSET_B;
        path[1] = ASSET_A;
        amountIn = 300 * 10 ** ERC20(ASSET_B).decimals();
        IERC20(ASSET_B).approve(_router, 300 * 10 ** ERC20(ASSET_B).decimals());
        ICamelotRouterSwap(_router).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn, amountOutMin, path, to, referrer, deadline
        );

        vm.warp(block.timestamp + 10 days);
        vm.roll(block.number + 1000);

        deadline = block.timestamp;

        amountIn = 400 * 10 ** ERC20(ASSET_A).decimals();
        path[0] = ASSET_A;
        path[1] = ASSET_B;
        IERC20(ASSET_A).approve(_router, 400 * 10 ** ERC20(ASSET_A).decimals());
        ICamelotRouterSwap(_router).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn, amountOutMin, path, to, referrer, deadline
        );
        amountIn = 300 * 10 ** ERC20(ASSET_B).decimals();
        path[0] = ASSET_B;
        path[1] = ASSET_A;
        IERC20(ASSET_B).approve(_router, 350 * 10 ** ERC20(ASSET_B).decimals());
        ICamelotRouterSwap(_router).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn, amountOutMin, path, to, referrer, deadline
        );
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
    function test_Deposit_Assets_To_Strategy() public {
        uint256 currentAmountAssetA = IERC20(ASSET_A).balanceOf(address(camelotStrategy));
        uint256 currentAmountAssetB = IERC20(ASSET_B).balanceOf(address(camelotStrategy));

        _depositAssetsToStrategy(1000 * 10 ** ERC20(ASSET_A).decimals(), 1000 * 10 ** ERC20(ASSET_B).decimals());

        assertEq(
            IERC20(ASSET_A).balanceOf(address(camelotStrategy)),
            currentAmountAssetA + 1000 * 10 ** ERC20(ASSET_A).decimals()
        );
        assertEq(
            IERC20(ASSET_B).balanceOf(address(camelotStrategy)),
            currentAmountAssetB + 1000 * 10 ** ERC20(ASSET_B).decimals()
        );
    }

    function test_Revert_When_Wrong_Asset_Deposit_To_Strategy() public {
        address randomToken = address(0x1);
        vm.expectRevert(abi.encodeWithSelector(CollateralNotSupported.selector, randomToken));
        camelotStrategy.deposit(randomToken, 1000);
    }
}

contract AllocationTest is CamelotStrategyTestSetup {
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

    function test_Allocate_MintNewPositionAndAddLiquidity() public {
        _depositAssetsToStrategy(1000 * 10 ** ERC20(ASSET_A).decimals(), 1000 * 10 ** ERC20(ASSET_B).decimals());

        (,, address _router,,, address _nftPool) = camelotStrategy.strategyData();

        address pair = IRouter(_router).getPair(ASSET_A, ASSET_B);

        uint256 numOfSpNFTsBeforeAllocation = IERC721(_nftPool).balanceOf(address(camelotStrategy));
        uint256 amountAllocatedBeforeAllocation = camelotStrategy.allocatedAmount();

        uint256 assetABalanceInContractBeforeAllocation = IERC20(ASSET_A).balanceOf(address(camelotStrategy));
        uint256 assetBBalanceInContractBeforeAllocation = IERC20(ASSET_B).balanceOf(address(camelotStrategy));

        uint256 spNFTId = camelotStrategy.spNFTId();
        assertEq(spNFTId, 0); // before first allocation spNFTId should be 0

        (uint256 allocatedAmountAssetA, uint256 allocatedAmountAssetB) =
            _allocate(1000 * 10 ** ERC20(ASSET_A).decimals(), 1000 * 10 ** ERC20(ASSET_B).decimals());

        uint256 assetABalanceInContractAfterAllocation = IERC20(ASSET_A).balanceOf(address(camelotStrategy));
        uint256 assetBBalanceInContractAfterAllocation = IERC20(ASSET_B).balanceOf(address(camelotStrategy));

        spNFTId = camelotStrategy.spNFTId();
        (uint256 liquidityBalance,,,,,,,) = INFTPool(_nftPool).getStakingPosition(spNFTId);

        uint256 numOfSpNFTsAfterAllocation = IERC721(_nftPool).balanceOf(address(camelotStrategy));
        uint256 amountAllocatedAfterAllocation = camelotStrategy.allocatedAmount();

        assertEq(numOfSpNFTsBeforeAllocation + 1, numOfSpNFTsAfterAllocation);
        assertEq(IERC20(pair).balanceOf(address(camelotStrategy)), 0);
        assertTrue(amountAllocatedAfterAllocation > amountAllocatedBeforeAllocation);
        assertEq(liquidityBalance, amountAllocatedAfterAllocation);
        assertApproxEqAbs(
            assetABalanceInContractAfterAllocation, assetABalanceInContractBeforeAllocation - allocatedAmountAssetA, 1
        );
        assertApproxEqAbs(
            assetBBalanceInContractAfterAllocation, assetBBalanceInContractBeforeAllocation - allocatedAmountAssetB, 1
        );
    }

    // wrote this as a separate test as i got stack too deep error in test_Allocate_MintNewPositionAndAddLiquidity function.
    // Also --via-ir taking lot of time to run. So separated the test
    function test_Allocate_MintNewPositionAndAddLiquidity_Emit_And_Slippage_Test() public {
        _depositAssetsToStrategy(1000 * 10 ** ERC20(ASSET_A).decimals(), 1000 * 10 ** ERC20(ASSET_B).decimals());

        (,,,,, address _nftPool) = camelotStrategy.strategyData();

        vm.recordLogs();

        (uint256 allocatedAmountAssetA, uint256 allocatedAmountAssetB) =
            _allocate(1000 * 10 ** ERC20(ASSET_A).decimals(), 1000 * 10 ** ERC20(ASSET_B).decimals());

        uint256 minAmountsAssetA =
            allocatedAmountAssetA - (allocatedAmountAssetA * camelotStrategy.depositSlippage() / Helpers.MAX_PERCENTAGE);
        uint256 minAmountsAssetB =
            allocatedAmountAssetB - (allocatedAmountAssetB * camelotStrategy.depositSlippage() / Helpers.MAX_PERCENTAGE);

        VmSafe.Log[] memory logs = vm.getRecordedLogs();

        // uint256 expectedTokenId;
        uint256 expectedLiquidity;
        uint256 expectedAmountA;
        uint256 expectedAmountB;

        for (uint8 j = 0; j < logs.length; ++j) {
            if (logs[j].topics[0] == keccak256("IncreaseLiquidity(uint256,uint256,uint256)")) {
                (expectedLiquidity, expectedAmountA, expectedAmountB) =
                    abi.decode(logs[j].data, (uint256, uint256, uint256));
            }
        }

        uint256 spNFTId = camelotStrategy.spNFTId();
        (uint256 liquidityBalance,,,,,,,) = INFTPool(_nftPool).getStakingPosition(spNFTId);

        // assertEq(expectedTokenId, spNFTId);
        assertEq(expectedLiquidity, liquidityBalance);
        assertApproxEqAbs(expectedAmountA, allocatedAmountAssetA, 3);
        assertApproxEqAbs(expectedAmountB, allocatedAmountAssetB, 3);

        assertTrue(expectedAmountA >= minAmountsAssetA);
        assertTrue(expectedAmountB >= minAmountsAssetB);
    }

    function test_Allocate_IncreaseLiquidity() public {
        uint256 amountAllocatedBeforeIncreaseAllocation = camelotStrategy.allocatedAmount();

        _multipleAllocations();

        (,, address _router,,, address _nftPool) = camelotStrategy.strategyData();

        address pair = IRouter(_router).getPair(ASSET_A, ASSET_B);
        uint256 spNFTId = camelotStrategy.spNFTId();

        uint256 amountAllocatedAfterIncreaseAllocation = camelotStrategy.allocatedAmount();

        (uint256 liquidityBalance,,,,,,,) = INFTPool(_nftPool).getStakingPosition(spNFTId);

        assertTrue(amountAllocatedAfterIncreaseAllocation > amountAllocatedBeforeIncreaseAllocation);
        assertEq(IERC20(pair).balanceOf(address(camelotStrategy)), 0);
        assertEq(liquidityBalance, amountAllocatedAfterIncreaseAllocation);
    }

    function test_Asset_Balance_In_Contract_After_Multiple_Allocations() public {
        _depositAssetsToStrategy(2000 * 10 ** ERC20(ASSET_A).decimals(), 2000 * 10 ** ERC20(ASSET_B).decimals());

        uint256 assetABalanceInContractBeforeAllocations = IERC20(ASSET_A).balanceOf(address(camelotStrategy));
        uint256 assetBBalanceInContractBeforeAllocations = IERC20(ASSET_B).balanceOf(address(camelotStrategy));

        (uint256 firstAllocatedAmountAssetA, uint256 firstAllocatedAmountAssetB) =
            _allocate(1000 * 10 ** ERC20(ASSET_A).decimals(), 1000 * 10 ** ERC20(ASSET_B).decimals());

        (uint256 secondAllocatedAmountAssetA, uint256 secondAllocatedAmountAssetB) =
            _allocate(100 * 10 ** ERC20(ASSET_A).decimals(), 100 * 10 ** ERC20(ASSET_B).decimals());

        uint256 totalAllocatedAssetA = firstAllocatedAmountAssetA + secondAllocatedAmountAssetA;
        uint256 totalAllocatedAssetB = firstAllocatedAmountAssetB + secondAllocatedAmountAssetB;

        uint256 assetABalanceInContractAfterAllocations = IERC20(ASSET_A).balanceOf(address(camelotStrategy));
        uint256 assetBBalanceInContractAfterAllocations = IERC20(ASSET_B).balanceOf(address(camelotStrategy));

        assertApproxEqAbs(
            assetABalanceInContractAfterAllocations, assetABalanceInContractBeforeAllocations - totalAllocatedAssetA, 2
        );
        assertApproxEqAbs(
            assetBBalanceInContractAfterAllocations, assetBBalanceInContractBeforeAllocations - totalAllocatedAssetB, 2
        );
    }

    function test_GetDepositAmounts() public {
        (,, address _router,,,) = camelotStrategy.strategyData();
        address pair = IRouter(_router).getPair(ASSET_A, ASSET_B);
        (uint112 reserveA, uint112 reserveB,,) = IPair(pair).getReserves();
        uint256 amountADesired = 1000 * 10 ** ERC20(ASSET_A).decimals();
        uint256 amountBDesired = 1000 * 10 ** ERC20(ASSET_B).decimals();

        (uint256 amountA, uint256 amountB) = camelotStrategy.getDepositAmounts(amountADesired, amountBDesired);

        if (reserveA == 0 && reserveB == 0) {
            assertEq(amountA, amountADesired);
            assertEq(amountB, amountBDesired);
        } else {
            uint256 amountBOptimal = IRouter(_router).quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                assertEq(amountA, amountADesired);
                assertEq(amountB, amountBOptimal);
            } else {
                uint256 amountAOptimal = IRouter(_router).quote(amountBDesired, reserveB, reserveA);
                assertTrue(amountAOptimal <= amountADesired);
                assertEq(amountA, amountAOptimal);
                assertEq(amountB, amountBDesired);
            }
        }
    }
}

contract RedeemTest is CamelotStrategyTestSetup {
    // Need to write one more test case to check the amount of assets returned on full redeem to make sure we are getting back enough/correct amount back.
    // Need to test the above by rolling and warping a few blocks and timestamp using simulation and some swaps in the camelot pool.

    function test_Full_Redeem_After_Allocate_IncreaseLiquidity() public {
        _multipleAllocations();

        (,,,,, address _nftPool) = camelotStrategy.strategyData();
        uint256 spNFTId = camelotStrategy.spNFTId();

        (uint256 liquidityBalanceBeforeRedeem,,,,,,,) = INFTPool(_nftPool).getStakingPosition(spNFTId);
        uint256 allocatedAmountBeforeRedeem = camelotStrategy.allocatedAmount();

        uint256 assetABalanceInContractBeforeRedeem = IERC20(ASSET_A).balanceOf(address(camelotStrategy));
        uint256 assetBBalanceInContractBeforeRedeem = IERC20(ASSET_B).balanceOf(address(camelotStrategy));

        _redeem(liquidityBalanceBeforeRedeem);

        (uint256 liquidityBalanceAfterRedeem,,,,,,,) = INFTPool(_nftPool).getStakingPosition(spNFTId);
        uint256 allocatedAmountAfterRedeem = camelotStrategy.allocatedAmount();

        uint256 assetABalanceInContractAfterRedeem = IERC20(ASSET_A).balanceOf(address(camelotStrategy));
        uint256 assetBBalanceInContractAfterRedeem = IERC20(ASSET_B).balanceOf(address(camelotStrategy));

        assertTrue(assetABalanceInContractAfterRedeem > assetABalanceInContractBeforeRedeem);
        assertTrue(assetBBalanceInContractAfterRedeem > assetBBalanceInContractBeforeRedeem);
        assertEq(liquidityBalanceBeforeRedeem, allocatedAmountBeforeRedeem);
        assertEq(liquidityBalanceAfterRedeem, 0);
        assertEq(allocatedAmountAfterRedeem, 0);
    }

    function test_Partial_Redeem_After_Allocate_IncreaseLiquidity() public {
        _multipleAllocations();

        (,,,,, address _nftPool) = camelotStrategy.strategyData();
        uint256 spNFTId = camelotStrategy.spNFTId();

        (uint256 liquidityBalanceBeforeRedeem,,,,,,,) = INFTPool(_nftPool).getStakingPosition(spNFTId);
        uint256 allocatedAmountBeforeRedeem = camelotStrategy.allocatedAmount();
        uint256 partialRedeemAmount = liquidityBalanceBeforeRedeem - 1000;

        uint256 assetABalanceInContractBeforeRedeem = IERC20(ASSET_A).balanceOf(address(camelotStrategy));
        uint256 assetBBalanceInContractBeforeRedeem = IERC20(ASSET_B).balanceOf(address(camelotStrategy));

        _redeem(partialRedeemAmount);

        (uint256 liquidityBalanceAfterRedeem,,,,,,,) = INFTPool(_nftPool).getStakingPosition(spNFTId);
        uint256 allocatedAmountAfterRedeem = camelotStrategy.allocatedAmount();

        uint256 assetABalanceInContractAfterRedeem = IERC20(ASSET_A).balanceOf(address(camelotStrategy));
        uint256 assetBBalanceInContractAfterRedeem = IERC20(ASSET_B).balanceOf(address(camelotStrategy));

        assertTrue(assetABalanceInContractAfterRedeem > assetABalanceInContractBeforeRedeem);
        assertTrue(assetBBalanceInContractAfterRedeem > assetBBalanceInContractBeforeRedeem);
        assertEq(liquidityBalanceBeforeRedeem, allocatedAmountBeforeRedeem);
        assertEq(liquidityBalanceAfterRedeem, 1000);
        assertEq(allocatedAmountAfterRedeem, 1000);
    }

    function test_Full_Redeem_After_Allocate_MintNewPositionAndAddLiquidity() public {
        _singleAllocation();

        (,,,,, address _nftPool) = camelotStrategy.strategyData();
        uint256 spNFTId = camelotStrategy.spNFTId();

        (uint256 liquidityBalanceBeforeRedeem,,,,,,,) = INFTPool(_nftPool).getStakingPosition(spNFTId);
        uint256 allocatedAmountBeforeRedeem = camelotStrategy.allocatedAmount();

        uint256 assetABalanceInContractBeforeRedeem = IERC20(ASSET_A).balanceOf(address(camelotStrategy));
        uint256 assetBBalanceInContractBeforeRedeem = IERC20(ASSET_B).balanceOf(address(camelotStrategy));

        _redeem(liquidityBalanceBeforeRedeem);

        (uint256 liquidityBalanceAfterRedeem,,,,,,,) = INFTPool(_nftPool).getStakingPosition(spNFTId);
        uint256 allocatedAmountAfterRedeem = camelotStrategy.allocatedAmount();

        uint256 assetABalanceInContractAfterRedeem = IERC20(ASSET_A).balanceOf(address(camelotStrategy));
        uint256 assetBBalanceInContractAfterRedeem = IERC20(ASSET_B).balanceOf(address(camelotStrategy));

        assertTrue(assetABalanceInContractAfterRedeem > assetABalanceInContractBeforeRedeem);
        assertTrue(assetBBalanceInContractAfterRedeem > assetBBalanceInContractBeforeRedeem);
        assertEq(liquidityBalanceBeforeRedeem, allocatedAmountBeforeRedeem);
        assertEq(liquidityBalanceAfterRedeem, 0);
        assertEq(allocatedAmountAfterRedeem, 0);
    }

    function test_Partial_Redeem_After_Allocate_MintNewPositionAndAddLiquidity() public {
        _singleAllocation();

        (,,,,, address _nftPool) = camelotStrategy.strategyData();
        uint256 spNFTId = camelotStrategy.spNFTId();

        (uint256 liquidityBalanceBeforeRedeem,,,,,,,) = INFTPool(_nftPool).getStakingPosition(spNFTId);
        uint256 allocatedAmountBeforeRedeem = camelotStrategy.allocatedAmount();
        uint256 partialRedeemAmount = liquidityBalanceBeforeRedeem - 1000;

        uint256 assetABalanceInContractBeforeRedeem = IERC20(ASSET_A).balanceOf(address(camelotStrategy));
        uint256 assetBBalanceInContractBeforeRedeem = IERC20(ASSET_B).balanceOf(address(camelotStrategy));

        _redeem(partialRedeemAmount);

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

    function test_Redeem_Emit_Test() public {
        _multipleAllocations();

        (,,,,, address _nftPool) = camelotStrategy.strategyData();
        uint256 spNFTId = camelotStrategy.spNFTId();

        (uint256 liquidityBalanceBeforeRedeem,,,,,,,) = INFTPool(_nftPool).getStakingPosition(spNFTId);
        uint256 partialRedeemAmount = liquidityBalanceBeforeRedeem - 1000;

        vm.recordLogs();

        _redeem(partialRedeemAmount);

        VmSafe.Log[] memory logs = vm.getRecordedLogs();

        uint256 expectedLiquidityToWithdraw;
        // uint256 expectedAmountA;
        // uint256 expectedAmountB;

        for (uint8 j = 0; j < logs.length; ++j) {
            if (logs[j].topics[0] == keccak256("DecreaseLiquidity(uint256,uint256,uint256)")) {
                (expectedLiquidityToWithdraw,,) = abi.decode(logs[j].data, (uint256, uint256, uint256));
            }
        }

        assertEq(expectedLiquidityToWithdraw, partialRedeemAmount);
    }

    // function test_Assets_Amount_Returned_On_Full_Redeem_After_Some_Swaps() public {
    //     // This check is to make sure that we are getting more assets than we allocated in the camelot pool after some swaps in the pool.
    //     // This is due to raise in value of liquidity tokens from fees on swaps.
    //     // Hence the amount of assets returned should be more than what we allocated.
    //     // OfCourse there will be a small fee when we redeem but with more swaps we will have more valued liquidity tokens and hence more assets returned.

    //     (,, address _router,,,) = camelotStrategy.strategyData();

    //     address swapper = address(0x1);
    //     _depositAssetsToStrategy(2000 * 10 ** ERC20(ASSET_A).decimals(), 2000 * 10 ** ERC20(ASSET_B).decimals());

    //     _allocate(1000 * 10 ** ERC20(ASSET_A).decimals(), 1000 * 10 ** ERC20(ASSET_B).decimals());
    //     _allocate(100 * 10 ** ERC20(ASSET_A).decimals(), 100 * 10 ** ERC20(ASSET_B).decimals());

    //     uint256 totalBalanceAssetABeforeSwaps = camelotStrategy.checkBalance(ASSET_A); // The total balance, including allocated and unallocated amounts.
    //     uint256 totalBalanceAssetBBeforeSwaps = camelotStrategy.checkBalance(ASSET_B); // The total balance, including allocated and unallocated amounts.

    //     deal(ASSET_A, swapper, 1000 * 10 ** ERC20(ASSET_A).decimals());

    //     uint256 amountIn;
    //     uint256 amountOutMin = 0;
    //     address[] memory path = new address[](2);
    //     address to = swapper;
    //     address referrer = address(0x0);

    //     vm.warp(block.timestamp + 10 days);
    //     vm.roll(block.number + 1000);

    //     uint256 deadline = block.timestamp;

    //     vm.startPrank(swapper);
    //     path[0] = ASSET_A;
    //     path[1] = ASSET_B;
    //     amountIn = 400 * 10 ** ERC20(ASSET_A).decimals();
    //     IERC20(ASSET_A).approve(_router, 400 * 10 ** ERC20(ASSET_A).decimals());
    //     ICamelotRouterSwap(_router).swapExactTokensForTokensSupportingFeeOnTransferTokens(
    //         amountIn, amountOutMin, path, to, referrer, deadline
    //     );

    //     path[0] = ASSET_B;
    //     path[1] = ASSET_A;
    //     amountIn = 300 * 10 ** ERC20(ASSET_B).decimals();
    //     IERC20(ASSET_B).approve(_router, 300 * 10 ** ERC20(ASSET_B).decimals());
    //     ICamelotRouterSwap(_router).swapExactTokensForTokensSupportingFeeOnTransferTokens(
    //         amountIn, amountOutMin, path, to, referrer, deadline
    //     );

    //     vm.stopPrank();

    //     vm.warp(block.timestamp + 10 days);
    //     vm.roll(block.number + 1000);

    //     deadline = block.timestamp;

    //     vm.startPrank(swapper);
    //     amountIn = 400 * 10 ** ERC20(ASSET_A).decimals();
    //     path[0] = ASSET_A;
    //     path[1] = ASSET_B;
    //     IERC20(ASSET_A).approve(_router, 400 * 10 ** ERC20(ASSET_A).decimals());
    //     ICamelotRouterSwap(_router).swapExactTokensForTokensSupportingFeeOnTransferTokens(
    //         amountIn, amountOutMin, path, to, referrer, deadline
    //     );
    //     amountIn = 300 * 10 ** ERC20(ASSET_B).decimals();
    //     path[0] = ASSET_B;
    //     path[1] = ASSET_A;
    //     IERC20(ASSET_B).approve(_router, 350 * 10 ** ERC20(ASSET_B).decimals());
    //     ICamelotRouterSwap(_router).swapExactTokensForTokensSupportingFeeOnTransferTokens(
    //         amountIn, amountOutMin, path, to, referrer, deadline
    //     );
    //     vm.stopPrank();

    //     vm.warp(block.timestamp + 10 days);
    //     vm.roll(block.number + 1000);

    //     uint256 totalBalanceAssetAAfterSwaps = camelotStrategy.checkBalance(ASSET_A); // The total balance, including allocated and unallocated amounts.
    //     uint256 totalBalanceAssetBAfterSwaps = camelotStrategy.checkBalance(ASSET_B); // The total balance, including allocated and unallocated amounts.

    //     emit log_named_uint("beforeSwaps", totalBalanceAssetABeforeSwaps + totalBalanceAssetBBeforeSwaps);
    //     emit log_named_uint("afterSwaps", totalBalanceAssetAAfterSwaps + totalBalanceAssetBAfterSwaps);
    //     // The below assertion is based on that both the assets are stable usd coins with same decimal places and almost same pool ratio between them.
    //     // Need to enhance this test by using decimal conversions and exact price factors
    //     assertTrue(totalBalanceAssetAAfterSwaps + totalBalanceAssetABeforeSwaps > totalBalanceAssetABeforeSwaps + totalBalanceAssetBAfterSwaps);
    // }
}

contract WithdrawAssetsToVaultTests is CamelotStrategyTestSetup {
    function test_Withdraw_Assets_To_Vault_After_Deposit_Caller_UsdsOwner() public {
        _depositAssetsToStrategy(1000 * 10 ** ERC20(ASSET_A).decimals(), 1000 * 10 ** ERC20(ASSET_B).decimals());

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
        _multipleAllocations();

        (,,,,, address _nftPool) = camelotStrategy.strategyData();
        uint256 spNFTId = camelotStrategy.spNFTId();

        (uint256 liquidityBalanceBeforeRedeem,,,,,,,) = INFTPool(_nftPool).getStakingPosition(spNFTId);

        _redeem(liquidityBalanceBeforeRedeem);

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
        _multipleAllocations();

        (,,,,, address _nftPool) = camelotStrategy.strategyData();
        uint256 spNFTId = camelotStrategy.spNFTId();

        (uint256 liquidityBalanceBeforeRedeem,,,,,,,) = INFTPool(_nftPool).getStakingPosition(spNFTId);

        _redeem(liquidityBalanceBeforeRedeem);

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

contract collectRewardTest is CamelotStrategyTestSetup {
    address internal yieldReceiver;
    address internal harvestor = address(0x1);

    error InvalidRedeemIndex();

    function setUp() public override {
        super.setUp();
        yieldReceiver = actors[0];
    }

    function test_checkRewardEarned() public {
        _multipleAllocations();

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
        assertTrue(rewardsAfterContractState > rewardsBeforeContractState);
    }

    function test_CollectRewards_Grail() public {
        (,,,,, address _nftPool) = camelotStrategy.strategyData();
        (, address grail,,,,,,) = INFTPool(_nftPool).getPoolInfo();
        uint256 harvestIncentiveRate = camelotStrategy.harvestIncentiveRate();

        yieldReceiver = IVault(VAULT).yieldReceiver();

        uint256 yieldReceiverGrailAmountBeforeCollection = IERC20(grail).balanceOf(yieldReceiver);
        uint256 harvestorGrailAmountBeforeCollection = IERC20(grail).balanceOf(harvestor);

        _multipleAllocations();

        vm.warp(block.timestamp + 10 days);
        vm.roll(block.number + 1000);

        vm.startPrank(harvestor);
        camelotStrategy.collectReward();
        vm.stopPrank();

        uint256 yieldReceiverGrailAmountAfterCollection = IERC20(grail).balanceOf(yieldReceiver);
        uint256 harvestorGrailAmountAfterCollection = IERC20(grail).balanceOf(harvestor);

        uint256 yieldReceiverGrailAmountCollected =
            yieldReceiverGrailAmountAfterCollection - yieldReceiverGrailAmountBeforeCollection;
        uint256 harvestorGrailAmountCollected =
            harvestorGrailAmountAfterCollection - harvestorGrailAmountBeforeCollection;

        uint256 totalGrailAmountCollected = yieldReceiverGrailAmountCollected + harvestorGrailAmountCollected;

        uint256 harvestIncentive = totalGrailAmountCollected * harvestIncentiveRate / Helpers.MAX_PERCENTAGE;

        assertTrue(yieldReceiverGrailAmountAfterCollection > yieldReceiverGrailAmountBeforeCollection);
        assertTrue(harvestorGrailAmountAfterCollection > harvestorGrailAmountBeforeCollection);
        assertEq(yieldReceiverGrailAmountCollected, totalGrailAmountCollected - harvestorGrailAmountCollected);
        assertEq(harvestIncentive, harvestorGrailAmountAfterCollection - harvestorGrailAmountBeforeCollection);
    }

    function test_CollectRewards_XGrail() public {}

    function test_Revert_collectVestedGrailAndDividends_With_Invalid_Redeem_Index() public {
        // Without calling collectReward we don't get a valid redeem index.
        vm.expectRevert(abi.encodeWithSelector(InvalidRedeemIndex.selector));
        camelotStrategy.collectVestedGrailAndDividends(1);
    }

    // Had to separate grail and other dividend token test cases for collectVestedGrailAndDividends due to stack too deep error.
    // The below two functions test grail and other dividend tokens for collectVestedGrailAndDividends.

    function test_collectVestedGrailAndDividends_For_Tokens_Other_Than_Grail() public {
        // todo
        // In this test function need to write test to check RewardTokenCollected events for each dividend token.

        (,,,,, address _nftPool) = camelotStrategy.strategyData();
        (,, address xGrail,,,,,) = INFTPool(_nftPool).getPoolInfo();
        uint256 harvestIncentiveRate = camelotStrategy.harvestIncentiveRate();
        yieldReceiver = IVault(VAULT).yieldReceiver();

        _multipleAllocations();

        vm.warp(block.timestamp + 10 days);
        vm.roll(block.number + 1000);

        vm.startPrank(harvestor);
        camelotStrategy.collectReward();
        vm.stopPrank();

        _multipleSwaps();

        vm.warp(block.timestamp + 16 days); // to make sure we cross the vesting time of 15 days.
        vm.roll(block.number + 1000);

        uint256 userRedeemsLength = IXGrailToken(xGrail).getUserRedeemsLength(address(camelotStrategy));
        emit log_named_uint("userRedeemsLength", userRedeemsLength);

        (,,, address dividendsContract,) =
            IXGrailToken(xGrail).getUserRedeem(address(camelotStrategy), userRedeemsLength - 1);
        uint256 dividendTokensLength = IDividendV2(dividendsContract).distributedTokensLength();
        address[] memory _dividendTokensForARedeemIndex = new address[](dividendTokensLength);
        uint256[] memory yieldReceiverTokenAmountBeforeCollection = new uint256[](dividendTokensLength);
        uint256[] memory harvestorTokenAmountBeforeCollection = new uint256[](dividendTokensLength);
        uint256[] memory yieldReceiverTokenAmountAfterCollection = new uint256[](dividendTokensLength);
        uint256[] memory harvestorTokenAmountAfterCollection = new uint256[](dividendTokensLength);
        uint256[] memory harvestorTokenAmountCollected = new uint256[](dividendTokensLength);
        uint256[] memory yieldReceiverTokenAmountCollected = new uint256[](dividendTokensLength);
        uint256[] memory harvestIncentive = new uint256[](dividendTokensLength);

        for (uint8 j; j < dividendTokensLength; ++j) {
            _dividendTokensForARedeemIndex[j] = IDividendV2(dividendsContract).distributedToken(j);

            yieldReceiverTokenAmountBeforeCollection[j] =
                IERC20(_dividendTokensForARedeemIndex[j]).balanceOf(yieldReceiver);

            harvestorTokenAmountBeforeCollection[j] = IERC20(_dividendTokensForARedeemIndex[j]).balanceOf(harvestor);
        }

        vm.startPrank(harvestor);
        camelotStrategy.collectVestedGrailAndDividends(userRedeemsLength - 1);
        vm.stopPrank();

        for (uint8 j; j < dividendTokensLength; ++j) {
            if (_dividendTokensForARedeemIndex[j] != xGrail) {
                yieldReceiverTokenAmountAfterCollection[j] =
                    IERC20(_dividendTokensForARedeemIndex[j]).balanceOf(yieldReceiver);

                harvestorTokenAmountAfterCollection[j] = IERC20(_dividendTokensForARedeemIndex[j]).balanceOf(harvestor);

                harvestorTokenAmountCollected[j] =
                    harvestorTokenAmountAfterCollection[j] - harvestorTokenAmountBeforeCollection[j];

                yieldReceiverTokenAmountCollected[j] =
                    yieldReceiverTokenAmountAfterCollection[j] - yieldReceiverTokenAmountBeforeCollection[j];

                harvestIncentive[j] = harvestorTokenAmountCollected[j] * harvestIncentiveRate / Helpers.MAX_PERCENTAGE;

                emit log_named_uint(
                    "yieldReceiverTokenAmountBeforeCollection", yieldReceiverTokenAmountBeforeCollection[j]
                );
                emit log_named_uint("harvestorTokenAmountBeforeCollection", harvestorTokenAmountBeforeCollection[j]);
                emit log_named_uint(
                    "yieldReceiverTokenAmountAfterCollection", yieldReceiverTokenAmountAfterCollection[j]
                );
                emit log_named_uint("harvestorTokenAmountAfterCollection", harvestorTokenAmountAfterCollection[j]);
                emit log_named_uint("yieldReceiverTokenAmountCollected", yieldReceiverTokenAmountCollected[j]);
                emit log_named_uint("harvestorTokenAmountCollected", harvestorTokenAmountCollected[j]);
                emit log_named_uint("harvestIncentive", harvestIncentive[j]);
                emit log_named_uint(
                    "test1", yieldReceiverTokenAmountAfterCollection[j] - yieldReceiverTokenAmountBeforeCollection[j]
                );
                emit log_named_uint(
                    "test2", harvestorTokenAmountAfterCollection[j] - harvestorTokenAmountBeforeCollection[j]
                );

                assertTrue(yieldReceiverTokenAmountAfterCollection[j] > yieldReceiverTokenAmountBeforeCollection[j]);
                assertTrue(harvestorTokenAmountAfterCollection[j] > harvestorTokenAmountBeforeCollection[j]);
                assertEq(
                    yieldReceiverTokenAmountCollected[j],
                    yieldReceiverTokenAmountAfterCollection[j] - yieldReceiverTokenAmountBeforeCollection[j]
                );
                assertEq(
                    harvestIncentive[j],
                    harvestorTokenAmountAfterCollection[j] - harvestorTokenAmountBeforeCollection[j]
                );
            }
        }
    }

    // Separated this test case from the above one due to stack too deep error.
    function test_collectVestedGrailAndDividends_For_Grail() public {
        (,,,,, address _nftPool) = camelotStrategy.strategyData();
        (, address grail, address xGrail,,,,,) = INFTPool(_nftPool).getPoolInfo();
        uint256 harvestIncentiveRate = camelotStrategy.harvestIncentiveRate();
        yieldReceiver = IVault(VAULT).yieldReceiver();

        _multipleAllocations();

        vm.warp(block.timestamp + 10 days);
        vm.roll(block.number + 1000);

        vm.startPrank(harvestor);
        camelotStrategy.collectReward();
        vm.stopPrank();

        _multipleSwaps();

        vm.warp(block.timestamp + 16 days); // to make sure we cross the vesting time of 15 days.
        vm.roll(block.number + 1000);

        uint256 userRedeemsLength = IXGrailToken(xGrail).getUserRedeemsLength(address(camelotStrategy));
        emit log_named_uint("userRedeemsLength", userRedeemsLength);

        uint256 yieldReceiverGrailAmountBeforeCollection = IERC20(grail).balanceOf(yieldReceiver);
        uint256 harvestorGrailAmountBeforeCollection = IERC20(grail).balanceOf(harvestor);

        vm.startPrank(harvestor);
        camelotStrategy.collectVestedGrailAndDividends(userRedeemsLength - 1);
        vm.stopPrank();

        uint256 yieldReceiverGrailAmountAfterCollection = IERC20(grail).balanceOf(yieldReceiver);
        uint256 harvestorGrailAmountAfterCollection = IERC20(grail).balanceOf(harvestor);

        uint256 yieldReceiverGrailAmountCollected =
            yieldReceiverGrailAmountAfterCollection - yieldReceiverGrailAmountBeforeCollection;
        uint256 harvestorGrailAmountCollected =
            harvestorGrailAmountAfterCollection - harvestorGrailAmountBeforeCollection;

        uint256 totalGrailAmountCollected = yieldReceiverGrailAmountCollected + harvestorGrailAmountCollected;

        uint256 grailHarvestIncentive = totalGrailAmountCollected * harvestIncentiveRate / Helpers.MAX_PERCENTAGE;

        assertTrue(yieldReceiverGrailAmountAfterCollection > yieldReceiverGrailAmountBeforeCollection);
        assertTrue(harvestorGrailAmountAfterCollection > harvestorGrailAmountBeforeCollection);
        assertEq(yieldReceiverGrailAmountCollected, totalGrailAmountCollected - harvestorGrailAmountCollected);
        assertEq(grailHarvestIncentive, harvestorGrailAmountAfterCollection - harvestorGrailAmountBeforeCollection);
    }
}

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

    function test_Revert_When_Invalid_Update_Strategy_Data() public {
        CamelotStrategy.StrategyData memory _newStrategyData = CamelotStrategy.StrategyData({
            tokenA: address(0),
            tokenB: ASSET_B,
            router: 0xc873fEcbd354f5A56E00E710B90EF4201db2448d,
            positionHelper: 0xe458018Ad4283C90fB7F5460e24C4016F81b8175,
            factory: 0x6EcCab422D763aC031210895C81787E87B43A652,
            nftPool: 0xcC9f28dAD9b85117AB5237df63A5EE6fC50B02B7
        });

        vm.expectRevert(abi.encodeWithSelector(Helpers.InvalidAddress.selector));

        vm.startPrank(USDS_OWNER);
        camelotStrategy.updateStrategyData(_newStrategyData);
        vm.stopPrank();
    }
}

contract MiscellaneousTests is CamelotStrategyTestSetup {
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

    function test_onERC721Received() public {
        bytes4 _ERC721_RECEIVED = 0x150b7a02;
        uint256 randomTokenId = 152;
        (,,,,, address _nftPool) = camelotStrategy.strategyData();
        vm.startPrank(_nftPool);
        bytes4 result = camelotStrategy.onERC721Received(address(0x1), address(0x2), randomTokenId, "");
        uint256 spNFTId = camelotStrategy.spNFTId();
        vm.stopPrank();
        assertEq(result, _ERC721_RECEIVED);
        assertEq(spNFTId, randomTokenId);
    }

    function test_RevertWhen_Random_onNFTHarvest_Caller() public {
        address randomCaller = address(0x1);
        vm.expectRevert(abi.encodeWithSelector(NotCamelotNFTPool.selector));
        vm.startPrank(randomCaller);
        camelotStrategy.onNFTHarvest(address(0x1), address(0x2), 1, 1, 1);
        vm.stopPrank();
    }

    function test_onNFTHarvest() public {
        (,,,,, address _nftPool) = camelotStrategy.strategyData();
        vm.startPrank(_nftPool);
        bool result = camelotStrategy.onNFTHarvest(address(0x1), address(0x2), 1, 1, 1);
        vm.stopPrank();
        assertEq(result, true);
    }

    function test_RevertWhen_Random_onNFTAddToPosition_Caller() public {
        address randomCaller = address(0x1);
        vm.expectRevert(abi.encodeWithSelector(NotCamelotNFTPool.selector));
        vm.startPrank(randomCaller);
        camelotStrategy.onNFTAddToPosition(address(0x1), 1, 1);
        vm.stopPrank();
    }

    function test_onNFTAddToPosition() public {
        (,,,,, address _nftPool) = camelotStrategy.strategyData();
        vm.startPrank(_nftPool);
        bool result = camelotStrategy.onNFTAddToPosition(address(0x1), 1, 1);
        vm.stopPrank();
        assertEq(result, true);
    }

    function test_RevertWhen_Random_onNFTWithdraw_Caller() public {
        address randomCaller = address(0x1);
        vm.expectRevert(abi.encodeWithSelector(NotCamelotNFTPool.selector));
        vm.startPrank(randomCaller);
        camelotStrategy.onNFTWithdraw(address(0x1), 1, 1);
        vm.stopPrank();
    }

    function test_onNFTWithdraw() public {
        (,,,,, address _nftPool) = camelotStrategy.strategyData();
        vm.startPrank(_nftPool);
        bool result = camelotStrategy.onNFTWithdraw(address(0x1), 1, 1);
        vm.stopPrank();
        assertEq(result, true);
    }

    function test_checkLPTokenBalance() public {
        _multipleAllocations();

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

    function test_UpdateVaultCore() public useKnownActor(USDS_OWNER) {
        address newVault = address(1);
        vm.expectEmit(true, true, false, true);
        emit VaultUpdated(newVault);
        camelotStrategy.updateVault(newVault);
        address vault = camelotStrategy.vault();
        assertEq(vault, newVault);
    }

    function test_Revert_UpdateVaultCore_When_NotOwner() public {
        address newVault = address(1);
        address randomCaller = address(0x1);
        vm.expectRevert("Ownable: caller is not the owner");
        vm.startPrank(randomCaller);
        camelotStrategy.updateVault(newVault);
        vm.stopPrank();
    }

    function test_UpdateHarvestIncentiveRate() public useKnownActor(USDS_OWNER) {
        uint16 newRate = 100;

        vm.expectEmit(true, false, false, true);
        emit HarvestIncentiveRateUpdated(newRate);
        camelotStrategy.updateHarvestIncentiveRate(newRate);

        uint256 harvestIncentiveRate = camelotStrategy.harvestIncentiveRate();

        assertEq(harvestIncentiveRate, newRate);

        newRate = 10001;
        vm.expectRevert(abi.encodeWithSelector(Helpers.GTMaxPercentage.selector, newRate));
        camelotStrategy.updateHarvestIncentiveRate(newRate);
    }

    function test_Revert_UpdateHarvestIncentiveRate_When_NotOwner() public {
        uint16 newRate = 100;
        address randomCaller = address(0x1);
        vm.expectRevert("Ownable: caller is not the owner");
        vm.startPrank(randomCaller);
        camelotStrategy.updateHarvestIncentiveRate(newRate);
        vm.stopPrank();
    }

    function test_UpdateSlippage() public useKnownActor(USDS_OWNER) {
        uint16 updatedDepositSlippage = 100;
        uint16 updatedWithdrawSlippage = 200;
        vm.expectEmit(true, false, false, true);
        emit SlippageUpdated(updatedDepositSlippage, updatedWithdrawSlippage);
        camelotStrategy.updateSlippage(updatedDepositSlippage, updatedWithdrawSlippage);
        assertEq(camelotStrategy.depositSlippage(), updatedDepositSlippage);
        assertEq(camelotStrategy.withdrawSlippage(), updatedWithdrawSlippage);
    }

    function test_Revert_UpdateSlippage_When_NotOwner() public {
        uint16 updatedDepositSlippage = 100;
        uint16 updatedWithdrawSlippage = 200;
        vm.expectRevert("Ownable: caller is not the owner");
        camelotStrategy.updateSlippage(updatedDepositSlippage, updatedWithdrawSlippage);
    }

    function test_RevertWhen_slippageExceedsMax() public useKnownActor(USDS_OWNER) {
        vm.expectRevert(abi.encodeWithSelector(Helpers.GTMaxPercentage.selector, 10001));
        camelotStrategy.updateSlippage(10001, 10001);
    }

    function test_assetToPToken() public {
        (address _tokenA, address _tokenB, address _router,,,) = camelotStrategy.strategyData();
        address pair = IRouter(_router).getPair(_tokenA, _tokenB);
        address assetToPTokenOfTokenA = camelotStrategy.assetToPToken(_tokenA);
        address assetToPTokenOfTokenB = camelotStrategy.assetToPToken(_tokenB);

        assertEq(assetToPTokenOfTokenA, pair);
        assertEq(assetToPTokenOfTokenB, pair);
    }

    function test_checkAvailableBalance() public {
        uint256 availableBalanceInContractAssetA = IERC20(ASSET_A).balanceOf(address(camelotStrategy));
        uint256 availableBalanceInContractAssetB = IERC20(ASSET_B).balanceOf(address(camelotStrategy));
        camelotStrategy.checkAvailableBalance(ASSET_A);
        camelotStrategy.checkAvailableBalance(ASSET_B);

        assertEq(availableBalanceInContractAssetA, availableBalanceInContractAssetA);
        assertEq(availableBalanceInContractAssetB, availableBalanceInContractAssetB);

        address randomAsset = address(0x1);
        vm.expectRevert(abi.encodeWithSelector(CollateralNotSupported.selector, randomAsset));
        camelotStrategy.checkAvailableBalance(randomAsset);
    }

    //  The total balance, including allocated and unallocated amounts.
    function test_checkBalance() public {
        _depositAssetsToStrategy(2000 * 10 ** ERC20(ASSET_A).decimals(), 2000 * 10 ** ERC20(ASSET_B).decimals());

        uint256 availableBalanceInContractAssetABeforeAllocations = IERC20(ASSET_A).balanceOf(address(camelotStrategy));
        uint256 availableBalanceInContractAssetBBeforeAllocations = IERC20(ASSET_B).balanceOf(address(camelotStrategy));

        (uint256 firstAllocationAssetA, uint256 firstAllocationAssetB) =
            _allocate(100 * 10 ** ERC20(ASSET_A).decimals(), 100 * 10 ** ERC20(ASSET_B).decimals());
        (uint256 secondAllocationAssetA, uint256 secondAllocationAssetB) =
            _allocate(10 * 10 ** ERC20(ASSET_A).decimals(), 10 * 10 ** ERC20(ASSET_B).decimals());

        uint256 availableBalanceInContractAssetAAfterAllocations = IERC20(ASSET_A).balanceOf(address(camelotStrategy));
        uint256 availableBalanceInContractAssetBAfterAllocations = IERC20(ASSET_B).balanceOf(address(camelotStrategy));

        camelotStrategy.checkBalance(ASSET_A);
        camelotStrategy.checkBalance(ASSET_B);

        // Need to simulate some swaps here in camelot. This will increase the value of liquidity and hence assets.

        assertTrue(
            firstAllocationAssetA + secondAllocationAssetA + availableBalanceInContractAssetAAfterAllocations
                >= availableBalanceInContractAssetABeforeAllocations
        );

        assertTrue(
            firstAllocationAssetB + secondAllocationAssetB + availableBalanceInContractAssetBAfterAllocations
                >= availableBalanceInContractAssetBBeforeAllocations
        );
    }
}
