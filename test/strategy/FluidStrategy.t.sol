// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {BaseStrategy} from "./BaseStrategy.t.sol";
import {BaseTest} from "../utils/BaseTest.sol";
import {UpgradeUtil} from "../utils/UpgradeUtil.sol";
import {FluidStrategy, IFluidToken} from "../../contracts/strategies/fluid/FluidStrategy.sol";
import {Helpers} from "../../contracts/libraries/Helpers.sol";
import {IERC20, ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {InitializableAbstractStrategy} from "../../contracts/strategies/InitializableAbstractStrategy.sol";
import {IVault} from "../../contracts/interfaces/IVault.sol";
import {console} from "forge-std/console.sol";

interface ICollateralManager {
    function addCollateralStrategy(address _collateral, address _strategy, uint16 _allocationCap) external;
    function removeCollateralStrategy(address _collateral, address _strategy) external;
    function getCollateralInStrategies(address _collateral) external view returns (uint256);
    function getCollateralInVault(address _collateral) external view returns (uint256);
    function getCollateralStrategies(address _collateral) external view returns (address[] memory);
    function getCollateralInAStrategy(address _collateral, address _strategy) external view returns (uint256);
    function updateCollateralStrategy(address _collateral, address _strategy, uint16 _cap) external;
}

interface IStrategy {
    function withdrawToVault(address _asset, uint256 _amount) external returns (uint256);
    function checkAvailableBalance(address _asset) external view returns (uint256);
}

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
    uint16 internal constant depositSlippage = 50;
    uint16 internal constant withdrawSlippage = 50;
    uint256 public constant BLOCKS_MINED_IN_A_DAY = 5750;
    address internal constant DEFAULT_STRATEGY = 0xb9C9100720D8c6E35eb8dd0F9C1aBEf320dAA136;
    address internal constant ALTERNATE_STRATEGY = 0x974993eE8DF7F5C4F3f9Aa4eB5b4534F359f3388;
    address internal constant FLUID_STRATEGY = 0xa503A325fc97310b6c2FEeAaDeb8816481E0BDAb;

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

    function _allocateIntoStrategy(address __collateral, address _strategy, uint256 _amount) internal useActor(1) {
        IVault(VAULT).allocate(__collateral, _strategy, _amount);
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
        vm.expectEmit(true, false, false, true);
        emit Deposit(ASSET, depositAmount);
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

contract WithdrawTestss is FluidStrategyTest {
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
        timeTravel(10 days);
        vm.expectEmit(true, false, false, false);
        emit Withdrawal(ASSET, depositAmount);
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

contract MiscellaneousTestss is FluidStrategyTest {
    address private redeemer;
    uint256 private _usdsAmt;
    uint256 private _minCollAmt;
    uint256 private _deadline;

    function setUp() public override {
        super.setUp();
        redeemer = actors[1];
        _usdsAmt = 1000e18;
        vm.startPrank(USDS_OWNER);
        _initializeStrategy();
        strategy.setPTokenAddress(ASSET, P_TOKEN);
        vm.stopPrank();
    }

    function test_CheckRewardEarned() public {
        InitializableAbstractStrategy.RewardData[] memory rewardData = strategy.checkRewardEarned();
        assertEq(rewardData.length, 0);
    }

    function test_CheckBalance() public {
        (uint256 balance) = strategy.allocatedAmount(ASSET);
        uint256 bal = strategy.checkBalance(ASSET);
        assertEq(bal, balance);
    }

    function test_CollectReward() public {
        vm.expectRevert(abi.encodeWithSelector(NoRewardIncentive.selector));
        strategy.collectReward();
    }

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

    function test_CheckAvailableBalance_large_deposit() public {
        vm.startPrank(VAULT);
        deal(address(ASSET), VAULT, 1e12);
        IERC20(ASSET).approve(address(strategy), 1e12);
        strategy.deposit(ASSET, 1e12);
        vm.stopPrank();
        vm.mockCall(
            address(strategy), abi.encodeWithSignature("_getAvailableLiquidity(address)", ASSET), abi.encode(1e30)
        );
        strategy.checkAvailableBalance(ASSET);
    }
}

contract IntegrationTests is FluidStrategyTest {
    address private redeemer;
    uint256 private _usdsAmt;
    uint256 private _minCollAmt;
    uint256 private _deadline;

    function setUp() public override {
        super.setUp();
        redeemer = actors[1];
        _usdsAmt = 1000e18;
        vm.startPrank(USDS_OWNER);
        _initializeStrategy();
        strategy.setPTokenAddress(ASSET, P_TOKEN);
        vm.stopPrank();
    }
    /**
     * @dev Tests the allocation of an amount from the vault to the strategy.
     *
     * This function performs the following steps:
     * 1. Sets a cap for the collateral strategy.
     * 2. Checks the initial balance and LP token balance of the strategy.
     * 3. Asserts that the initial LP token balance is zero.
     * 4. Starts a prank as the USDS owner.
     * 5. Withdraws the available balance from an alternate strategy to the vault.
     * 6. Removes the alternate strategy from the collateral manager.
     * 7. Adds the current strategy to the collateral manager with the specified cap.
     * 8. Calculates the maximum deposit amount based on the cap and the vault's balance.
     * 9. Deals the asset to the vault.
     * 10. Allocates the calculated amount into the strategy.
     * 11. Checks the new balance and LP token balance of the strategy.
     * 12. Asserts that the new balance is equal to the initial balance plus the maximum deposit.
     * 13. Asserts that the new LP token balance is approximately equal to the initial LP token balance plus the maximum deposit, allowing for a 4% slippage.
     */

    function test_allocateAmountFromVault() public {
        uint16 cap = 3000;
        uint256 initial_bal = strategy.checkBalance(ASSET);
        uint256 initialLPBalance = strategy.checkLPTokenBalance(ASSET);
        assert(initialLPBalance == 0);
        vm.startPrank(USDS_OWNER);
        uint256 VaultBalance = IStrategy(ALTERNATE_STRATEGY).checkAvailableBalance(ASSET);
        IStrategy(ALTERNATE_STRATEGY).withdrawToVault(ASSET, VaultBalance);
        ICollateralManager(COLLATERAL_MANAGER).removeCollateralStrategy(ASSET, ALTERNATE_STRATEGY);
        ICollateralManager(COLLATERAL_MANAGER).addCollateralStrategy(ASSET, address(strategy), cap);
        uint256 maxDeposit = (
            cap
                * (ERC20(ASSET).balanceOf(VAULT) + ICollateralManager(COLLATERAL_MANAGER).getCollateralInStrategies(ASSET))
        ) / 10000;
        deal(ASSET, VAULT, depositAmount);
        _allocateIntoStrategy(ASSET, address(strategy), maxDeposit);
        uint256 new_bal = strategy.checkBalance(ASSET);
        uint256 newLPBalance = strategy.checkLPTokenBalance(ASSET);
        assertEq(initial_bal + maxDeposit, new_bal);
        assertApproxEqRel(initialLPBalance + maxDeposit, newLPBalance, 4e16); // 4% slippage
    }

    /**
     * @dev Test function to withdraw assets from an alternate strategy to the vault and reallocate them to a new strategy.
     *
     * This function performs the following steps:
     * 1. Retrieves the available balance from the alternate strategy.
     * 2. Withdraws the entire balance from the alternate strategy to the vault.
     * 3. Removes the alternate strategy from the collateral manager.
     * 4. Adds a new strategy to the collateral manager with a specified cap.
     * 5. Calculates the maximum deposit amount based on the cap and current balances.
     * 6. Allocates half of the maximum deposit amount into the new strategy.
     * 7. Advances the blockchain time by 10 hours.
     * 8. Sets a deadline for the mint and redeem operations.
     * 9. Calculates the collateral amount required for redemption.
     * 10. Mints new tokens by depositing assets into the vault.
     * 11. Redeems the minted tokens for the underlying asset.
     */
    function test_WithdrawToVaultFromAllocation() public useKnownActor(USDS_OWNER) {
        uint16 cap = 2000;
        uint256 VaultBalance = IStrategy(ALTERNATE_STRATEGY).checkAvailableBalance(ASSET);
        IStrategy(ALTERNATE_STRATEGY).withdrawToVault(ASSET, VaultBalance);
        ICollateralManager(COLLATERAL_MANAGER).removeCollateralStrategy(ASSET, ALTERNATE_STRATEGY);
        ICollateralManager(COLLATERAL_MANAGER).addCollateralStrategy(ASSET, address(strategy), cap);
        uint256 maxDeposit = (
            cap
                * (ERC20(ASSET).balanceOf(VAULT) + ICollateralManager(COLLATERAL_MANAGER).getCollateralInStrategies(ASSET))
        ) / 10000;
        deal(ASSET, VAULT, depositAmount);
        _allocateIntoStrategy(ASSET, address(strategy), maxDeposit / 2);
        timeTravel(1 hours);
        _deadline = block.timestamp + 120;

        (uint256 _calculatedCollateralAmt,,,,) = IVault(VAULT).redeemView(ASSET, maxDeposit / 20);
        vm.startPrank(USDS_OWNER);
        deal(ASSET, USDS_OWNER, depositAmount);
        ERC20(ASSET).approve(VAULT, depositAmount);
        IVault(VAULT).mint(ASSET, depositAmount, 10e5, _deadline);
        ERC20(USDS).approve(VAULT, _usdsAmt);
        IVault(VAULT).redeem(ASSET, _usdsAmt, _calculatedCollateralAmt, _deadline, address(strategy));
    }
}

contract FluidSimulations is IntegrationTests {
    ICollateralManager collateralManager;

    uint256[] collateralAmounts;
    address[2] COLLATERALS = [USDT, USDC];

    function test_simulation() external {
        vm.prank(USDS_OWNER);
        strategy.setPTokenAddress(data[1].asset, data[1].pToken);

        collateralManager = ICollateralManager(COLLATERAL_MANAGER);

        console.log("removing deployed fluid strategy");
        uint256 USDTAmount = collateralManager.getCollateralInAStrategy(USDT, FLUID_STRATEGY);
        uint256 USDCAmount = collateralManager.getCollateralInAStrategy(USDC, FLUID_STRATEGY);

        vm.prank(USDS_OWNER);
        IStrategy(FLUID_STRATEGY).withdrawToVault(USDT, USDTAmount);
        vm.prank(USDS_OWNER);
        IStrategy(FLUID_STRATEGY).withdrawToVault(USDC, USDCAmount);
        vm.prank(USDS_OWNER);
        collateralManager.removeCollateralStrategy(USDC, FLUID_STRATEGY);
        vm.prank(USDS_OWNER);
        collateralManager.removeCollateralStrategy(USDT, FLUID_STRATEGY);

        for (uint8 c; c < COLLATERALS.length; c++) {
            console.log("\nCollateral address:", COLLATERALS[c]);
            address[] memory collateralStrategies = collateralManager.getCollateralStrategies(COLLATERALS[c]);

            // Getting the amounts
            collateralAmounts.push(collateralManager.getCollateralInVault(COLLATERALS[c]));
            uint256 totalCollateralUSDT = collateralAmounts[0];
            for (uint8 i; i < collateralStrategies.length; i++) {
                collateralAmounts.push(
                    collateralManager.getCollateralInAStrategy(COLLATERALS[c], collateralStrategies[i])
                );
                totalCollateralUSDT += collateralAmounts[i + 1];
            }
            uint256 collateralPerStrategy = totalCollateralUSDT / 3;
            collateralPerStrategy -= 10e6;
            console.log("\nTotal collateral:", totalCollateralUSDT / 1e6);
            console.log("\nCollateral per strategy:", collateralPerStrategy / 1e6);

            // Balancing the strategies and adjusting the allocation caps
            console.log("\nConfiguring collateral strategies in Collateral manager");
            for (uint8 i; i < collateralStrategies.length; i++) {
                if (collateralAmounts[i + 1] > collateralPerStrategy) {
                    uint256 amountToWithdraw = collateralAmounts[i + 1] - collateralPerStrategy;
                    vm.prank(USDS_OWNER);
                    IStrategy(collateralStrategies[i]).withdrawToVault(COLLATERALS[c], amountToWithdraw);
                }

                vm.prank(USDS_OWNER);
                collateralManager.updateCollateralStrategy(COLLATERALS[c], collateralStrategies[i], 3333);
            }
            // Adding fluid strategy
            console.log("Adding fluid strategy");
            vm.prank(USDS_OWNER);
            collateralManager.addCollateralStrategy(COLLATERALS[c], address(strategy), 3334);

            // collateralPerStrategy -= 10e6;
            // Allocating to the strategy (Deposit)
            console.log("Depositing in the strategy:", collateralPerStrategy / 1e6);
            IVault(VAULT).allocate(COLLATERALS[c], address(strategy), collateralPerStrategy);
            assertTrue(strategy.checkAvailableBalance(COLLATERALS[c]) >= collateralPerStrategy - 1);
            timeTravel(10 minutes);

            // Claiming interest
            uint256 interestEarned = strategy.checkInterestEarned(COLLATERALS[c]);
            console.log("\nInterest earned is:", interestEarned);
            assert(interestEarned != 0);
            console.log("Claiming interest");
            uint256 harvestorBalBefore = IERC20(COLLATERALS[c]).balanceOf(actors[0]);
            uint256 yieldReceiverBalBefore = IERC20(COLLATERALS[c]).balanceOf(IVault(VAULT).yieldReceiver());
            vm.prank(actors[0]);
            strategy.collectInterest(COLLATERALS[c]);
            uint256 harvestorBalAfter = IERC20(COLLATERALS[c]).balanceOf(actors[0]);
            uint256 yieldReceiverBalAfter = IERC20(COLLATERALS[c]).balanceOf(IVault(VAULT).yieldReceiver());
            uint256 receivedInterest =
                (harvestorBalAfter - harvestorBalBefore) + (yieldReceiverBalAfter - yieldReceiverBalBefore);
            assertTrue(receivedInterest >= interestEarned);
            console.log("Received interest:", receivedInterest);

            // Withdrawing from the strategy
            uint256 balBefore = IERC20(COLLATERALS[c]).balanceOf(VAULT);
            vm.prank(VAULT);
            strategy.withdraw(VAULT, COLLATERALS[c], collateralPerStrategy / 2);
            uint256 balAfter = IERC20(COLLATERALS[c]).balanceOf(VAULT);
            uint256 difference = balAfter - balBefore;

            assertTrue(difference >= collateralPerStrategy / 2);
            console.log("\nSuccessfully withdrawn:", difference / 1e6);

            // cleanup
            collateralAmounts.pop();
            collateralAmounts.pop();
            collateralAmounts.pop();
        }
    }
}
