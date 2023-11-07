// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {BaseStrategy} from "./BaseStrategy.t.sol";
import {BaseTest} from "../utils/BaseTest.t.sol";
import {UpgradeUtil} from "../utils/UpgradeUtil.t.sol";
import {UniswapStrategy} from "../../contracts/strategies/uniswap/UniswapStrategy.sol";
import {INonfungiblePositionManager} from "../../contracts/strategies/uniswap/interfaces/UniswapV3.sol";
import {InitializableAbstractStrategy, Helpers} from "../../contracts/strategies/InitializableAbstractStrategy.sol";
import {IERC20, ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {
    IUniswapV3Factory,
    INonfungiblePositionManager as INFPM
} from "../../contracts/strategies/uniswap/interfaces/UniswapV3.sol";
import {IUniswapUtils} from "../../contracts/strategies/uniswap/interfaces/IUniswapUtils.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {VmSafe} from "forge-std/Vm.sol";

address constant UNISWAP_V3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
address constant NONFUNGIBLE_POSITION_MANAGER = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
address constant UNISWAP_UTILS = 0xd2Aa19D3B7f8cdb1ea5B782c5647542055af415e;
address constant SWAP_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
address constant DUMMY_ADDRESS = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
uint24 constant FEE = 500;
int24 constant TICK_LOWER = -887270;
int24 constant TICK_UPPER = 887270;

contract UniswapStrategyTest is BaseStrategy, BaseTest {
    struct AssetData {
        string name;
        address asset;
    }

    AssetData[] public data;

    UniswapStrategy internal strategy;
    UniswapStrategy internal impl;
    UpgradeUtil internal upgradeUtil;
    uint16 internal constant DEPOSIT_SLIPPAGE = 100;
    uint256 internal depositAmount1;
    uint256 internal depositAmount2;
    address internal proxyAddress;
    address internal yieldReceiver;
    address internal ASSET_1;
    address internal ASSET_2;
    address internal constant P_TOKEN = NONFUNGIBLE_POSITION_MANAGER;
    IUniswapV3Pool POOL;

    // Events
    event MintNewPosition(uint256 tokenId);
    event IncreaseLiquidity(uint256 liquidity, uint256 amount0, uint256 amount1);
    event DecreaseLiquidity(uint256 liquidity, uint256 amount0, uint256 amount1);

    // Custom errors
    error InvalidUniswapPoolConfig();
    error NoRewardIncentive();
    error NotUniv3NFT();
    error NotSelf();
    error InvalidTickRange();

    function setUp() public virtual override {
        super.setUp();
        setArbitrumFork();
        yieldReceiver = actors[0];
        vm.startPrank(USDS_OWNER);
        impl = new UniswapStrategy();
        upgradeUtil = new UpgradeUtil();
        proxyAddress = upgradeUtil.deployErc1967Proxy(address(impl));

        strategy = UniswapStrategy(proxyAddress);
        _configAsset();
        ASSET_1 = data[0].asset;
        ASSET_2 = data[1].asset;
        depositAmount1 = 1e6 * 10 ** ERC20(ASSET_1).decimals();
        depositAmount2 = 1e6 * 10 ** ERC20(ASSET_2).decimals();

        POOL = IUniswapV3Pool(IUniswapV3Factory(UNISWAP_V3_FACTORY).getPool(ASSET_1, ASSET_2, FEE));

        vm.stopPrank();
    }

    function _initializeStrategy() internal {
        UniswapStrategy.UniswapPoolData memory poolData = UniswapStrategy.UniswapPoolData(
            ASSET_1,
            ASSET_2,
            FEE,
            TICK_LOWER,
            TICK_UPPER,
            INFPM(NONFUNGIBLE_POSITION_MANAGER),
            IUniswapV3Factory(UNISWAP_V3_FACTORY),
            POOL,
            IUniswapUtils(UNISWAP_UTILS),
            0
        );
        strategy.initialize(VAULT, poolData, DEPOSIT_SLIPPAGE);
    }

    function _deposit() internal {
        changePrank(VAULT);
        deal(address(ASSET_1), VAULT, depositAmount1);
        IERC20(ASSET_1).approve(address(strategy), depositAmount1);
        strategy.deposit(ASSET_1, depositAmount1);

        deal(address(ASSET_2), VAULT, depositAmount2);
        IERC20(ASSET_2).approve(address(strategy), depositAmount2);
        strategy.deposit(ASSET_2, depositAmount2);
        changePrank(USDS_OWNER);
    }

    function _allocate() internal {
        uint256[2] memory amounts = [depositAmount1, depositAmount2];
        strategy.allocate(amounts);
    }

    function _redeem() internal {
        (,,,,,,,,, uint256 lpTokenId) = strategy.uniswapPoolData();
        (,,,,,,, uint128 liquidity,,,,) = INonfungiblePositionManager(NONFUNGIBLE_POSITION_MANAGER).positions(lpTokenId);
        uint256[2] memory minBurnAmount = [uint256(0), uint256(0)];
        strategy.redeem(liquidity, minBurnAmount);
    }

    function _withdraw() internal {
        changePrank(VAULT);
        uint256 availableBal1 = IERC20(ASSET_1).balanceOf(address(strategy));
        strategy.withdraw(VAULT, ASSET_1, availableBal1);

        uint256 availableBal2 = IERC20(ASSET_2).balanceOf(address(strategy));
        strategy.withdraw(VAULT, ASSET_2, availableBal2);
        changePrank(USDS_OWNER);
    }

    function _swap(address inputToken, address outputToken, uint24 poolFee, uint256 amountIn)
        internal
        returns (uint256 amountOut)
    {
        deal(address(inputToken), currentActor, amountIn);

        IERC20(inputToken).approve(address(SWAP_ROUTER), amountIn);
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: inputToken,
            tokenOut: outputToken,
            fee: poolFee,
            recipient: currentActor,
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });
        // Executes the swap.
        amountOut = ISwapRouter(SWAP_ROUTER).exactInputSingle(params);
    }

    function _simulateSwap() internal {
        _swap(ASSET_1, ASSET_2, FEE, depositAmount1);
        _swap(ASSET_2, ASSET_1, FEE, depositAmount2);
    }

    function _configAsset() internal {
        data.push(AssetData({name: "DAI", asset: 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1}));
        data.push(AssetData({name: "USDC.e", asset: 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8}));
    }
}

