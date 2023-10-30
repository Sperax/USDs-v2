// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {BaseStrategy} from "./BaseStrategy.t.sol";
import {BaseTest} from "../utils/BaseTest.sol";
import {UpgradeUtil} from "../utils/UpgradeUtil.sol";
import {UniswapStrategy} from "../../contracts/strategies/uniswap/UniswapStrategy.sol";
import {INonfungiblePositionManager} from "../../contracts/strategies/uniswap/interfaces/UniswapV3.sol";
import {InitializableAbstractStrategy, Helpers} from "../../contracts/strategies/InitializableAbstractStrategy.sol";
import {IERC20, ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {
    IUniswapV3Factory,
    INonfungiblePositionManager as INFPM
} from "../../contracts/strategies/uniswap/interfaces/UniswapV3.sol";
import {IUniswapUtils} from "../../contracts/strategies/uniswap/interfaces/IUniswapUtils.sol";

address constant UNISWAP_V3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
address constant NONFUNGIBLE_POSITION_MANAGER = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
address constant DUMMY_ADDRESS = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
uint24 constant FEE = 500;
int24 constant TICK_LOWER = -276330;
int24 constant TICK_UPPER = -276310;

contract UniswapStrategyTest is BaseStrategy, BaseTest {
    struct AssetData {
        string name;
        address asset;
    }

    AssetData[] public data;

    UniswapStrategy internal strategy;
    UniswapStrategy internal impl;
    UpgradeUtil internal upgradeUtil;
    uint256 internal depositAmount1;
    uint256 internal depositAmount2;
    address internal proxyAddress;
    address internal yieldReceiver;
    address internal ASSET_1;
    address internal ASSET_2;
    address internal constant P_TOKEN = NONFUNGIBLE_POSITION_MANAGER;
    IUniswapUtils internal UNISWAP_UTILS;

    // Events
    event MintNewPosition(uint256 tokenId);
    event IncreaseLiquidity(uint256 liquidity, uint256 amount0, uint256 amount1);
    event DecreaseLiquidity(uint256 liquidity, uint256 amount0, uint256 amount1);

    // Custom errors
    error InvalidUniswapPoolConfig();
    error NoRewardToken();
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
        depositAmount1 = 1 * 10 ** ERC20(ASSET_1).decimals();
        depositAmount2 = 1 * 10 ** ERC20(ASSET_2).decimals();

        UNISWAP_UTILS = IUniswapUtils(deployCode("UniswapUtils.sol"));

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
            UNISWAP_UTILS,
            0
        );
        strategy.initialize(VAULT, poolData);
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
        uint256[2] memory minMintAmount = [uint256(0), uint256(0)];
        strategy.allocate(amounts, minMintAmount);
    }

    function _redeem() internal {
        (,,,,,,,, uint256 lpTokenId) = strategy.uniswapPoolData();
        (,,,,,,, uint128 liquidity,,,,) = INonfungiblePositionManager(NONFUNGIBLE_POSITION_MANAGER).positions(lpTokenId);
        uint256[2] memory minBurnAmount = [uint256(0), uint256(0)];
        strategy.redeem(liquidity, minBurnAmount);
    }

    function _configAsset() internal {
        data.push(AssetData({name: "DAI", asset: 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1}));
        data.push(AssetData({name: "USDC.e", asset: 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8}));
    }

    function _mockInsufficientAsset() internal {
        // TODO add ASSET_2?
        vm.startPrank(strategy.assetToPToken(ASSET_1));
        IERC20(ASSET_1).transfer(actors[0], IERC20(ASSET_1).balanceOf(strategy.assetToPToken(ASSET_1)));
        vm.stopPrank();
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
            UNISWAP_UTILS,
            0
        );
        vm.expectRevert(abi.encodeWithSelector(Helpers.InvalidAddress.selector));
        strategy.initialize(address(0), poolData);

        vm.expectRevert();
        poolData.uniV3Factory = IUniswapV3Factory(address(0));
        strategy.initialize(VAULT, poolData);

        vm.expectRevert();
        poolData.uniV3Factory = IUniswapV3Factory(UNISWAP_V3_FACTORY);
        poolData.uniswapUtils = IUniswapUtils(address(0));
        strategy.initialize(VAULT, poolData);
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
            UNISWAP_UTILS,
            0
        );

        vm.expectRevert(abi.encodeWithSelector(InvalidUniswapPoolConfig.selector));
        strategy.initialize(VAULT, poolData);
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
            UNISWAP_UTILS,
            0
        );

        vm.expectRevert(abi.encodeWithSelector(InvalidTickRange.selector));
        strategy.initialize(VAULT, poolData);
    }

    function test_Initialize() public useKnownActor(USDS_OWNER) {
        assertEq(impl.owner(), address(0));
        assertEq(strategy.owner(), address(0));

        _initializeStrategy();

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
        assertEq(address(uniswapUtils), address(UNISWAP_UTILS));
        assertEq(lpTokenId, 0);

        assertEq(strategy.assetToPToken(ASSET_1), P_TOKEN);
        assertEq(strategy.assetToPToken(ASSET_2), P_TOKEN);

        assertTrue(strategy.supportsCollateral(ASSET_1));
        assertTrue(strategy.supportsCollateral(ASSET_2));
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

        vm.expectEmit(false, false, false, false);
        emit Deposit(ASSET_1, depositAmount1);

        strategy.deposit(ASSET_1, 1);

        uint256 new_bal_1 = IERC20(ASSET_1).balanceOf(address(strategy));
        assertEq(initialBal1 + 1, new_bal_1);
    }
}

