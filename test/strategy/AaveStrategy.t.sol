// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {BaseStrategy} from "./BaseStrategy.t.sol";
import {BaseTest} from "../utils/BaseTest.sol";
import {UpgradeUtil} from "../utils/UpgradeUtil.sol";
import {AaveStrategy} from "../../contracts/strategies/aave/AaveStrategy.sol";
import {InitializableAbstractStrategy, Helpers} from "../../contracts/strategies/InitializableAbstractStrategy.sol";
import {IERC20, ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

address constant AAVE_POOL_PROVIDER = 0xa97684ead0e402dC232d5A977953DF7ECBaB3CDb;
address constant DUMMY_ADDRESS = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

contract AaveStrategyTest is BaseStrategy, BaseTest {
    struct AssetData {
        string name;
        address asset;
        address pToken;
    }

    AssetData[] public data;

    AaveStrategy internal strategy;
    AaveStrategy internal impl;
    UpgradeUtil internal upgradeUtil;
    uint256 internal depositAmount;
    address internal proxyAddress;
    address internal ASSET;
    address internal P_TOKEN;

    function setUp() public virtual override {
        super.setUp();
        setArbitrumFork();
        vm.startPrank(USDS_OWNER);
        impl = new AaveStrategy();
        upgradeUtil = new UpgradeUtil();
        proxyAddress = upgradeUtil.deployErc1967Proxy(address(impl));

        strategy = AaveStrategy(proxyAddress);
        _configAsset();
        ASSET = data[0].asset;
        P_TOKEN = data[0].pToken;
        depositAmount = 1 * 10 ** ERC20(ASSET).decimals();
        vm.stopPrank();
    }

    function _initializeStrategy() internal {
        strategy.initialize(AAVE_POOL_PROVIDER, VAULT);
    }

    function _deposit() internal {
        changePrank(VAULT);
        deal(address(ASSET), VAULT, depositAmount);
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
                name: "WETH",
                asset: 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1,
                pToken: 0xe50fA9b3c56FfB159cB0FCA61F5c9D750e8128c8
            })
        );
        data.push(
            AssetData({
                name: "USDC.e",
                asset: 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8,
                pToken: 0x625E7708f30cA75bfd92586e17077590C60eb4cD
            })
        );

        data.push(
            AssetData({
                name: "DAI",
                asset: 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1,
                pToken: 0x82E64f49Ed5EC1bC6e43DAD4FC8Af9bb3A2312EE
            })
        );
    }

    function _mockInsufficientAsset() internal {
        vm.startPrank(strategy.assetToPToken(ASSET));
        IERC20(ASSET).transfer(actors[0], IERC20(ASSET).balanceOf(strategy.assetToPToken(ASSET)));
        vm.stopPrank();
    }
}

contract InitializeTests is AaveStrategyTest {
    function test_empty_address() public useKnownActor(USDS_OWNER) {
        vm.expectRevert(abi.encodeWithSelector(Helpers.InvalidAddress.selector));

        strategy.initialize(address(0), VAULT);

        vm.expectRevert(abi.encodeWithSelector(Helpers.InvalidAddress.selector));

        strategy.initialize(AAVE_POOL_PROVIDER, address(0));
    }

    function test_success() public useKnownActor(USDS_OWNER) {
        assertEq(impl.owner(), address(0));
        assertEq(strategy.owner(), address(0));

        _initializeStrategy();

        assertEq(impl.owner(), address(0));
        assertEq(strategy.owner(), USDS_OWNER);
        assertEq(strategy.vault(), VAULT);
        assertNotEq(strategy.aavePool.address, address(0));
    }
}

contract SetPToken is AaveStrategyTest {
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
        vm.expectRevert(abi.encodeWithSelector(InvalidAssetLpPair.selector, ASSET, data[1].pToken));
        strategy.setPTokenAddress(ASSET, data[1].pToken);
    }

    function test_SetPTokenAddress() public useKnownActor(USDS_OWNER) {
        vm.expectEmit(true, false, false, false);
        assertEq(strategy.assetToPToken(ASSET), address(0));

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

contract RemovePToken is AaveStrategyTest {
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
        vm.expectEmit(true, false, false, false);
        emit PTokenRemoved(address(ASSET), address(P_TOKEN));

        strategy.removePToken(0);

        (uint256 allocatedAmt) = strategy.assetInfo(ASSET);

        assertEq(allocatedAmt, 0);
        assertEq(strategy.assetToPToken(ASSET), address(0));
        assertFalse(strategy.supportsCollateral(ASSET));
    }
}

contract Deposit is AaveStrategyTest {
    function setUp() public override {
        super.setUp();
        vm.startPrank(USDS_OWNER);
        _initializeStrategy();
        strategy.setPTokenAddress(ASSET, P_TOKEN);
        vm.stopPrank();
    }

    function test_deposit_Collateral_not_supported() public useKnownActor(VAULT) {
        vm.expectRevert(abi.encodeWithSelector(CollateralNotSupported.selector, DUMMY_ADDRESS));
        strategy.deposit(DUMMY_ADDRESS, 1);
    }

    function test_RevertWhen_InvalidAmount() public useKnownActor(VAULT) {
        vm.expectRevert(abi.encodeWithSelector(Helpers.InvalidAmount.selector));
        strategy.deposit(ASSET, 0);
    }

    function test_Deposit() public useKnownActor(VAULT) {
        uint256 initial_bal = strategy.checkBalance(ASSET);

        deal(address(ASSET), VAULT, depositAmount);
        IERC20(ASSET).approve(address(strategy), depositAmount);
        strategy.deposit(ASSET, 1);

        uint256 new_bal = strategy.checkBalance(ASSET);
        assertEq(initial_bal + 1, new_bal);
    }
}