contract InitializeTests is UniswapStrategyTest {
    function test_empty_address() public useKnownActor(USDS_OWNER) {
        UniswapStrategy.UniswapPoolData memory poolData = UniswapStrategy.UniswapPoolData(
            ASSET_1,
            ASSET_2,
            FEE,
            TICK_LOWER,
            TICK_UPPER,
            INFPM(NONFUNGIBLE_POSITION_MANAGER),
            IUniswapV3Factory(UNISWAP_V3_FACTORY),
            POOL,
            IUniswapUtils(UNISWAP_UTILS),
            0
        );
        vm.expectRevert(abi.encodeWithSelector(Helpers.InvalidAddress.selector));
        strategy.initialize(address(0), poolData, DEPOSIT_SLIPPAGE);

        vm.expectRevert();
        poolData.uniV3Factory = IUniswapV3Factory(address(0));
        strategy.initialize(VAULT, poolData, DEPOSIT_SLIPPAGE);

        vm.expectRevert();
        poolData.uniV3Factory = IUniswapV3Factory(UNISWAP_V3_FACTORY);
        poolData.uniswapUtils = IUniswapUtils(address(0));
        strategy.initialize(VAULT, poolData, DEPOSIT_SLIPPAGE);
    }

    function test_RevertWhen_InvalidUniswapPoolConfig() public useKnownActor(USDS_OWNER) {
        UniswapStrategy.UniswapPoolData memory poolData = UniswapStrategy.UniswapPoolData(
            ASSET_1,
            ASSET_2,
            1, // invalid fee
            TICK_LOWER,
            TICK_UPPER,
            INFPM(NONFUNGIBLE_POSITION_MANAGER),
            IUniswapV3Factory(UNISWAP_V3_FACTORY),
            POOL,
            IUniswapUtils(UNISWAP_UTILS),
            0
        );

        vm.expectRevert(abi.encodeWithSelector(InvalidUniswapPoolConfig.selector));
        strategy.initialize(VAULT, poolData, DEPOSIT_SLIPPAGE);
    }

    function test_RevertWhen_InvalidTickRange() public useKnownActor(USDS_OWNER) {
        UniswapStrategy.UniswapPoolData memory poolData = UniswapStrategy.UniswapPoolData(
            ASSET_1,
            ASSET_2,
            FEE,
            -887273, // invalid tickLower
            TICK_UPPER,
            INFPM(NONFUNGIBLE_POSITION_MANAGER),
            IUniswapV3Factory(UNISWAP_V3_FACTORY),
            POOL,
            IUniswapUtils(UNISWAP_UTILS),
            0
        );

        vm.expectRevert(abi.encodeWithSelector(InvalidTickRange.selector));
        strategy.initialize(VAULT, poolData, DEPOSIT_SLIPPAGE);
    }

    function test_Initialize() public useKnownActor(USDS_OWNER) {
        assertEq(impl.owner(), address(0));
        assertEq(strategy.owner(), address(0));

        UniswapStrategy.UniswapPoolData memory poolData = UniswapStrategy.UniswapPoolData(
            ASSET_2, // passing asset2 first to check if the contract swaps it
            ASSET_1,
            FEE,
            TICK_LOWER,
            TICK_UPPER,
            INFPM(NONFUNGIBLE_POSITION_MANAGER),
            IUniswapV3Factory(UNISWAP_V3_FACTORY),
            POOL,
            IUniswapUtils(UNISWAP_UTILS),
            0
        );
        strategy.initialize(VAULT, poolData, DEPOSIT_SLIPPAGE);

        assertEq(impl.owner(), address(0));
        assertEq(strategy.owner(), USDS_OWNER);
        assertEq(strategy.vault(), VAULT);
        (
            address tokenA,
            address tokenB,
            uint24 feeTier,
            int24 tickLower,
            int24 tickUpper,
            INFPM nfpm,
            IUniswapV3Factory uniV3Factory,
            IUniswapV3Pool pool,
            IUniswapUtils uniswapUtils,
            uint256 lpTokenId
        ) = strategy.uniswapPoolData();
        assertEq(tokenA, ASSET_1);
        assertEq(tokenB, ASSET_2);
        assertEq(feeTier, FEE);
        assertEq(tickLower, TICK_LOWER);
        assertEq(tickUpper, TICK_UPPER);
        assertEq(address(nfpm), NONFUNGIBLE_POSITION_MANAGER);
        assertEq(address(uniV3Factory), UNISWAP_V3_FACTORY);
        assertEq(address(pool), address(POOL));
        assertEq(address(uniswapUtils), UNISWAP_UTILS);
        assertEq(lpTokenId, 0);

        assertEq(strategy.assetToPToken(ASSET_1), P_TOKEN);
        assertEq(strategy.assetToPToken(ASSET_2), P_TOKEN);

        assertTrue(strategy.supportsCollateral(ASSET_1));
        assertTrue(strategy.supportsCollateral(ASSET_2));
        assertFalse(strategy.supportsCollateral(DUMMY_ADDRESS));
    }
}