contract allocateTests is UniswapStrategyTest {
    function setUp() public override {
        super.setUp();
        vm.startPrank(USDS_OWNER);
        _initializeStrategy();
        _deposit();
        vm.stopPrank();
    }

    function test_RevertWhen_ZeroAmounts() public useKnownActor(USDS_OWNER) {
        uint256[2] memory amounts = [uint256(0), uint256(0)];
        uint256[2] memory minMintAmount = [uint256(0), uint256(0)];
        vm.expectRevert(abi.encodeWithSelector(Helpers.InvalidAmount.selector));
        strategy.allocate(amounts, minMintAmount);
    }

    function test_Allocate_MintNewPositionAndLiquidity() public useKnownActor(USDS_OWNER) {
        (,,,,,,,, uint256 lpTokenId) = strategy.uniswapPoolData();
        uint256 initialBal1 = IERC20(ASSET_1).balanceOf(address(strategy));
        uint256 initialBal2 = IERC20(ASSET_2).balanceOf(address(strategy));
        uint256 oldAllocatedAmt1 = strategy.checkBalance(ASSET_1) - initialBal1;
        uint256 oldAllocatedAmt2 = strategy.checkBalance(ASSET_2) - initialBal2;
        assertEq(lpTokenId, 0);
        assertEq(oldAllocatedAmt1, 0);
        assertEq(oldAllocatedAmt2, 0);

        uint256[2] memory amounts = [depositAmount1, depositAmount2];
        uint256[2] memory minMintAmount = [uint256(0), uint256(0)];

        vm.expectEmit(false, false, false, false);
        // TODO fix matching params?
        emit MintNewPosition(0); // not checking tokenId
        emit IncreaseLiquidity(0, 0, 0); // not checking params
        strategy.allocate(amounts, minMintAmount);

        uint256 new_bal_1 = IERC20(ASSET_1).balanceOf(address(strategy));
        uint256 new_bal_2 = IERC20(ASSET_2).balanceOf(address(strategy));
        uint256 newAllocatedAmt1 = strategy.checkBalance(ASSET_1) - new_bal_1;
        uint256 newAllocatedAmt2 = strategy.checkBalance(ASSET_2) - new_bal_2;

        assertTrue(new_bal_1 < initialBal1);
        assertTrue(new_bal_2 < initialBal2);
        (,,,,,,,, lpTokenId) = strategy.uniswapPoolData();
        assertNotEq(lpTokenId, 0);

        // TODO check exact amounts?
        assertTrue(newAllocatedAmt1 > 0);
        assertTrue(newAllocatedAmt2 > 0);
    }

    function test_Allocate_IncreaseLiquidity() public useKnownActor(USDS_OWNER) {
        _allocate();
        _deposit();
        (,,,,,,,, uint256 lpTokenId) = strategy.uniswapPoolData();
        uint256 oldAllocatedAmt1 = strategy.checkBalance(ASSET_1) - IERC20(ASSET_1).balanceOf(address(strategy));
        uint256 oldAllocatedAmt2 = strategy.checkBalance(ASSET_2) - IERC20(ASSET_2).balanceOf(address(strategy));

        uint256[2] memory amounts = [depositAmount1, depositAmount2];
        uint256[2] memory minMintAmount = [uint256(0), uint256(0)];

        vm.expectEmit(false, false, false, false);
        emit IncreaseLiquidity(0, 0, 0); // not checking params
        strategy.allocate(amounts, minMintAmount);

        (,,,,,,,, uint256 newLpTokenId) = strategy.uniswapPoolData();
        uint256 newAllocatedAmt1 = strategy.checkBalance(ASSET_1) - IERC20(ASSET_1).balanceOf(address(strategy));
        uint256 newAllocatedAmt2 = strategy.checkBalance(ASSET_2) - IERC20(ASSET_2).balanceOf(address(strategy));

        assertEq(newLpTokenId, lpTokenId);
        // TODO check exact amounts?
        assertTrue(newAllocatedAmt1 > oldAllocatedAmt1);
        assertTrue(newAllocatedAmt2 > oldAllocatedAmt2);
    }
}