contract CollectInterest is AaveStrategyTest {
    address public yieldReceiver;

    function setUp() public override {
        super.setUp();
        yieldReceiver = actors[0];
        vm.startPrank(USDS_OWNER);
        _initializeStrategy();
        strategy.setPTokenAddress(ASSET, P_TOKEN);

        changePrank(VAULT);
        deal(address(ASSET), VAULT, depositAmount);
        IERC20(ASSET).approve(address(strategy), depositAmount);
        strategy.deposit(ASSET, depositAmount);
        vm.stopPrank();
    }

    function test_CollectInterest() public useKnownActor(VAULT) {
        vm.warp(block.timestamp + 10 days);
        vm.roll(block.number + 1000);

        uint256 initial_bal = IERC20(ASSET).balanceOf(yieldReceiver);

        vm.mockCall(VAULT, abi.encodeWithSignature("yieldReceiver()"), abi.encode(yieldReceiver));

        uint256 interestEarned = strategy.checkInterestEarned(ASSET);

        assert(interestEarned > 0);

        uint256 incentiveAmt = (interestEarned * 10) / 10000;
        uint256 harvestAmount = interestEarned - incentiveAmt;

        vm.expectEmit(true, false, false, true);
        emit InterestCollected(ASSET, yieldReceiver, harvestAmount);

        strategy.collectInterest(ASSET);

        uint256 current_bal = IERC20(ASSET).balanceOf(yieldReceiver);
        uint256 newInterestEarned = strategy.checkInterestEarned(ASSET);

        assertEq(newInterestEarned, 0);
        assertEq(current_bal, (initial_bal + harvestAmount));
    }
}

contract WithdrawTest is AaveStrategyTest {
    address public yieldReceiver;

    function setUp() public override {
        super.setUp();
        yieldReceiver = actors[0];
        vm.startPrank(USDS_OWNER);
        _initializeStrategy();
        strategy.setPTokenAddress(ASSET, P_TOKEN);

        changePrank(VAULT);
        deal(address(ASSET), VAULT, depositAmount);
        IERC20(ASSET).approve(address(strategy), depositAmount);
        strategy.deposit(ASSET, depositAmount);
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
        uint256 amt = 1000;

        vm.expectEmit(true, false, false, true);
        emit Withdrawal(ASSET, amt);

        vm.warp(block.timestamp + 10 days);
        vm.roll(block.number + 1000);

        strategy.withdraw(VAULT, ASSET, amt);
        assertEq(initialVaultBal + amt, IERC20(ASSET).balanceOf(VAULT));
    }

    function test_WithdrawToVault() public useKnownActor(USDS_OWNER) {
        uint256 initialVaultBal = IERC20(ASSET).balanceOf(VAULT);
        uint256 amt = 1000;

        vm.warp(block.timestamp + 10 days);
        vm.roll(block.number + 1000);

        vm.expectEmit(true, false, false, true);
        emit Withdrawal(ASSET, amt);

        strategy.withdrawToVault(ASSET, amt);
        assertEq(initialVaultBal + amt, IERC20(ASSET).balanceOf(VAULT));
    }
}

contract MiscellaneousTest is AaveStrategyTest {
    function setUp() public override {
        super.setUp();
        vm.startPrank(USDS_OWNER);
        _initializeStrategy();
        strategy.setPTokenAddress(ASSET, P_TOKEN);
        vm.stopPrank();
    }

    function test_CheckRewardEarned() public {
        uint256 reward = strategy.checkRewardEarned();
        assertEq(reward, 0);
    }

    function test_CheckBalance() public {
        (uint256 balance) = strategy.assetInfo(ASSET);
        uint256 bal = strategy.checkBalance(ASSET);
        assertEq(bal, balance);
    }

    function test_CheckAvailableBalance() public {
        vm.startPrank(VAULT);
        deal(address(ASSET), VAULT, depositAmount);
        IERC20(ASSET).approve(address(strategy), depositAmount);
        strategy.deposit(ASSET, depositAmount);
        vm.stopPrank();

        uint256 bal_after = strategy.checkAvailableBalance(ASSET);
        assertEq(bal_after, depositAmount);
    }

    function test_CheckAvailableBalance_InsufficientTokens() public {
        vm.startPrank(VAULT);
        deal(address(ASSET), VAULT, depositAmount);
        IERC20(ASSET).approve(address(strategy), depositAmount);
        strategy.deposit(ASSET, depositAmount);
        vm.stopPrank();

        _mockInsufficientAsset();

        uint256 bal_after = strategy.checkAvailableBalance(ASSET);
        assertEq(bal_after, IERC20(ASSET).balanceOf(strategy.assetToPToken(ASSET)));
    }

    function test_CollectReward() public {
        vm.expectRevert("No reward incentive for AAVE");
        strategy.collectReward();
    }

    function test_CheckInterestEarned_Empty() public {
        uint256 interest = strategy.checkInterestEarned(ASSET);
        assertEq(interest, 0);
    }
}