contract DepositTests is UniswapStrategyTest {
    function setUp() public override {
        super.setUp();
        vm.startPrank(USDS_OWNER);
        _initializeStrategy();
        vm.stopPrank();
    }

    function test_deposit_Collateral_not_supported() public useKnownActor(VAULT) {
        vm.expectRevert(abi.encodeWithSelector(CollateralNotSupported.selector, DUMMY_ADDRESS));
        strategy.deposit(DUMMY_ADDRESS, 1);
    }

    function test_RevertWhen_InvalidAmount() public useKnownActor(VAULT) {
        vm.expectRevert(abi.encodeWithSelector(Helpers.InvalidAmount.selector));
        strategy.deposit(ASSET_1, 0);
    }

    function test_Deposit() public useKnownActor(VAULT) {
        uint256 initialBal1 = IERC20(ASSET_1).balanceOf(address(strategy));

        deal(address(ASSET_1), VAULT, depositAmount1);
        IERC20(ASSET_1).approve(address(strategy), depositAmount1);

        vm.expectEmit(true, true, true, true, address(strategy));
        emit Deposit(ASSET_1, depositAmount1);

        strategy.deposit(ASSET_1, depositAmount1);

        uint256 new_bal_1 = IERC20(ASSET_1).balanceOf(address(strategy));
        assertEq(initialBal1 + depositAmount1, new_bal_1);
    }
}