contract redeemTests is UniswapStrategyTest {
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

        (,,,,,,,, uint256 lpTokenId) = strategy.uniswapPoolData();
        (,,,,,,, uint128 oldLiquidity,,,,) =
            INonfungiblePositionManager(NONFUNGIBLE_POSITION_MANAGER).positions(lpTokenId);
        assertTrue(oldLiquidity != 0, "Liquidity is 0");

        // TODO fix matching params?
        vm.expectEmit(false, false, false, false);
        emit DecreaseLiquidity(0, 0, 0); // not checking tokenId

        uint256[2] memory minMintAmount = [uint256(0), uint256(0)];
        strategy.redeem(oldLiquidity, minMintAmount);

        uint256 new_bal_1 = IERC20(ASSET_1).balanceOf(address(strategy));
        uint256 new_bal_2 = IERC20(ASSET_2).balanceOf(address(strategy));
        uint256 newAllocatedAmt1 = strategy.checkBalance(ASSET_1) - new_bal_1;
        uint256 newAllocatedAmt2 = strategy.checkBalance(ASSET_2) - new_bal_2;
        (,,,,,,, uint128 newLiquidity,,,,) =
            INonfungiblePositionManager(NONFUNGIBLE_POSITION_MANAGER).positions(lpTokenId);

        // TODO check exact amounts?
        assertTrue(new_bal_1 > initialBal1, "Balance not increased");
        assertTrue(new_bal_2 > initialBal2, "Balance not increased");
        assertTrue(newAllocatedAmt1 == 0);
        assertTrue(newAllocatedAmt2 == 0);
        assertTrue(oldLiquidity > newLiquidity);
    }

    function test_Redeem_partialLiquidity() public useKnownActor(USDS_OWNER) {
        uint256 initialBal1 = IERC20(ASSET_1).balanceOf(address(strategy));
        uint256 initialBal2 = IERC20(ASSET_2).balanceOf(address(strategy));
        uint256 oldAllocatedAmt1 = strategy.checkBalance(ASSET_1) - initialBal1;
        uint256 oldAllocatedAmt2 = strategy.checkBalance(ASSET_2) - initialBal2;

        (,,,,,,,, uint256 lpTokenId) = strategy.uniswapPoolData();
        (,,,,,,, uint128 oldLiquidity,,,,) =
            INonfungiblePositionManager(NONFUNGIBLE_POSITION_MANAGER).positions(lpTokenId);
        assertTrue(oldLiquidity != 0, "Liquidity is 0");

        // TODO fix matching params?
        vm.expectEmit(false, false, false, false);
        emit DecreaseLiquidity(0, 0, 0); // not checking tokenId

        uint256[2] memory minMintAmount = [uint256(0), uint256(0)];
        strategy.redeem(oldLiquidity / 2, minMintAmount);

        uint256 new_bal_1 = IERC20(ASSET_1).balanceOf(address(strategy));
        uint256 new_bal_2 = IERC20(ASSET_2).balanceOf(address(strategy));
        uint256 newAllocatedAmt1 = strategy.checkBalance(ASSET_1) - new_bal_1;
        uint256 newAllocatedAmt2 = strategy.checkBalance(ASSET_2) - new_bal_2;
        (,,,,,,, uint128 newLiquidity,,,,) =
            INonfungiblePositionManager(NONFUNGIBLE_POSITION_MANAGER).positions(lpTokenId);

        // TODO check exact amounts?
        assertTrue(new_bal_1 > initialBal1, "Balance not increased");
        assertTrue(new_bal_2 > initialBal2, "Balance not increased");
        assertTrue(newLiquidity < oldLiquidity);
        assertTrue(newAllocatedAmt1 < oldAllocatedAmt1);
        assertTrue(newAllocatedAmt2 < oldAllocatedAmt2);
    }
}

