// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {BaseStrategy} from "./BaseStrategy.t.sol";
import {BaseTest} from "../utils/BaseTest.sol";
import {UpgradeUtil} from "../utils/UpgradeUtil.sol";
import {UniswapStrategy} from "../../contracts/strategies/uniswap/UniswapStrategy.sol";
import {INonfungiblePositionManager} from "../../contracts/strategies/uniswap/interfaces/UniswapV3.sol";
import {InitializableAbstractStrategy, Helpers} from "../../contracts/strategies/InitializableAbstractStrategy.sol";
import {IERC20, ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

address constant UNISWAP_V3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
address constant NONFUNGIBLE_POSITION_MANAGER = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
address constant DUMMY_ADDRESS = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
uint24 constant fee = 500;

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
        vm.stopPrank();
    }

    function _initializeStrategy() internal {
        strategy.initialize(VAULT, NONFUNGIBLE_POSITION_MANAGER, UNISWAP_V3_FACTORY);
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
        (,,,,,,, uint128 liquidity,,,,) =
            INonfungiblePositionManager(NONFUNGIBLE_POSITION_MANAGER).positions(strategy.lpTokenId());
        uint256[2] memory minBurnAmount = [uint256(0), uint256(0)];
        strategy.redeem(liquidity, minBurnAmount);
    }

    function _setAssetData() internal {
        UniswapStrategy.UniswapPoolData memory poolData =
            UniswapStrategy.UniswapPoolData(ASSET_1, ASSET_2, fee, -276330, -276310);
        strategy.setPTokenAddress(poolData);
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
        vm.expectRevert(abi.encodeWithSelector(Helpers.InvalidAddress.selector));
        strategy.initialize(address(0), NONFUNGIBLE_POSITION_MANAGER, UNISWAP_V3_FACTORY);

        vm.expectRevert(abi.encodeWithSelector(Helpers.InvalidAddress.selector));
        strategy.initialize(VAULT, address(0), UNISWAP_V3_FACTORY);

        vm.expectRevert(abi.encodeWithSelector(Helpers.InvalidAddress.selector));
        strategy.initialize(VAULT, NONFUNGIBLE_POSITION_MANAGER, address(0));
    }

    function test_success() public useKnownActor(USDS_OWNER) {
        assertEq(impl.owner(), address(0));
        assertEq(strategy.owner(), address(0));

        _initializeStrategy();

        assertEq(impl.owner(), address(0));
        assertEq(strategy.owner(), USDS_OWNER);
        assertEq(strategy.vault(), VAULT);
        assertEq(address(strategy.nfpm()), NONFUNGIBLE_POSITION_MANAGER);
        assertEq(address(strategy.uniV3Factory()), UNISWAP_V3_FACTORY);
    }
}