contract AllocateTests is UniswapStrategyTest {
    function setUp() public override {
        super.setUp();
        vm.startPrank(USDS_OWNER);
        _initializeStrategy();
        _deposit();
        vm.stopPrank();
    }

    function test_RevertWhen_ZeroAmounts() public useKnownActor(USDS_OWNER) {
        uint256[2] memory amounts = [uint256(0), uint256(0)];
        vm.expectRevert(abi.encodeWithSelector(Helpers.InvalidAmount.selector));
        strategy.allocate(amounts);
    }

    function test_Allocate_MintNewPositionAndLiquidity() public useKnownActor(VAULT) {
        (,,,,,,,,, uint256 lpTokenId) = strategy.uniswapPoolData();
        uint256 initialBal1 = IERC20(ASSET_1).balanceOf(address(strategy));
        uint256 initialBal2 = IERC20(ASSET_2).balanceOf(address(strategy));
        uint256 oldAllocatedAmt1 = strategy.checkBalance(ASSET_1) - initialBal1;
        uint256 oldAllocatedAmt2 = strategy.checkBalance(ASSET_2) - initialBal2;
        assertEq(lpTokenId, 0);
        assertEq(oldAllocatedAmt1, 0);
        assertEq(oldAllocatedAmt2, 0);

        uint256[2] memory amounts = [depositAmount1, depositAmount2];

        vm.recordLogs();
        strategy.allocate(amounts);

        VmSafe.Log[] memory logs = vm.getRecordedLogs();
        uint256 expectedTokenId;
        uint256 expectedLiquidity;
        uint256 expectedAmountA;
        uint256 expectedAmountB;
        for (uint8 j = 0; j < logs.length; ++j) {
            if (logs[j].topics[0] == keccak256("MintNewPosition(uint256)")) {
                (expectedTokenId) = abi.decode(logs[j].data, (uint256));
            }
            if (logs[j].topics[0] == keccak256("IncreaseLiquidity(uint256,uint256,uint256)")) {
                (expectedLiquidity, expectedAmountA, expectedAmountB) =
                    abi.decode(logs[j].data, (uint256, uint256, uint256));
            }
        }
        (,,,,,,,,, uint256 mintedTokenId) = strategy.uniswapPoolData();
        assertNotEq(mintedTokenId, 0);
        assertEq(mintedTokenId, expectedTokenId);

        (,,,,,,, uint128 mintedLiquidity,,,,) = INFPM(NONFUNGIBLE_POSITION_MANAGER).positions(mintedTokenId);
        assertEq(uint256(mintedLiquidity), expectedLiquidity, "Liquidity mismatch");
        uint256 new_bal_1 = IERC20(ASSET_1).balanceOf(address(strategy));
        uint256 new_bal_2 = IERC20(ASSET_2).balanceOf(address(strategy));
        assertApproxEqAbs(strategy.checkBalance(ASSET_1) - new_bal_1, expectedAmountA, 1);
        assertApproxEqAbs(strategy.checkBalance(ASSET_2) - new_bal_2, expectedAmountB, 1);
    }

    function test_Allocate_IncreaseLiquidity() public useKnownActor(USDS_OWNER) {
        _allocate();
        _deposit();
        (,,,,,,,,, uint256 lpTokenId) = strategy.uniswapPoolData();
        uint256 oldAllocatedAmt1 = strategy.checkBalance(ASSET_1) - IERC20(ASSET_1).balanceOf(address(strategy));
        uint256 oldAllocatedAmt2 = strategy.checkBalance(ASSET_2) - IERC20(ASSET_2).balanceOf(address(strategy));
        (,,,,,,, uint128 oldLiquidity,,,,) = INFPM(NONFUNGIBLE_POSITION_MANAGER).positions(lpTokenId);

        uint256[2] memory amounts = [depositAmount1, depositAmount2];

        vm.recordLogs();
        strategy.allocate(amounts);

        VmSafe.Log[] memory logs = vm.getRecordedLogs();
        uint256 mintedLiquidity;
        uint256 expectedAmountA;
        uint256 expectedAmountB;
        for (uint8 j = 0; j < logs.length; ++j) {
            if (logs[j].topics[0] == keccak256("IncreaseLiquidity(uint256,uint256,uint256)")) {
                (mintedLiquidity, expectedAmountA, expectedAmountB) =
                    abi.decode(logs[j].data, (uint256, uint256, uint256));
            }
        }

        (,,,,,,, uint128 newLiquidity,,,,) = INFPM(NONFUNGIBLE_POSITION_MANAGER).positions(lpTokenId);
        assertEq(newLiquidity - oldLiquidity, mintedLiquidity);

        (,,,,,,,,, uint256 newLpTokenId) = strategy.uniswapPoolData();
        assertEq(newLpTokenId, lpTokenId);

        uint256 newAllocatedAmt1 = strategy.checkBalance(ASSET_1) - IERC20(ASSET_1).balanceOf(address(strategy));
        uint256 newAllocatedAmt2 = strategy.checkBalance(ASSET_2) - IERC20(ASSET_2).balanceOf(address(strategy));
        assertEq(newAllocatedAmt1 - oldAllocatedAmt1, expectedAmountA, "Amount A mismatch");
        assertEq(newAllocatedAmt2 - oldAllocatedAmt2, expectedAmountB, "Amount B mismatch");
    }
}