// TODO failing as interestEarned1 is not increased with time, but is increased with swap. So need to do that.
// contract CollectInterest is UniswapStrategyTest {

//     function setUp() public override {
//         super.setUp();
//         vm.startPrank(USDS_OWNER);
//         _initializeStrategy();
//         _setAssetData();
//         _deposit();
//         _allocate();
//         vm.stopPrank();
//     }

//     function test_CollectInterest() public useKnownActor(VAULT) {
//         vm.warp(block.timestamp + 10 days);
//         vm.roll(block.number + 1000);

//         uint256 initialBal1 = IERC20(ASSET_1).balanceOf(yieldReceiver);
//         uint256 initialBal2 = IERC20(ASSET_2).balanceOf(yieldReceiver);

//         vm.mockCall(VAULT, abi.encodeWithSignature("yieldReceiver()"), abi.encode(yieldReceiver));

//         uint256 interestEarned1 = strategy.checkInterestEarned(ASSET_1);
//         uint256 interestEarned2 = strategy.checkInterestEarned(ASSET_2);

//         assert(interestEarned1 > 0);
//         assert(interestEarned2 > 0);

//         uint256 incentiveAmt1 = (interestEarned1 * 10) / 10000;
//         uint256 harvestAmount1 = interestEarned1 - incentiveAmt1;

//         vm.expectEmit(true, false, false, true);
//         emit InterestCollected(ASSET_1, yieldReceiver, harvestAmount1);
//         // TODO add second event?

//         strategy.collectInterest(DUMMY_ADDRESS);

//         uint256 current_bal_1 = IERC20(ASSET_1).balanceOf(yieldReceiver);
//         uint256 current_bal_2 = IERC20(ASSET_2).balanceOf(yieldReceiver);
//         uint256 newInterestEarned1 = strategy.checkInterestEarned(ASSET_1);
//         uint256 newInterestEarned2 = strategy.checkInterestEarned(ASSET_1);

//         assertEq(newInterestEarned1, 0);
//         assertEq(newInterestEarned2, 0);
//         assertEq(current_bal_1, (initialBal1 + harvestAmount1));
//         assertEq(current_bal_2, (initialBal2 + interestEarned2));
//     }
// }

