// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {console} from "forge-std/console.sol";
import {BaseStrategy} from "./BaseStrategy.t.sol";
import {BaseTest} from "../utils/BaseTest.sol";
import {UpgradeUtil} from "../utils/UpgradeUtil.sol";
import {Helpers, CompoundStrategy, IComet} from "../../contracts/strategies/compound/CompoundStrategy.sol";
import {IERC20, ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract CompoundStrategyTest is BaseStrategy, BaseTest {

    struct AssetData {
        string name;
        address asset;
        address pToken;
        uint256 intLiqThreshold;
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

    event IntLiqThresholdUpdated(
        address indexed asset,
        uint256 intLiqThreshold
    );

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
            strategy.setPTokenAddress(
                data[i].asset,
                data[i].pToken,
                data[i].intLiqThreshold
            );
        }
    }

    function _configAsset() internal {
        data.push(
            AssetData({
                name: "USDC.e",
                asset: 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8,
                pToken: 0xA5EDBDD9646f8dFF606d7448e414884C7d905dCA,
                intLiqThreshold: 0
            })
        );
    }

    function _mockInsufficientAsset() internal {
        vm.startPrank(strategy.assetToPToken(ASSET));
        IERC20(ASSET).transfer(
            actors[0],
            IERC20(ASSET).balanceOf(strategy.assetToPToken(ASSET))
        );
        vm.stopPrank();
    }
}

contract InitializeTests is CompoundStrategyTest {
    function test_invalid_address() public useKnownActor(USDS_OWNER) {
        vm.expectRevert(
            abi.encodeWithSelector(Helpers.InvalidAddress.selector)
        );
        strategy.initialize(address(0), VAULT);

        vm.expectRevert(
            abi.encodeWithSelector(Helpers.InvalidAddress.selector)
        );
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
        strategy.setPTokenAddress(ASSET, P_TOKEN, 0);
    }

    function test_RevertWhen_InvalidPToken() public useKnownActor(USDS_OWNER) {
        address OTHER_P_TOKEN = 0x9c4ec768c28520B50860ea7a15bd7213a9fF58bf;
        vm.expectRevert(
            abi.encodeWithSelector(
                InvalidAssetLpPair.selector,
                ASSET,
                OTHER_P_TOKEN
            )
        );
        strategy.setPTokenAddress(ASSET, OTHER_P_TOKEN, 0);
    }

    function test_SetPTokenAddress() public useKnownActor(USDS_OWNER) {
        assertEq(strategy.assetToPToken(ASSET), address(0));

        vm.expectEmit(true, false, false, false);
        emit PTokenAdded(address(ASSET), address(P_TOKEN));
        strategy.setPTokenAddress(ASSET, P_TOKEN, 0);

        (, uint256 intLiqThreshold) = strategy.assetInfo(ASSET);

        assertEq(intLiqThreshold, 0);
        assertEq(strategy.assetToPToken(ASSET), P_TOKEN);
        assertTrue(strategy.supportsCollateral(ASSET));
    }

    function test_RevertWhen_DuplicateAsset() public useKnownActor(USDS_OWNER) {
        strategy.setPTokenAddress(ASSET, P_TOKEN, 0);
        vm.expectRevert(
            abi.encodeWithSelector(PTokenAlreadySet.selector, ASSET, P_TOKEN)
        );
        strategy.setPTokenAddress(ASSET, P_TOKEN, 0);
    }
}