contract RedeemTests is UniswapStrategyTest {
    function setUp() public override {
        super.setUp();
        vm.startPrank(USDS_OWNER);
        _initializeStrategy();
        _deposit();
        _allocate();
        vm.stopPrank();
    }

    function test_Redeem_fullLiquidity() public useKnownActor(USDS_OWNER) {
        uint256 initialBal1 = IERC20(ASSET_1).balanceOf(address(strategy));
        uint256 initialBal2 = IERC20(ASSET_2).balanceOf(address(strategy));

        (,,,,,,,,, uint256 lpTokenId) = strategy.uniswapPoolData();
        (,,,,,,, uint128 oldLiquidity,,,,) =
            INonfungiblePositionManager(NONFUNGIBLE_POSITION_MANAGER).positions(lpTokenId);
        assertTrue(oldLiquidity != 0, "Liquidity is 0");

        uint256 availableAmount0 = strategy.checkBalance(ASSET_1) - initialBal1;
        uint256 availableAmount1 = strategy.checkBalance(ASSET_2) - initialBal2;
        uint256[2] memory minAmountOut;
        (minAmountOut[0], minAmountOut[1]) = strategy.getAmountsForLiquidity(oldLiquidity);
        vm.recordLogs();
        strategy.redeem(oldLiquidity, minAmountOut);

        uint256 _decreasedLiquidity;
        uint256 _amount0;
        uint256 _amount1;
        VmSafe.Log[] memory logs = vm.getRecordedLogs();
        for (uint8 j; j < logs.length; ++j) {
            if (logs[j].topics[0] == keccak256("DecreaseLiquidity(uint256,uint256,uint256)")) {
                (_decreasedLiquidity, _amount0, _amount1) = abi.decode(logs[j].data, (uint256, uint256, uint256));
            }
        }

        assertTrue(_amount0 >= minAmountOut[0], "Slippage error for asset 1");
        assertTrue(_amount1 >= minAmountOut[1], "Slippage error for asset 2");

        assertEq(_decreasedLiquidity, oldLiquidity, "Liquidity mismatch");
        assertEq(_amount0, availableAmount0, "amount0 mismatch");
        assertEq(_amount1, availableAmount1, "amount1 mismatch");

        (,,,,,,, uint128 newLiquidity,,,,) =
            INonfungiblePositionManager(NONFUNGIBLE_POSITION_MANAGER).positions(lpTokenId);
        assertEq(newLiquidity, 0, "Pending liquidity");
        assertEq(strategy.checkAvailableBalance(ASSET_1) - initialBal1, _amount0, "Asset 1 not received");
        assertEq(strategy.checkAvailableBalance(ASSET_2) - initialBal2, _amount1, "Asset 2 not received");
    }

    function test_Redeem_partialLiquidity() public useKnownActor(USDS_OWNER) {
        uint256 initialBal1 = IERC20(ASSET_1).balanceOf(address(strategy));
        uint256 initialBal2 = IERC20(ASSET_2).balanceOf(address(strategy));
        uint256 oldAllocatedAmt1 = strategy.checkBalance(ASSET_1) - initialBal1;
        uint256 oldAllocatedAmt2 = strategy.checkBalance(ASSET_2) - initialBal2;

        (,,,,,,,,, uint256 lpTokenId) = strategy.uniswapPoolData();
        (,,,,,,, uint128 oldLiquidity,,,,) =
            INonfungiblePositionManager(NONFUNGIBLE_POSITION_MANAGER).positions(lpTokenId);
        assertTrue(oldLiquidity != 0, "Liquidity is 0");

        uint256[2] memory minAmountOut;
        (minAmountOut[0], minAmountOut[1]) = strategy.getAmountsForLiquidity(oldLiquidity / 2);

        vm.recordLogs();
        strategy.redeem(oldLiquidity / 2, minAmountOut);

        uint256 _decreasedLiquidity;
        uint256 _amount0;
        uint256 _amount1;
        VmSafe.Log[] memory logs = vm.getRecordedLogs();
        for (uint8 j; j < logs.length; ++j) {
            if (logs[j].topics[0] == keccak256("DecreaseLiquidity(uint256,uint256,uint256)")) {
                (_decreasedLiquidity, _amount0, _amount1) = abi.decode(logs[j].data, (uint256, uint256, uint256));
            }
        }

        assertTrue(_amount0 >= minAmountOut[0], "Slippage error for asset 1");
        assertTrue(_amount1 >= minAmountOut[1], "Slippage error for asset 2");

        assertEq(_decreasedLiquidity, oldLiquidity / 2, "Liquidity mismatch");
        assertEq(_amount0, oldAllocatedAmt1 / 2, "amount0 mismatch");
        assertEq(_amount1, oldAllocatedAmt2 / 2, "amount1 mismatch");

        (,,,,,,, uint128 newLiquidity,,,,) =
            INonfungiblePositionManager(NONFUNGIBLE_POSITION_MANAGER).positions(lpTokenId);
        assertEq(newLiquidity, oldLiquidity / 2, "Pending liquidity");

        assertEq(strategy.checkAvailableBalance(ASSET_1) - initialBal1, _amount0, "Asset 1 not received");
        assertEq(strategy.checkAvailableBalance(ASSET_2) - initialBal2, _amount1, "Asset 2 not received");

        assertEq(
            strategy.checkBalance(ASSET_1) - initialBal1 - _amount0, _amount0, "Insufficient asset 1 allocated balance"
        );
        assertEq(
            strategy.checkBalance(ASSET_2) - initialBal2 - _amount1, _amount1, "Insufficient asset 2 allocated balance"
        );
    }
}