contract SetPToken is UniswapStrategyTest {
    function setUp() public override {
        super.setUp();
        vm.startPrank(USDS_OWNER);
        _initializeStrategy();
        vm.stopPrank();
    }

    function test_RevertWhen_NotOwner() public useActor(0) {
        vm.expectRevert("Ownable: caller is not the owner");
        _setAssetData();
    }

    function test_RevertWhen_InvalidUniswapPoolConfig() public useKnownActor(USDS_OWNER) {
        UniswapStrategy.UniswapPoolData memory poolData = UniswapStrategy.UniswapPoolData(
            ASSET_1,
            ASSET_2,
            1, //invalid fee
            -276330,
            -276310
        );

        vm.expectRevert(abi.encodeWithSelector(InvalidUniswapPoolConfig.selector));
        strategy.setPTokenAddress(poolData);
    }

    function test_RevertWhen_InvalidTickRange() public useKnownActor(USDS_OWNER) {
        UniswapStrategy.UniswapPoolData memory poolData = UniswapStrategy.UniswapPoolData(
            ASSET_1,
            ASSET_2,
            fee,
            -887273, // invalid tickLower
            -276310
        );

        vm.expectRevert(abi.encodeWithSelector(InvalidTickRange.selector));
        strategy.setPTokenAddress(poolData);
    }

    function test_SetPTokenAddress() public useKnownActor(USDS_OWNER) {
        assertEq(strategy.assetToPToken(ASSET_1), address(0));
        assertEq(strategy.assetToPToken(ASSET_2), address(0));

        vm.expectEmit(true, false, false, false);
        emit PTokenAdded(address(ASSET_1), address(P_TOKEN));
        emit PTokenAdded(address(ASSET_2), address(P_TOKEN));

        UniswapStrategy.UniswapPoolData memory poolData =
            UniswapStrategy.UniswapPoolData(ASSET_1, ASSET_2, fee, -276330, -276310);
        strategy.setPTokenAddress(poolData);

        uint256 allocatedAmt = strategy.allocatedAmt(ASSET_1);

        assertEq(allocatedAmt, 0);

        assertEq(strategy.assetToPToken(ASSET_1), P_TOKEN);
        assertEq(strategy.assetToPToken(ASSET_2), P_TOKEN);

        assertTrue(strategy.supportsCollateral(ASSET_1));
        assertTrue(strategy.supportsCollateral(ASSET_2));
    }

    function test_RevertWhen_DuplicateAsset() public useKnownActor(USDS_OWNER) {
        _setAssetData();
        vm.expectRevert(abi.encodeWithSelector(PTokenAlreadySet.selector, ASSET_1, P_TOKEN));
        _setAssetData();
    }
}

contract RemovePToken is UniswapStrategyTest {
    function setUp() public override {
        super.setUp();
        vm.startPrank(USDS_OWNER);
        _initializeStrategy();
        _setAssetData();
        vm.stopPrank();
    }

    function test_RevertWhen_NotOwner() public useActor(0) {
        vm.expectRevert("Ownable: caller is not the owner");
        strategy.removePToken();
    }

    // TODO test not needed. Delete this later.
    // function test_RevertWhen_InvalidId() public useKnownActor(USDS_OWNER) {
    //     vm.expectRevert(abi.encodeWithSelector(InvalidIndex.selector));
    //     strategy.removePToken();
    // }

    function test_RevertWhen_CollateralAllocated() public useKnownActor(USDS_OWNER) {
        // deposit only ASSET_2
        deal(address(ASSET_2), VAULT, depositAmount2);
        changePrank(VAULT);
        IERC20(ASSET_2).approve(address(strategy), depositAmount2);
        strategy.deposit(ASSET_2, depositAmount2);
        changePrank(USDS_OWNER);
        vm.expectRevert(abi.encodeWithSelector(CollateralAllocated.selector, ASSET_2));
        strategy.removePToken();

        // deposit and allocate
        _deposit();
        _allocate();
        vm.expectRevert(abi.encodeWithSelector(CollateralAllocated.selector, ASSET_1));
        strategy.removePToken();
    }

    function test_RemovePToken() public useKnownActor(USDS_OWNER) {
        vm.expectEmit(true, false, false, false);
        emit PTokenRemoved(address(ASSET_1), address(P_TOKEN));
        emit PTokenRemoved(address(ASSET_2), address(P_TOKEN));

        strategy.removePToken();

        assertEq(strategy.allocatedAmt(ASSET_1), 0);
        assertEq(strategy.allocatedAmt(ASSET_2), 0);

        assertEq(strategy.assetToPToken(ASSET_1), address(0));
        assertEq(strategy.assetToPToken(ASSET_2), address(0));

        assertFalse(strategy.supportsCollateral(ASSET_1));
        assertFalse(strategy.supportsCollateral(ASSET_2));

        (address tokenA, address tokenB, uint24 feeTier, int24 tickLower, int24 tickUpper) = strategy.uniswapPoolData();

        assertEq(tokenA, address(0));
        assertEq(tokenB, address(0));
        assertEq(feeTier, 0);
        assertEq(tickLower, 0);
        assertEq(tickUpper, 0);
    }
}

