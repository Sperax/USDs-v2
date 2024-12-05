// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {console} from "forge-std/console.sol";
import {BaseStrategy} from "./BaseStrategy.t.sol";
import {BaseTest} from "../utils/BaseTest.sol";
import {UpgradeUtil} from "../utils/UpgradeUtil.sol";
import {FluidStrategy, IFluidToken} from "../../contracts/strategies/fluid/FluidStrategy.sol";
import {Helpers} from "../../contracts/libraries/Helpers.sol";
import {IERC20, ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {InitializableAbstractStrategy} from "../../contracts/strategies/InitializableAbstractStrategy.sol";

contract FluidStrategyTest is BaseStrategy, BaseTest {
    struct AssetData {
        string name;
        address asset;
        address pToken;
    }

    AssetData[] public data;

    FluidStrategy internal strategy;
    FluidStrategy internal impl;
    UpgradeUtil internal upgradeUtil;
    uint256 internal depositAmount;
    uint256 internal interestAmount;
    address internal proxyAddress;
    address internal yieldReceiver;
    address internal ASSET;
    address internal P_TOKEN;
    uint16 internal constant depositSlippage = 200;
    uint16 internal constant withdrawSlippage = 200;
    uint256 public constant BLOCKS_MINED_IN_A_DAY = 5750;

    error NoRewardIncentive();
    error LimitReached();

    function setUp() public virtual override {
        super.setUp();
        setArbitrumFork();
        yieldReceiver = actors[0];
        vm.startPrank(USDS_OWNER);
        impl = new FluidStrategy();
        upgradeUtil = new UpgradeUtil();
        proxyAddress = upgradeUtil.deployErc1967Proxy(address(impl));

        strategy = FluidStrategy(proxyAddress);
        _configAsset();
        ASSET = data[0].asset;
        P_TOKEN = data[0].pToken;
        depositAmount = 1e6 * 10 ** ERC20(ASSET).decimals();
        interestAmount = 10 * 10 ** ERC20(ASSET).decimals();
        vm.stopPrank();
    }

    function _initializeStrategy() internal {
        strategy.initialize(VAULT, depositSlippage, withdrawSlippage);
    }

    function timeTravel(uint256 num) internal {
        vm.warp(block.timestamp + (num));
        vm.roll(block.number + (num / 1 days * BLOCKS_MINED_IN_A_DAY));
    }

    function _configAsset() internal {
        data.push(
            AssetData({
                name: "USDT",
                asset: 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9,
                pToken: 0x4A03F37e7d3fC243e3f99341d36f4b829BEe5E03
            })
        );
        data.push(
            AssetData({
                name: "USDC",
                asset: 0xaf88d065e77c8cC2239327C5EDb3A432268e5831,
                pToken: 0x1A996cb54bb95462040408C06122D45D6Cdb6096
            })
        );
    }

    function _setAssetData() internal {
        for (uint8 i = 0; i < data.length; ++i) {
            strategy.setPTokenAddress(data[i].asset, data[i].pToken);
        }
    }

    function _mockInsufficientAsset() internal {
        vm.startPrank(strategy.assetToPToken(ASSET));
        IERC20(ASSET).transfer(actors[0], IERC20(ASSET).balanceOf(strategy.assetToPToken(ASSET)));
        vm.stopPrank();
    }

    function _deposit() internal {
        changePrank(VAULT);
        deal(ASSET, VAULT, depositAmount);
        IERC20(ASSET).approve(address(strategy), depositAmount);
        strategy.deposit(ASSET, depositAmount);
        timeTravel(1 days);
        changePrank(USDS_OWNER);
    }

    function _depositHugeAmount() internal {
        depositAmount = 1e10 * 10 ** ERC20(ASSET).decimals();
        changePrank(VAULT);
        deal(ASSET, VAULT, depositAmount);
        IERC20(ASSET).approve(address(strategy), depositAmount);
        strategy.deposit(ASSET, depositAmount);
        timeTravel(1 days);
    }
}

contract InitializeTests is FluidStrategyTest {
    function test_invalid_address() public useKnownActor(USDS_OWNER) {
        vm.expectRevert(abi.encodeWithSelector(Helpers.InvalidAddress.selector));
        strategy.initialize(address(0), depositSlippage, withdrawSlippage);
    }

    function test_fuzz_invalid_deposit_slippage(uint256 depositSlippage) public useKnownActor(USDS_OWNER) {
        depositSlippage = uint16(bound(depositSlippage, uint256(10001), uint256(65535)));
        vm.expectRevert(abi.encodeWithSelector(Helpers.GTMaxPercentage.selector, depositSlippage));
        strategy.initialize(VAULT, uint16(depositSlippage), withdrawSlippage);
    }

    function test_fuzz_invalid_withdraw_slippage(uint256 withdrawSlippage) public useKnownActor(USDS_OWNER) {
        withdrawSlippage = uint16(bound(withdrawSlippage, uint256(10001), uint256(65535)));
        vm.expectRevert(abi.encodeWithSelector(Helpers.GTMaxPercentage.selector, withdrawSlippage));
        strategy.initialize(VAULT, depositSlippage, uint16(withdrawSlippage));
    }

    function test_initialization() public useKnownActor(USDS_OWNER) {
        assertEq(impl.owner(), address(0));
        assertEq(strategy.owner(), address(0));
        _initializeStrategy();
        assertEq(impl.owner(), address(0));
        assertEq(strategy.owner(), USDS_OWNER);
        assertEq(strategy.vault(), VAULT);
        assertEq(strategy.depositSlippage(), depositSlippage);
        assertEq(strategy.withdrawSlippage(), withdrawSlippage);
    }
}

contract SetPTokenTest is FluidStrategyTest {
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
        address INVALID_P_TOKEN = 0xe0C97480CA7BDb33B2CD9810cC7f103188de4383;
        vm.expectRevert();
        strategy.setPTokenAddress(ASSET, INVALID_P_TOKEN);
    }

    function test_RevertWhen_InvalidPToken_anotherAsset() public useKnownActor(USDS_OWNER) {
        address ANOTHER_ASSET_PTOKEN = 0xbE3860FD4c3facDf8ad57Aa8c1A36D6dc4390a49;
        vm.expectRevert(abi.encodeWithSelector(InvalidAssetLpPair.selector, ASSET, ANOTHER_ASSET_PTOKEN));
        strategy.setPTokenAddress(ASSET, ANOTHER_ASSET_PTOKEN);
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

contract RemovePTokenTest is FluidStrategyTest {
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

contract DepositTest is FluidStrategyTest {
    function setUp() public override {
        super.setUp();
        vm.startPrank(USDS_OWNER);
        _initializeStrategy();
        _setAssetData();
        vm.stopPrank();
    }

    function test_deposit_Collateral_not_supported() public useKnownActor(VAULT) {
        vm.expectRevert(abi.encodeWithSelector(CollateralNotSupported.selector, makeAddr("DUMMY")));
        strategy.deposit(makeAddr("DUMMY"), 100);
    }

    function test_RevertWhen_InvalidAmount() public useKnownActor(VAULT) {
        vm.expectRevert(abi.encodeWithSelector(Helpers.CustomError.selector, ("Must deposit something")));
        strategy.deposit(ASSET, 0);
    }

    function test_RevertWhen_LimitReached() public useKnownActor(VAULT) {
        uint256 maxDeposit = IFluidToken(P_TOKEN).maxDeposit(address(strategy));
        vm.expectRevert(abi.encodeWithSelector(LimitReached.selector));
        strategy.deposit(ASSET, maxDeposit + 1);
    }

    function test_RevertWhen_insufficientSharesMintedOnDeposit() public useKnownActor(VAULT) {
        uint256 maxDeposit = IFluidToken(P_TOKEN).maxDeposit(address(strategy));
        deal(ASSET, VAULT, maxDeposit);
        IERC20(ASSET).approve(address(strategy), maxDeposit);
        uint256 minDepositAmt =
            (maxDeposit * (Helpers.MAX_PERCENTAGE - strategy.depositSlippage())) / Helpers.MAX_PERCENTAGE;
        vm.mockCall(address(P_TOKEN), abi.encodeWithSignature("convertToAssets(uint256)"), abi.encode(maxDeposit / 2));
        vm.expectRevert(abi.encodeWithSelector(Helpers.MinSlippageError.selector, maxDeposit / 2, minDepositAmt));
        strategy.deposit(ASSET, maxDeposit);
    }

    function testFuzz_Deposit(uint256 _depositAmount) public useKnownActor(VAULT) {
        depositAmount = bound(_depositAmount, 1 * 10 ** ERC20(ASSET).decimals(), 1e6 * 10 ** ERC20(ASSET).decimals());
        uint256 initial_bal = strategy.checkBalance(ASSET);
        uint256 initialLPBalance = strategy.checkLPTokenBalance(ASSET);
        emit log_named_uint("initial LP balance", initialLPBalance);
        assert(initialLPBalance == 0);
        deal(ASSET, VAULT, depositAmount);
        IERC20(ASSET).approve(address(strategy), depositAmount);
        strategy.deposit(ASSET, depositAmount);
        uint256 new_bal = strategy.checkBalance(ASSET);
        uint256 newLPBalance = strategy.checkLPTokenBalance(ASSET);
        assertEq(initial_bal + depositAmount, new_bal);
        assertApproxEqRel(initialLPBalance + depositAmount, newLPBalance, 4e16); // 4% slippage
    }
}

contract CollectInterestTest is FluidStrategyTest {
    function setUp() public override {
        super.setUp();
        vm.startPrank(USDS_OWNER);
        _initializeStrategy();
        strategy.setPTokenAddress(ASSET, P_TOKEN);

        _deposit();
        vm.stopPrank();
    }

    function test_CollectInterest() public useKnownActor(VAULT) {
        timeTravel(10 days);
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
        assertApproxEqAbs(strategy.checkInterestEarned(ASSET), 0, 1);
        assertEq(current_bal, (initial_bal + harvestAmount));
    }
}

contract WithdrawTest is FluidStrategyTest {
    function setUp() public override {
        super.setUp();
        vm.startPrank(USDS_OWNER);
        _initializeStrategy();
        _setAssetData();
        _deposit();
        vm.stopPrank();
    }

    function test_RevertWhen_insufficientSharesMintedOnWithdraw() public useKnownActor(VAULT) {
        uint256 shares = IFluidToken(P_TOKEN).previewWithdraw(depositAmount);
        uint256 minRecvAmt =
            (depositAmount * (Helpers.MAX_PERCENTAGE - strategy.withdrawSlippage())) / Helpers.MAX_PERCENTAGE;
        vm.mockCall(
            address(P_TOKEN),
            abi.encodeWithSignature("redeem(uint256,address,address)", shares, VAULT, address(strategy)),
            abi.encode(minRecvAmt / 2)
        );
        vm.expectRevert(abi.encodeWithSelector(Helpers.MinSlippageError.selector, minRecvAmt / 2, minRecvAmt));
        strategy.withdraw(VAULT, ASSET, depositAmount);
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

    function test_revertWhen_limitIsReached() public useKnownActor(VAULT) {
        _depositHugeAmount();
        // emit Withdrawal(ASSET, depositAmount * 10e6);
        timeTravel(10 days);
        vm.expectRevert(abi.encodeWithSelector(LimitReached.selector));
        strategy.withdraw(VAULT, ASSET, depositAmount * 10e6);
    }

    function test_WithdrawToVault_RevertsIf_CallerNotOwner() public useActor(0) {
        uint256 initialVaultBal = IERC20(ASSET).balanceOf(VAULT);
        uint256 interestAmt = strategy.checkInterestEarned(ASSET);
        uint256 amt = initialVaultBal + interestAmt;
        vm.expectRevert("Ownable: caller is not the owner");
        strategy.withdrawToVault(ASSET, amt);
    }

    function test_Withdraw() public useKnownActor(VAULT) {
        uint256 initialVaultBal = IERC20(ASSET).balanceOf(VAULT);
        vm.expectEmit(true, false, false, true);
        emit Withdrawal(ASSET, depositAmount);
        timeTravel(10 days);
        strategy.withdraw(VAULT, ASSET, depositAmount);
        assertEq(initialVaultBal + depositAmount, IERC20(ASSET).balanceOf(VAULT));
    }

    function test_WithdrawToVault() public useKnownActor(USDS_OWNER) {
        uint256 initialVaultBal = IERC20(ASSET).balanceOf(VAULT);
        timeTravel(10 days);
        vm.expectEmit(true, false, false, true);
        emit Withdrawal(ASSET, depositAmount);
        strategy.withdrawToVault(ASSET, depositAmount);
        assertEq(initialVaultBal + depositAmount, IERC20(ASSET).balanceOf(VAULT));
    }
}

contract MiscellaneousTest is FluidStrategyTest {
    function setUp() public override {
        super.setUp();
        vm.startPrank(USDS_OWNER);
        _initializeStrategy();
        strategy.setPTokenAddress(ASSET, P_TOKEN);
        vm.stopPrank();
    }

    function test_CheckRewardEarned() public {
        InitializableAbstractStrategy.RewardData[] memory rewardData = strategy.checkRewardEarned();
        assertEq(rewardData.length, 0);
    }

    // function test_CheckBalance() public {
    //     (uint256 balance) = strategy.allocatedAmount(ASSET);
    //     uint256 bal = strategy.checkBalance(ASSET);
    //     assertEq(bal, balance);
    // }

    function test_CheckAvailableBalance() public {
        vm.startPrank(VAULT);
        deal(address(ASSET), VAULT, depositAmount);
        IERC20(ASSET).approve(address(strategy), depositAmount);
        strategy.deposit(ASSET, depositAmount);
        vm.stopPrank();

        uint256 bal_after = strategy.checkAvailableBalance(ASSET);
        assertApproxEqAbs(bal_after, depositAmount, 5);
    }

    function test_CheckAvailableBalance_small_deposit() public {
        vm.startPrank(VAULT);
        deal(address(ASSET), VAULT, 1e6);
        IERC20(ASSET).approve(address(strategy), 1e6);
        strategy.deposit(ASSET, 1e6);
        vm.stopPrank();

        uint256 bal_after = strategy.checkAvailableBalance(ASSET);
        assertApproxEqAbs(bal_after, 1e6, 5);
    }

    function test_CollectReward() public {
        vm.expectRevert(abi.encodeWithSelector(NoRewardIncentive.selector));
        strategy.collectReward();
    }
}