contract CollectInterestTests is UniswapStrategyTest {
    function setUp() public override {
        super.setUp();
        vm.startPrank(USDS_OWNER);
        _initializeStrategy();
        _deposit();
        _allocate();
        vm.stopPrank();
    }

    function test_RevertWhen_InvalidLPToken() public useActor(0) {
        vm.expectRevert();
        strategy.collectInterest(DUMMY_ADDRESS);
    }

    function test_CollectInterest() public useActor(1) {
        _simulateSwap();

        uint256[2] memory initialBal =
            [IERC20(ASSET_1).balanceOf(yieldReceiver), IERC20(ASSET_2).balanceOf(yieldReceiver)];
        uint256[2] memory initialSenderBal =
            [IERC20(ASSET_1).balanceOf(currentActor), IERC20(ASSET_2).balanceOf(currentActor)];

        vm.mockCall(VAULT, abi.encodeWithSignature("yieldReceiver()"), abi.encode(yieldReceiver));

        uint256[2] memory interestEarned =
            [strategy.checkInterestEarned(ASSET_1), strategy.checkInterestEarned(ASSET_2)];

        assertTrue(interestEarned[0] > 0, "Insufficient interest 0");
        assertTrue(interestEarned[1] > 0, "Insufficient interest 1");

        uint256 incentiveAmt1 = (interestEarned[0] * 10) / 10000;
        uint256 harvestAmount1 = interestEarned[0] - incentiveAmt1;
        uint256 incentiveAmt2 = (interestEarned[1] * 10) / 10000;
        uint256 harvestAmount2 = interestEarned[1] - incentiveAmt2;

        vm.expectEmit(true, true, true, true, address(strategy));
        emit InterestCollected(ASSET_1, yieldReceiver, harvestAmount1);
        vm.expectEmit(true, true, true, true, address(strategy));
        emit InterestCollected(ASSET_2, yieldReceiver, harvestAmount2);
        strategy.collectInterest(DUMMY_ADDRESS);

        assertEq(strategy.checkInterestEarned(ASSET_1), 0);
        assertEq(strategy.checkInterestEarned(ASSET_1), 0);
        assertEq(IERC20(ASSET_1).balanceOf(yieldReceiver), (initialBal[0] + harvestAmount1));
        assertEq(IERC20(ASSET_2).balanceOf(yieldReceiver), (initialBal[1] + harvestAmount2));
        assertEq(IERC20(ASSET_1).balanceOf(currentActor), (initialSenderBal[0] + incentiveAmt1));
        assertEq(IERC20(ASSET_2).balanceOf(currentActor), (initialSenderBal[1] + incentiveAmt2));
    }
}