contract Deposit is UniswapStrategyTest {
    function setUp() public override {
        super.setUp();
        vm.startPrank(USDS_OWNER);
        _initializeStrategy();
        _setAssetData();
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
        uint256 initial_bal_1 = IERC20(ASSET_1).balanceOf(address(strategy));

        deal(address(ASSET_1), VAULT, depositAmount1);
        IERC20(ASSET_1).approve(address(strategy), depositAmount1);
        strategy.deposit(ASSET_1, 1);

        uint256 new_bal_1 = IERC20(ASSET_1).balanceOf(address(strategy));
        assertEq(initial_bal_1 + 1, new_bal_1);
    }
}

contract allocate is UniswapStrategyTest {
    function setUp() public override {
        super.setUp();
        vm.startPrank(USDS_OWNER);
        _initializeStrategy();
        _setAssetData();
        _deposit();
        vm.stopPrank();
    }

    // TODO add other required tests

    // TODO fix tests if required
    function test_Allocate() public useKnownActor(USDS_OWNER) {
        uint256 initial_bal_1 = IERC20(ASSET_1).balanceOf(address(strategy));
        uint256 initial_bal_2 = IERC20(ASSET_2).balanceOf(address(strategy));

        uint256[2] memory amounts = [depositAmount1, depositAmount2];
        uint256[2] memory minMintAmount = [uint256(0), uint256(0)];
        strategy.allocate(amounts, minMintAmount);

        uint256 new_bal_1 = IERC20(ASSET_1).balanceOf(address(strategy));
        uint256 new_bal_2 = IERC20(ASSET_2).balanceOf(address(strategy));

        assertTrue(new_bal_1 < initial_bal_1);
        assertTrue(new_bal_2 < initial_bal_2);
    }
}

contract redeem is UniswapStrategyTest {
    function setUp() public override {
        super.setUp();
        vm.startPrank(USDS_OWNER);
        _initializeStrategy();
        _setAssetData();
        _deposit();
        _allocate();
        vm.stopPrank();
    }

    // TODO add other required tests

    // TODO fix tests if required
    function test_Redeem() public useKnownActor(USDS_OWNER) {
        uint256 initial_bal_1 = IERC20(ASSET_1).balanceOf(address(strategy));
        uint256 initial_bal_2 = IERC20(ASSET_2).balanceOf(address(strategy));

        (,,,,,,, uint128 liquidity,,,,) =
            INonfungiblePositionManager(NONFUNGIBLE_POSITION_MANAGER).positions(strategy.lpTokenId());
        assertTrue(liquidity != 0, "Liquidity is 0");

        uint256[2] memory minMintAmount = [uint256(0), uint256(0)];
        strategy.redeem(liquidity, minMintAmount);
        // strategy.collectInterest(DUMMY_ADDRESS);

        uint256 new_bal_1 = IERC20(ASSET_1).balanceOf(address(strategy));
        uint256 new_bal_2 = IERC20(ASSET_2).balanceOf(address(strategy));
        (,,,,,,, uint128 newLiquidity,,,,) =
            INonfungiblePositionManager(NONFUNGIBLE_POSITION_MANAGER).positions(strategy.lpTokenId());

        assertTrue(new_bal_1 > initial_bal_1, "Balance not increased");
        assertTrue(new_bal_2 > initial_bal_2, "Balance not increased");
        assertEq(newLiquidity, 0, "Liquidity not 0");
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

//         uint256 initial_bal_1 = IERC20(ASSET_1).balanceOf(yieldReceiver);
//         uint256 initial_bal_2 = IERC20(ASSET_2).balanceOf(yieldReceiver);

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
//         assertEq(current_bal_1, (initial_bal_1 + harvestAmount1));
//         assertEq(current_bal_2, (initial_bal_2 + interestEarned2));
//     }
// }

contract WithdrawTest is UniswapStrategyTest {
    function setUp() public override {
        super.setUp();
        vm.startPrank(USDS_OWNER);
        _initializeStrategy();
        _setAssetData();
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