contract UpdateIntLiqThresholdTest is CompoundStrategyTest {
    function setUp() public override {
        super.setUp();
        vm.startPrank(USDS_OWNER);
        _initializeStrategy();
        _setAssetData();
        vm.stopPrank();
    }

    function test_RevertWhen_NotOwner() public useActor(0) {
        vm.expectRevert("Ownable: caller is not the owner");
        strategy.updateIntLiqThreshold(ASSET, 2);
    }

    function test_RevertWhen_CollateralNotSupported()
        public
        useKnownActor(USDS_OWNER)
    {
        vm.expectRevert(
            abi.encodeWithSelector(CollateralNotSupported.selector, P_TOKEN)
        );
        strategy.updateIntLiqThreshold(P_TOKEN, 2);
    }

    function test_UpdateIntLiqThreshold() public useKnownActor(USDS_OWNER) {
        vm.expectEmit(true, false, false, false);
        emit IntLiqThresholdUpdated(address(ASSET), uint256(2));
        strategy.updateIntLiqThreshold(ASSET, 2);
        (, uint256 intLiqThreshold) = strategy.assetInfo(ASSET);
        assertEq(intLiqThreshold, 2);
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

    function test_RevertWhen_CollateralAllocated()
        public
        useKnownActor(USDS_OWNER)
    {
        _deposit();
        vm.expectRevert(
            abi.encodeWithSelector(CollateralAllocated.selector, ASSET)
        );
        strategy.removePToken(0);
    }

    function test_RemovePToken() public useKnownActor(USDS_OWNER) {
        assertEq(strategy.assetToPToken(ASSET), P_TOKEN);
        assertTrue(strategy.supportsCollateral(ASSET));

        vm.expectEmit(true, false, false, false);
        emit PTokenRemoved(ASSET, P_TOKEN);
        strategy.removePToken(0);

        (uint256 allocatedAmt, uint256 intLiqThreshold) = strategy.assetInfo(
            ASSET
        );

        assertEq(allocatedAmt, 0);
        assertEq(intLiqThreshold, 0);
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

    function test_deposit_Collateral_not_supported()
        public
        useKnownActor(VAULT)
    {
        vm.expectRevert(
            abi.encodeWithSelector(
                CollateralNotSupported.selector,
                makeAddr('DUMMY')
            )
        );
        strategy.deposit(makeAddr('DUMMY'), 1);
    }

    function test_RevertWhen_InvalidAmount() public useKnownActor(VAULT) {
        vm.expectRevert(abi.encodeWithSelector(Helpers.InvalidAmount.selector));
        strategy.deposit(ASSET, 0);
    }

    function test_Deposit() public useKnownActor(VAULT) {
        uint256 initial_bal = strategy.checkBalance(ASSET);

        deal(ASSET, VAULT, depositAmount);
        IERC20(ASSET).approve(address(strategy), depositAmount);
        strategy.deposit(ASSET, depositAmount);

        uint256 new_bal = strategy.checkBalance(ASSET);
        assertEq(initial_bal + depositAmount, new_bal);
    }
}

contract CollectInterestTest is CompoundStrategyTest {
    function setUp() public override {
        super.setUp();
        vm.startPrank(USDS_OWNER);
        _initializeStrategy();
        strategy.setPTokenAddress(ASSET, P_TOKEN, 0);

        _deposit();
        vm.stopPrank();
    }

    function test_CollectInterest() public useKnownActor(VAULT) {
        vm.warp(block.timestamp + 10 days);
        vm.roll(block.number + 1000);
        uint256 initial_bal = IERC20(ASSET).balanceOf(yieldReceiver);

        // IComet(P_TOKEN).accrueAccount(address(strategy));
        vm.mockCall(
            VAULT,
            abi.encodeWithSignature("yieldReceiver()"),
            abi.encode(yieldReceiver)
        );

        
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

contract WithdrawTest is CompoundStrategyTest {
    function setUp() public override {
        super.setUp();
        vm.startPrank(USDS_OWNER);
        _initializeStrategy();
        strategy.setPTokenAddress(ASSET, P_TOKEN, 0);

        _deposit();
        vm.stopPrank();
    }

    function test_RevertWhen_Withdraw0() public useKnownActor(USDS_OWNER) {
        AssetData memory assetData = data[0];
        vm.expectRevert(
            abi.encodeWithSelector(
                Helpers.CustomError.selector,
                "Must withdraw something"
            )
        );
        strategy.withdrawToVault(assetData.asset, 0);
    }

    function test_RevertWhen_InvalidAddress() public useKnownActor(VAULT) {
        vm.expectRevert(
            abi.encodeWithSelector(Helpers.InvalidAddress.selector)
        );
        strategy.withdraw(address(0), ASSET, 1);
    }

    function test_RevertWhen_CallerNotVault() public useActor(0) {
        vm.expectRevert(
            abi.encodeWithSelector(CallerNotVault.selector, actors[0])
        );
        strategy.withdraw(VAULT, ASSET, 1);
    }

    function test_Withdraw() public useKnownActor(VAULT) {
        uint256 initialVaultBal = IERC20(ASSET).balanceOf(VAULT);

        vm.expectEmit(true, false, false, true);
        emit Withdrawal(ASSET, strategy.assetToPToken(ASSET), depositAmount);

        vm.warp(block.timestamp + 10 days);
        vm.roll(block.number + 1000);

        strategy.withdraw(VAULT, ASSET, depositAmount);
        assertEq(initialVaultBal + depositAmount, IERC20(ASSET).balanceOf(VAULT));
    }

    function test_WithdrawToVault_RevertsIf_CallerNotOwner() public useActor(0) {
        uint256 initialVaultBal = IERC20(ASSET).balanceOf(VAULT);
        uint256 interestAmt = strategy.checkInterestEarned(ASSET);
        uint256 amt = depositAmount + interestAmount;

        vm.expectRevert("Ownable: caller is not the owner");
        strategy.withdrawToVault(ASSET, amt);
    }

    function test_WithdrawToVault() public useKnownActor(USDS_OWNER) {
        uint256 initialVaultBal = IERC20(ASSET).balanceOf(VAULT);

        vm.warp(block.timestamp + 10 days);
        vm.roll(block.number + 1000);

        vm.expectEmit(true, false, false, true);
        emit Withdrawal(ASSET, strategy.assetToPToken(ASSET), depositAmount);

        strategy.withdrawToVault(ASSET, depositAmount);
        assertEq(initialVaultBal + depositAmount, IERC20(ASSET).balanceOf(VAULT));
    }
}
