// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {console} from "forge-std/console.sol";
import {BaseStrategy} from "./BaseStrategy.t.sol";
import {BaseTest} from "../utils/BaseTest.sol";
import {UpgradeUtil} from "../utils/UpgradeUtil.sol";
import {Helpers, CompoundStrategy, IComet, IReward} from "../../contracts/strategies/compound/CompoundStrategy.sol";
import {IERC20, ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract CompoundStrategyTest is BaseStrategy, BaseTest {
    struct AssetData {
        string name;
        address asset;
        address pToken;
    }

    AssetData[] public data;

    CompoundStrategy internal strategy;
    CompoundStrategy internal impl;
    UpgradeUtil internal upgradeUtil;
    uint256 internal depositAmount;
    uint256 internal interestAmount;
    address internal proxyAddress;
    address internal yieldReceiver;
    address internal ASSET;
    address internal P_TOKEN;
    address internal constant REWARD_POOL = 0x88730d254A2f7e6AC8388c3198aFd694bA9f7fae;

    function setUp() public virtual override {
        super.setUp();
        setArbitrumFork();
        yieldReceiver = actors[0];
        vm.startPrank(USDS_OWNER);
        impl = new CompoundStrategy();
        upgradeUtil = new UpgradeUtil();
        proxyAddress = upgradeUtil.deployErc1967Proxy(address(impl));

        strategy = CompoundStrategy(proxyAddress);
        _configAsset();
        ASSET = data[0].asset;
        P_TOKEN = data[0].pToken;
        depositAmount = 100 * 10 ** ERC20(ASSET).decimals();
        interestAmount = 10 * 10 ** ERC20(ASSET).decimals();
        vm.stopPrank();
    }

    function _initializeStrategy() internal {
        strategy.initialize(VAULT, REWARD_POOL);
    }

    function _deposit() internal {
        changePrank(VAULT);
        deal(ASSET, VAULT, depositAmount);
        IERC20(ASSET).approve(address(strategy), depositAmount);
        strategy.deposit(ASSET, depositAmount);
        changePrank(USDS_OWNER);
    }

    function _setAssetData() internal {
        for (uint8 i = 0; i < data.length; ++i) {
            strategy.setPTokenAddress(data[i].asset, data[i].pToken);
        }
    }

    function _configAsset() internal {
        data.push(
            AssetData({
                name: "USDC.e",
                asset: 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8,
                pToken: 0xA5EDBDD9646f8dFF606d7448e414884C7d905dCA
            })
        );
        data.push(
            AssetData({
                name: "USDC",
                asset: 0xaf88d065e77c8cC2239327C5EDb3A432268e5831,
                pToken: 0x9c4ec768c28520B50860ea7a15bd7213a9fF58bf
            })
        );
    }

    function _mockInsufficientAsset() internal {
        vm.startPrank(strategy.assetToPToken(ASSET));
        IERC20(ASSET).transfer(actors[0], IERC20(ASSET).balanceOf(strategy.assetToPToken(ASSET)));
        vm.stopPrank();
    }
}

contract InitializeTests is CompoundStrategyTest {
    function test_invalid_address() public useKnownActor(USDS_OWNER) {
        vm.expectRevert(abi.encodeWithSelector(Helpers.InvalidAddress.selector));
        strategy.initialize(address(0), VAULT);

        vm.expectRevert(abi.encodeWithSelector(Helpers.InvalidAddress.selector));
        strategy.initialize(REWARD_POOL, address(0));
    }

    function test_initialization() public useKnownActor(USDS_OWNER) {
        assertEq(impl.owner(), address(0));
        assertEq(strategy.owner(), address(0));

        _initializeStrategy();

        assertEq(impl.owner(), address(0));
        assertEq(address(impl.rewardPool()), address(0));
        assertEq(strategy.owner(), USDS_OWNER);
        assertEq(strategy.vault(), VAULT);
        assertEq(address(strategy.rewardPool()), REWARD_POOL);
    }
}

contract SetPTokenTest is CompoundStrategyTest {
    function setUp() public override {
        super.setUp();
        vm.startPrank(USDS_OWNER);
        _initializeStrategy();
        vm.stopPrank();
    }

    function test_RevertWhen_NotOwner() public useActor(0) {
        vm.expectRevert("Ownable: caller is not the owner");
        strategy.setPTokenAddress(ASSET, P_TOKEN);
    }

    function test_RevertWhen_InvalidPToken() public useKnownActor(USDS_OWNER) {
        address OTHER_P_TOKEN = 0x9c4ec768c28520B50860ea7a15bd7213a9fF58bf;
        vm.expectRevert(abi.encodeWithSelector(InvalidAssetLpPair.selector, ASSET, OTHER_P_TOKEN));
        strategy.setPTokenAddress(ASSET, OTHER_P_TOKEN);
    }

    function test_SetPTokenAddress() public useKnownActor(USDS_OWNER) {
        assertEq(strategy.assetToPToken(ASSET), address(0));

        vm.expectEmit(true, false, false, false);
        emit PTokenAdded(address(ASSET), address(P_TOKEN));
        strategy.setPTokenAddress(ASSET, P_TOKEN);

        assertEq(strategy.assetToPToken(ASSET), P_TOKEN);
        assertTrue(strategy.supportsCollateral(ASSET));
    }

    function test_RevertWhen_DuplicateAsset() public useKnownActor(USDS_OWNER) {
        strategy.setPTokenAddress(ASSET, P_TOKEN);
        vm.expectRevert(abi.encodeWithSelector(PTokenAlreadySet.selector, ASSET, P_TOKEN));
        strategy.setPTokenAddress(ASSET, P_TOKEN);
    }
}

contract RemovePTokenTest is CompoundStrategyTest {
    function setUp() public override {
        super.setUp();
        vm.startPrank(USDS_OWNER);
        _initializeStrategy();
        _setAssetData();
        vm.stopPrank();
    }

    function test_RevertWhen_NotOwner() public useActor(0) {
        vm.expectRevert("Ownable: caller is not the owner");
        strategy.removePToken(0);
    }

    function test_RevertWhen_InvalidId() public useKnownActor(USDS_OWNER) {
        vm.expectRevert(abi.encodeWithSelector(InvalidIndex.selector));
        strategy.removePToken(5);
    }

    function test_RevertWhen_CollateralAllocated() public useKnownActor(USDS_OWNER) {
        _deposit();
        vm.expectRevert(abi.encodeWithSelector(CollateralAllocated.selector, ASSET));
        strategy.removePToken(0);
    }

    function test_RemovePToken() public useKnownActor(USDS_OWNER) {
        assertEq(strategy.assetToPToken(ASSET), P_TOKEN);
        assertTrue(strategy.supportsCollateral(ASSET));

        vm.expectEmit(true, false, false, false);
        emit PTokenRemoved(ASSET, P_TOKEN);
        strategy.removePToken(0);

        (uint256 allocatedAmt) = strategy.allocatedAmount(ASSET);

        assertEq(allocatedAmt, 0);
        assertEq(strategy.assetToPToken(ASSET), address(0));
        assertFalse(strategy.supportsCollateral(ASSET));
    }
}

contract DepositTest is CompoundStrategyTest {
    function setUp() public override {
        super.setUp();
        vm.startPrank(USDS_OWNER);
        _initializeStrategy();
        _setAssetData();
        vm.stopPrank();
    }

    function test_deposit_Collateral_not_supported() public useKnownActor(VAULT) {
        vm.expectRevert(abi.encodeWithSelector(CollateralNotSupported.selector, makeAddr("DUMMY")));
        strategy.deposit(makeAddr("DUMMY"), 1);
    }

    function test_RevertWhen_InvalidAmount() public useKnownActor(VAULT) {
        vm.expectRevert(abi.encodeWithSelector(Helpers.InvalidAmount.selector));
        strategy.deposit(ASSET, 0);
    }

    function testFuzz_Deposit(uint256 _depositAmount) public useKnownActor(VAULT) {
        depositAmount = bound(_depositAmount, 1, 1e10 * 10 ** ERC20(ASSET).decimals());
        uint256 initial_bal = strategy.checkBalance(ASSET);
        uint256 initialLPBalance = strategy.checkLPTokenBalance(ASSET);
        assert(initialLPBalance == 0);

        deal(ASSET, VAULT, depositAmount);
        IERC20(ASSET).approve(address(strategy), depositAmount);
        strategy.deposit(ASSET, depositAmount);

        uint256 new_bal = strategy.checkBalance(ASSET);
        uint256 newLPBalance = strategy.checkLPTokenBalance(ASSET);
        assertEq(initial_bal + depositAmount, new_bal);
        assertApproxEqAbs(initialLPBalance + depositAmount, newLPBalance, 2);
    }
}

contract CollectInterestTest is CompoundStrategyTest {
    function setUp() public override {
        super.setUp();
        vm.startPrank(USDS_OWNER);
        _initializeStrategy();
        strategy.setPTokenAddress(ASSET, P_TOKEN);

        _deposit();
        vm.stopPrank();
    }

    function test_CollectInterest() public useKnownActor(VAULT) {
        vm.warp(block.timestamp + 10 days);
        vm.roll(block.number + 1000);
        uint256 initial_bal = IERC20(ASSET).balanceOf(yieldReceiver);

        // IComet(P_TOKEN).accrueAccount(address(strategy));
        vm.mockCall(VAULT, abi.encodeWithSignature("yieldReceiver()"), abi.encode(yieldReceiver));

        uint256 interestEarned = strategy.checkInterestEarned(ASSET);

        assert(interestEarned > 0);

        uint256 incentiveAmt = (interestEarned * 10) / 10000;
        uint256 harvestAmount = interestEarned - incentiveAmt;

        vm.expectEmit(true, false, false, true);
        emit InterestCollected(ASSET, yieldReceiver, harvestAmount);

        strategy.collectInterest(ASSET);

        uint256 current_bal = IERC20(ASSET).balanceOf(yieldReceiver);
        assertApproxEqAbs(strategy.checkInterestEarned(ASSET), 0, 1);
        assertEq(current_bal, (initial_bal + harvestAmount));
    }
}

contract WithdrawTest is CompoundStrategyTest {
    function setUp() public override {
        super.setUp();
        vm.startPrank(USDS_OWNER);
        _initializeStrategy();
        strategy.setPTokenAddress(ASSET, P_TOKEN);

        _deposit();
        vm.stopPrank();
    }

    function test_RevertWhen_Withdraw0() public useKnownActor(USDS_OWNER) {
        AssetData memory assetData = data[0];
        vm.expectRevert(abi.encodeWithSelector(Helpers.CustomError.selector, "Must withdraw something"));
        strategy.withdrawToVault(assetData.asset, 0);
    }

    function test_RevertWhen_InvalidAddress() public useKnownActor(VAULT) {
        vm.expectRevert(abi.encodeWithSelector(Helpers.InvalidAddress.selector));
        strategy.withdraw(address(0), ASSET, 1);
    }

    function test_RevertWhen_CallerNotVault() public useActor(0) {
        vm.expectRevert(abi.encodeWithSelector(CallerNotVault.selector, actors[0]));
        strategy.withdraw(VAULT, ASSET, 1);
    }

    function test_Withdraw() public useKnownActor(VAULT) {
        uint256 initialVaultBal = IERC20(ASSET).balanceOf(VAULT);

        vm.expectEmit(true, false, false, true);
        emit Withdrawal(ASSET, depositAmount);

        vm.warp(block.timestamp + 10 days);

        strategy.withdraw(VAULT, ASSET, depositAmount);
        assertEq(initialVaultBal + depositAmount, IERC20(ASSET).balanceOf(VAULT));
    }

    function test_WithdrawToVault_RevertsIf_CallerNotOwner() public useActor(0) {
        uint256 initialVaultBal = IERC20(ASSET).balanceOf(VAULT);
        uint256 interestAmt = strategy.checkInterestEarned(ASSET);
        uint256 amt = initialVaultBal + interestAmt;

        vm.expectRevert("Ownable: caller is not the owner");
        strategy.withdrawToVault(ASSET, amt);
    }

    function test_WithdrawToVault() public useKnownActor(USDS_OWNER) {
        uint256 initialVaultBal = IERC20(ASSET).balanceOf(VAULT);

        vm.warp(block.timestamp + 10 days);

        vm.expectEmit(true, false, false, true);
        emit Withdrawal(ASSET, depositAmount);

        strategy.withdrawToVault(ASSET, depositAmount);
        assertEq(initialVaultBal + depositAmount, IERC20(ASSET).balanceOf(VAULT));
    }
}

contract CheckRewardEarnedTest is CompoundStrategyTest {
    function setUp() public override {
        super.setUp();
        vm.startPrank(USDS_OWNER);
        _initializeStrategy();
        _setAssetData();
        ASSET = USDC;
        P_TOKEN = data[1].pToken;
        vm.stopPrank();
    }

    function test_CheckRewardEarned() public useKnownActor(USDS_OWNER) {
        changePrank(VAULT);
        deal(ASSET, VAULT, depositAmount);
        IERC20(ASSET).approve(address(strategy), depositAmount);
        strategy.deposit(ASSET, depositAmount);
        changePrank(USDS_OWNER);
        vm.warp(block.timestamp + 10 days);
        IReward.RewardConfig memory config = strategy.rewardPool().rewardConfig(P_TOKEN);
        IReward.RewardOwed memory data =
            IReward(address(strategy.rewardPool())).getRewardOwed(P_TOKEN, address(strategy));
        address rwdToken = data.token;
        uint256 mockAccrued = 10000000;
        vm.mockCall(P_TOKEN, abi.encodeWithSignature("baseTrackingAccrued(address)"), abi.encode(mockAccrued));
        uint256 accrued = mockAccrued;
        if (config.shouldUpscale) {
            accrued *= config.rescaleFactor;
        } else {
            accrued /= config.rescaleFactor;
        }
        accrued = ((accrued * config.multiplier) / 1e18);
        uint256 collectibleAmount = accrued - strategy.rewardPool().rewardsClaimed(P_TOKEN, address(strategy));

        IComet(P_TOKEN).accrueAccount(address(strategy));
        CompoundStrategy.RewardData[] memory rewardData = strategy.checkRewardEarned();
        assert(rewardData.length > 0);
        // since P_TOKEN is in index 1 of data array checking for index 1 in rewardData
        assertEq(rewardData[1].token, rwdToken);
        assertEq(rewardData[1].amount, collectibleAmount);
    }

    function test_CheckRewardEarned_shouldUpscaleTrue() public useKnownActor(USDS_OWNER) {
        changePrank(VAULT);
        deal(ASSET, VAULT, depositAmount);
        IERC20(ASSET).approve(address(strategy), depositAmount);
        strategy.deposit(ASSET, depositAmount);
        changePrank(USDS_OWNER);

        vm.warp(block.timestamp + 10 days);
        IReward.RewardConfig memory config = strategy.rewardPool().rewardConfig(P_TOKEN);
        config.shouldUpscale = true;
        IReward.RewardOwed memory data =
            IReward(address(strategy.rewardPool())).getRewardOwed(P_TOKEN, address(strategy));
        address rwdToken = data.token;
        uint256 mockAccrued = 10000000;
        vm.mockCall(P_TOKEN, abi.encodeWithSignature("baseTrackingAccrued(address)"), abi.encode(mockAccrued));
        vm.mockCall(REWARD_POOL, abi.encodeWithSignature("rewardConfig(address)", P_TOKEN), abi.encode(config));
        uint256 accrued = mockAccrued;

        accrued *= config.rescaleFactor;
        accrued = ((accrued * config.multiplier) / 1e18);
        uint256 collectibleAmount = accrued - strategy.rewardPool().rewardsClaimed(P_TOKEN, address(strategy));
        IComet(P_TOKEN).accrueAccount(address(strategy));
        CompoundStrategy.RewardData[] memory rewardData = strategy.checkRewardEarned();
        assert(rewardData.length > 0);
        // since P_TOKEN is in index 1 of data array checking for index 1 in rewardData
        assertEq(rewardData[1].token, rwdToken);
        assertEq(rewardData[1].amount, collectibleAmount);
    }

    function test_CheckRewardEarned_shouldUpscaleFalse() public useKnownActor(USDS_OWNER) {
        changePrank(VAULT);
        deal(ASSET, VAULT, depositAmount);
        IERC20(ASSET).approve(address(strategy), depositAmount);
        strategy.deposit(ASSET, depositAmount);
        changePrank(USDS_OWNER);

        vm.warp(block.timestamp + 10 days);
        IReward.RewardConfig memory config = strategy.rewardPool().rewardConfig(P_TOKEN);
        config.shouldUpscale = false;
        IReward.RewardOwed memory data =
            IReward(address(strategy.rewardPool())).getRewardOwed(P_TOKEN, address(strategy));
        address rwdToken = data.token;
        uint256 mockAccrued = 10000000;
        vm.mockCall(P_TOKEN, abi.encodeWithSignature("baseTrackingAccrued(address)"), abi.encode(mockAccrued));
        vm.mockCall(REWARD_POOL, abi.encodeWithSignature("rewardConfig(address)", P_TOKEN), abi.encode(config));
        uint256 accrued = mockAccrued;

        accrued /= config.rescaleFactor;
        accrued = ((accrued * config.multiplier) / 1e18);
        uint256 collectibleAmount = accrued - strategy.rewardPool().rewardsClaimed(P_TOKEN, address(strategy));
        IComet(P_TOKEN).accrueAccount(address(strategy));
        CompoundStrategy.RewardData[] memory rewardData = strategy.checkRewardEarned();
        assert(rewardData.length > 0);
        // since P_TOKEN is in index 1 of data array checking for index 1 in rewardData
        assertEq(rewardData[1].token, rwdToken);
        assertEq(rewardData[1].amount, collectibleAmount);
    }
}

contract CheckAvailableBalanceTest is CompoundStrategyTest {
    function setUp() public override {
        super.setUp();
        vm.startPrank(USDS_OWNER);
        _initializeStrategy();
        _setAssetData();
        _deposit();
    }

    function test_checkAvailableBalance_LTAllocatedAmount() public {
        vm.mockCall(ASSET, abi.encodeWithSignature("balanceOf(address)"), abi.encode(depositAmount - 100));
        uint256 availableBalance = strategy.checkAvailableBalance(ASSET);
        assertTrue(availableBalance < depositAmount);
    }

    function test_checkAvailableBalance_MoreThanAllocated() public {
        vm.warp(block.timestamp + 10 days);
        uint256 availableBalance = strategy.checkAvailableBalance(ASSET);
        assertEq(availableBalance, depositAmount);
    }
}

contract CollectRewardTest is CheckRewardEarnedTest {
    function test_collectReward() public useKnownActor(USDS_OWNER) {
        deal(ASSET, VAULT, depositAmount);
        changePrank(VAULT);
        IERC20(ASSET).approve(address(strategy), depositAmount);
        strategy.deposit(ASSET, depositAmount);
        changePrank(USDS_OWNER);
        vm.warp(block.timestamp + 10 days);
        IComet(P_TOKEN).accrueAccount(address(strategy));
        vm.mockCall(VAULT, abi.encodeWithSignature("yieldReceiver()"), abi.encode(yieldReceiver));
        vm.mockCall(P_TOKEN, abi.encodeWithSignature("baseTrackingAccrued(address)"), abi.encode(10000000));
        uint16 harvestIncentiveRate = strategy.harvestIncentiveRate();
        IReward.RewardOwed memory rewardData =
            IReward(address(strategy.rewardPool())).getRewardOwed(P_TOKEN, address(strategy));
        address rwdToken = rewardData.token;
        uint256 rwdAmount = rewardData.owed;
        uint256 harvestAmt = (rwdAmount * harvestIncentiveRate) / Helpers.MAX_PERCENTAGE;
        rwdAmount -= harvestAmt;
        address harvester = actors[2];
        changePrank(harvester);
        vm.expectEmit(true, true, true, true);
        emit RewardTokenCollected(rwdToken, yieldReceiver, rwdAmount);
        strategy.collectReward();
        assertEq(harvestAmt, IERC20(rwdToken).balanceOf(harvester));
        assertEq(rwdAmount, IERC20(rwdToken).balanceOf(yieldReceiver));
        vm.clearMockedCalls();
    }
}