contract WithdrawTests is UniswapStrategyTest {
    function setUp() public override {
        super.setUp();
        vm.startPrank(USDS_OWNER);
        _initializeStrategy();
        _deposit();
        _allocate();
        _redeem();
        vm.stopPrank();
    }

    function test_RevertWhen_Withdraw0() public useKnownActor(USDS_OWNER) {
        _withdraw();
        vm.expectRevert(abi.encodeWithSelector(Helpers.CustomError.selector, "Must withdraw something"));
        strategy.withdrawToVault(ASSET_1, 0);
    }

    function test_RevertWhen_InvalidAddress() public useKnownActor(VAULT) {
        vm.expectRevert(abi.encodeWithSelector(Helpers.InvalidAddress.selector));
        strategy.withdraw(address(0), ASSET_1, 1);
    }

    function test_RevertWhen_CallerNotVault() public useActor(0) {
        vm.expectRevert(abi.encodeWithSelector(CallerNotVault.selector, actors[0]));
        strategy.withdraw(VAULT, ASSET_1, 1);
    }

    function test_RevertWhen_NotSupportedCollateral() public useKnownActor(VAULT) {
        vm.expectRevert(abi.encodeWithSelector(CollateralNotSupported.selector, DUMMY_ADDRESS));
        strategy.withdraw(
            VAULT,
            DUMMY_ADDRESS, // invalid collateral
            1
        );
    }

    function test_Withdraw() public useKnownActor(VAULT) {
        uint256 initialVaultBal = IERC20(ASSET_1).balanceOf(VAULT);
        uint256 availableBal = IERC20(ASSET_1).balanceOf(address(strategy));

        vm.expectEmit(true, false, false, true);
        emit Withdrawal(ASSET_1, availableBal);

        strategy.withdraw(VAULT, ASSET_1, availableBal);
        assertEq(initialVaultBal + availableBal, IERC20(ASSET_1).balanceOf(VAULT));
    }
}

contract WithdrawToVaultTests is UniswapStrategyTest {
    function setUp() public override {
        super.setUp();
        vm.startPrank(USDS_OWNER);
        _initializeStrategy();
        _deposit();
        _allocate();
        _redeem();
        vm.stopPrank();
    }

    function test_RevertWhen_CallerNotOwner() public useActor(0) {
        vm.expectRevert(abi.encodeWithSelector(CallerNotVault.selector, actors[0]));
        strategy.withdraw(VAULT, ASSET_1, 1);
    }

    function test_WithdrawToVault() public useKnownActor(USDS_OWNER) {
        uint256 initialVaultBal = IERC20(ASSET_1).balanceOf(VAULT);
        uint256 availableBal = IERC20(ASSET_1).balanceOf(address(strategy));

        vm.expectEmit(true, false, false, true);
        emit Withdrawal(ASSET_1, availableBal);

        strategy.withdrawToVault(ASSET_1, availableBal);
        assertEq(initialVaultBal + availableBal, IERC20(ASSET_1).balanceOf(VAULT));
    }
}

contract OnERC721ReceivedTests is UniswapStrategyTest {
    function setUp() public override {
        super.setUp();
        vm.startPrank(USDS_OWNER);
        _initializeStrategy();
        vm.stopPrank();
    }

    function test_RevertWhen_NotUniV3NFT() public useActor(0) {
        vm.expectRevert(abi.encodeWithSelector(NotUniv3NFT.selector));
        strategy.onERC721Received(address(0), address(0), 0, "");
    }

    function test_RevertWhen_NotSelf() public useKnownActor(NONFUNGIBLE_POSITION_MANAGER) {
        vm.expectRevert(abi.encodeWithSelector(NotSelf.selector));
        strategy.onERC721Received(DUMMY_ADDRESS, address(0), 0, "");
    }

    function test_OnERC721Received() public useKnownActor(NONFUNGIBLE_POSITION_MANAGER) {
        assertEq(
            strategy.onERC721Received(address(strategy), address(0), 0, ""),
            bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"))
        );
    }
}