contract WithdrawTest is UniswapStrategyTest {
    function setUp() public override {
        super.setUp();
        vm.startPrank(USDS_OWNER);
        _initializeStrategy();
        _deposit();
        _allocate();
        _redeem();
        vm.stopPrank();
    }

    // function test_RevertWhen_Withdraw0() public useKnownActor(USDS_OWNER) {
    //     AssetData memory assetData = data[0];
    //     vm.expectRevert(abi.encodeWithSelector(Helpers.CustomError.selector, "Must withdraw something"));
    //     strategy.withdrawToVault(assetData.asset, 0);
    // }

    // function test_RevertWhen_InvalidAddress() public useKnownActor(VAULT) {
    //     vm.expectRevert(abi.encodeWithSelector(Helpers.InvalidAddress.selector));
    //     strategy.withdraw(address(0), ASSET, 1);
    // }

    // function test_RevertWhen_CallerNotVault() public useActor(0) {
    //     vm.expectRevert(abi.encodeWithSelector(CallerNotVault.selector, actors[0]));
    //     strategy.withdraw(VAULT, ASSET, 1);
    // }

    function test_Withdraw() public useKnownActor(VAULT) {
        uint256 initialVaultBal = IERC20(ASSET_1).balanceOf(VAULT);
        uint256 availableBal = IERC20(ASSET_1).balanceOf(address(strategy));

        vm.expectEmit(true, false, false, true);
        emit Withdrawal(ASSET_1, availableBal);

        strategy.withdraw(VAULT, ASSET_1, availableBal);
        assertEq(initialVaultBal + availableBal, IERC20(ASSET_1).balanceOf(VAULT));
    }

    // function test_WithdrawToVault() public useKnownActor(USDS_OWNER) {
    //     uint256 initialVaultBal = IERC20(ASSET).balanceOf(VAULT);
    //     uint256 amt = 1000;

    //     vm.warp(block.timestamp + 10 days);
    //     vm.roll(block.number + 1000);

    //     vm.expectEmit(true, false, false, true);
    //     emit Withdrawal(ASSET, amt);

    //     strategy.withdrawToVault(ASSET, amt);
    //     assertEq(initialVaultBal + amt, IERC20(ASSET).balanceOf(VAULT));
    // }
}

// contract MiscellaneousTest is UniswapStrategyTest {
//     function setUp() public override {
//         super.setUp();
//         vm.startPrank(USDS_OWNER);
//         _initializeStrategy();
//         strategy.setPTokenAddress(ASSET, P_TOKEN, 0);
//         vm.stopPrank();
//     }

//     function test_CheckRewardEarned() public {
//         uint256 reward = strategy.checkRewardEarned();
//         assertEq(reward, 0);
//     }

//     function test_CheckBalance() public {
//         (uint256 balance,) = strategy.assetInfo(ASSET);
//         uint256 bal = strategy.checkBalance(ASSET);
//         assertEq(bal, balance);
//     }

//     function test_CheckAvailableBalance() public {
//         vm.startPrank(VAULT);
//         deal(address(ASSET), VAULT, depositAmount);
//         IERC20(ASSET).approve(address(strategy), depositAmount);
//         strategy.deposit(ASSET, depositAmount);
//         vm.stopPrank();

//         uint256 bal_after = strategy.checkAvailableBalance(ASSET);
//         assertEq(bal_after, depositAmount);
//     }

//     function test_CheckAvailableBalance_InsufficientTokens() public {
//         vm.startPrank(VAULT);
//         deal(address(ASSET), VAULT, depositAmount);
//         IERC20(ASSET).approve(address(strategy), depositAmount);
//         strategy.deposit(ASSET, depositAmount);
//         vm.stopPrank();

//         _mockInsufficientAsset();

//         uint256 bal_after = strategy.checkAvailableBalance(ASSET);
//         assertEq(bal_after, IERC20(ASSET).balanceOf(strategy.assetToPToken(ASSET)));
//     }

//     function test_CollectReward() public {
//         vm.expectRevert("No reward incentive for AAVE");
//         strategy.collectReward();
//     }

//     function test_CheckInterestEarned_Empty() public {
//         uint256 interest = strategy.checkInterestEarned(ASSET);
//         assertEq(interest, 0);
//     }
// }