contract CheckInterestEarnedTests is UniswapStrategyTest {
    function setUp() public override {
        super.setUp();
        vm.startPrank(USDS_OWNER);
        _initializeStrategy();
        vm.stopPrank();
    }

    function test_RevertWhen_CollateralNotSupported() public useActor(0) {
        vm.expectRevert(abi.encodeWithSelector(CollateralNotSupported.selector, DUMMY_ADDRESS));
        strategy.checkInterestEarned(DUMMY_ADDRESS);
    }

    function test_CheckInterestEarned() public useKnownActor(USDS_OWNER) {
        assertEq(strategy.checkInterestEarned(ASSET_1), 0);
        assertEq(strategy.checkInterestEarned(ASSET_2), 0);

        _deposit();
        assertEq(strategy.checkInterestEarned(ASSET_1), 0);
        assertEq(strategy.checkInterestEarned(ASSET_2), 0);

        _allocate();
        assertEq(strategy.checkInterestEarned(ASSET_1), 0);
        assertEq(strategy.checkInterestEarned(ASSET_2), 0);

        _simulateSwap();
        assertTrue(strategy.checkInterestEarned(ASSET_1) > 0);
        assertTrue(strategy.checkInterestEarned(ASSET_2) > 0);

        vm.mockCall(VAULT, abi.encodeWithSignature("yieldReceiver()"), abi.encode(yieldReceiver));
        strategy.collectInterest(DUMMY_ADDRESS);
        assertEq(strategy.checkInterestEarned(ASSET_1), 0);
        assertEq(strategy.checkInterestEarned(ASSET_2), 0);
    }
}

contract CheckBalanceTests is UniswapStrategyTest {
    function setUp() public override {
        super.setUp();
        vm.startPrank(USDS_OWNER);
        _initializeStrategy();
        vm.stopPrank();
    }

    function test_RevertWhen_CollateralNotSupported() public useActor(0) {
        vm.expectRevert(abi.encodeWithSelector(CollateralNotSupported.selector, DUMMY_ADDRESS));
        strategy.checkBalance(DUMMY_ADDRESS);
    }

    function test_CheckBalance() public useActor(0) {
        assertEq(strategy.checkBalance(ASSET_1), 0);

        _deposit();

        assertEq(strategy.checkBalance(ASSET_1), depositAmount1);
        assertEq(strategy.checkBalance(ASSET_2), depositAmount2);
        assertEq(strategy.checkAvailableBalance(ASSET_1), depositAmount1);
        assertEq(strategy.checkAvailableBalance(ASSET_2), depositAmount2);

        _allocate();
        _redeem();
        _withdraw();

        assertEq(strategy.checkBalance(ASSET_1), 0);
        assertEq(strategy.checkBalance(ASSET_2), 0);
    }
}

contract CheckLPTokenBalanceTests is UniswapStrategyTest {
    function setUp() public override {
        super.setUp();
        vm.startPrank(USDS_OWNER);
        _initializeStrategy();
        vm.stopPrank();
    }

    function test_checkLPTokenBalance() public useActor(0) {
        assertEq(strategy.checkLPTokenBalance(DUMMY_ADDRESS), 0);

        _deposit();
        assertEq(strategy.checkLPTokenBalance(DUMMY_ADDRESS), 0);

        _allocate();
        assertTrue(strategy.checkLPTokenBalance(DUMMY_ADDRESS) > 0);

        _redeem();
        assertEq(strategy.checkLPTokenBalance(DUMMY_ADDRESS), 0);

        _withdraw();
        assertEq(strategy.checkLPTokenBalance(DUMMY_ADDRESS), 0);
    }
}

contract MiscellaneousTests is UniswapStrategyTest {
    function setUp() public override {
        super.setUp();
        vm.startPrank(USDS_OWNER);
        _initializeStrategy();
        vm.stopPrank();
    }

    function test_CheckRewardEarned() public {
        assertEq(strategy.checkRewardEarned(), 0);
    }

    function test_RevertWhen_CollectReward() public {
        vm.expectRevert(abi.encodeWithSelector(NoRewardIncentive.selector));
        strategy.collectReward();
    }
}
