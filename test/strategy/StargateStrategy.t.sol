// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {BaseTest} from "../utils/BaseTest.sol";
import {UpgradeUtil} from "../utils/UpgradeUtil.sol";
import {stdStorage, StdStorage} from "forge-std/StdStorage.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {StargateStrategy, ILPStaking, IStargatePool} from "../../contracts/strategies/stargate/StargateStrategy.sol";
import {VmSafe} from "forge-std/Vm.sol";

contract BaseStrategy {
    event VaultUpdated(address newVaultAddr);
    event YieldReceiverUpdated(address newYieldReceiver);
    event PTokenAdded(address indexed asset, address pToken);
    event PTokenRemoved(address indexed asset, address pToken);
    event Deposit(address indexed asset, address pToken, uint256 amount);
    event Withdrawal(address indexed asset, address pToken, uint256 amount);
    event SlippageChanged(uint16 depositSlippage, uint16 withdrawSlippage);
    event HarvestIncentiveCollected(
        address indexed token,
        address indexed harvestor,
        uint256 amount
    );
    event HarvestIncentiveRateUpdated(uint16 newRate);
    event InterestCollected(
        address indexed asset,
        address indexed recipient,
        uint256 amount
    );
    event RewardTokenCollected(
        address indexed rwdToken,
        address indexed recipient,
        uint256 amount
    );
}

contract StargateStrategyTest is BaseStrategy, BaseTest {
    struct AssetData {
        string name;
        address asset;
        address pToken;
        uint16 pid;
        uint256 rewardPid;
        uint256 intLiqThreshold;
    }

    // Strategy configuration:
    address public constant STARGATE_ROUTER =
        0x53Bf833A5d6c4ddA888F69c22C88C9f356a41614;
    address public constant STG = 0x6694340fc020c5E6B96567843da2df01b2CE1eb6;
    address public constant STARGATE_FARM =
        0xeA8DfEE1898a7e0a59f7527F076106d7e44c2176;
    uint16 public constant BASE_DEPOSIT_SLIPPAGE = 20;
    uint16 public constant BASE_WITHDRAW_SLIPPAGE = 20;

    // Test variables
    UpgradeUtil internal upgradeUtil;
    StargateStrategy internal impl;
    StargateStrategy internal strategy;
    address internal proxyAddress;

    // Test events
    event SkipRwdValidationStatus(bool status);
    event IntLiqThresholdChanged(
        address indexed asset,
        uint256 intLiqThreshold
    );

    function setUp() public virtual override {
        super.setUp();
        setArbitrumFork();

        vm.startPrank(USDS_OWNER);
        // Setup the upgrade params
        impl = new StargateStrategy();
        upgradeUtil = new UpgradeUtil();
        proxyAddress = upgradeUtil.deployErc1967Proxy(address(impl));

        // Load strategy object and initialize
        strategy = StargateStrategy(proxyAddress);
        vm.stopPrank();
    }

    function _initializeStrategy() internal {
        strategy.initialize(
            STARGATE_ROUTER,
            VAULT,
            STG,
            STARGATE_FARM,
            BASE_DEPOSIT_SLIPPAGE,
            BASE_WITHDRAW_SLIPPAGE
        );
    }

    function _setAssetData() internal {
        AssetData[] memory data = _getAssetConfig();
        for (uint8 i = 0; i < data.length; ++i) {
            strategy.setPTokenAddress(
                data[i].asset,
                data[i].pToken,
                data[i].pid,
                data[i].rewardPid,
                data[i].intLiqThreshold
            );
        }
    }

    function _createDeposits() internal {
        _setAssetData();
        AssetData[] memory data = _getAssetConfig();
        changePrank(VAULT);
        for (uint8 i = 0; i < data.length; ++i) {
            uint256 amount = 100;
            amount *= 10 ** ERC20(data[i].asset).decimals();
            deal(data[i].asset, VAULT, amount, true);
            ERC20(data[i].asset).approve(address(strategy), amount);
            strategy.deposit(data[i].asset, amount);
        }
    }

    // Mock Utils:
    function _mockInsufficientRwd(address asset) internal {
        // Do a time travel & mine dummy blocks for accumulating some rewards
        vm.warp(block.timestamp + 10 days);
        vm.roll(block.number + 1000);

        uint256 pendingRewards = strategy.checkPendingRewards(asset);
        assert(pendingRewards > 0);

        // MOCK: Withdraw rewards from the farm.
        changePrank(strategy.farm());
        ERC20(STG).transfer(actors[0], ERC20(STG).balanceOf(strategy.farm()));
        changePrank(currentActor);
    }

    function _getAssetConfig() internal pure returns (AssetData[] memory) {
        AssetData[] memory data = new AssetData[](2);
        data[0] = AssetData({
            name: "USDC.e",
            asset: 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8,
            pToken: 0x892785f33CdeE22A30AEF750F285E18c18040c3e,
            pid: 1,
            rewardPid: 0,
            intLiqThreshold: 0
        });

        data[1] = AssetData({
            name: "FRAX",
            asset: 0x17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F,
            pToken: 0xaa4BF442F024820B2C28Cd0FD72b82c63e66F56C,
            pid: 7,
            rewardPid: 3,
            intLiqThreshold: 0
        });
        return data;
    }
}

contract StrategyInitializationTest is StargateStrategyTest {
    function test_validInitialization() public useKnownActor(USDS_OWNER) {
        // Test state variables pre initialization
        assertEq(impl.owner(), address(0));
        assertEq(strategy.owner(), address(0));

        // Initialize strategy
        _initializeStrategy();

        // Test state variables post initializtion
        assertEq(impl.owner(), address(0));
        assertEq(strategy.owner(), USDS_OWNER);
        assertEq(strategy.vaultAddress(), VAULT);
        assertEq(strategy.router(), STARGATE_ROUTER);
        assertEq(strategy.farm(), STARGATE_FARM);
        assertEq(strategy.depositSlippage(), BASE_DEPOSIT_SLIPPAGE);
        assertEq(strategy.withdrawSlippage(), BASE_WITHDRAW_SLIPPAGE);
        assertEq(strategy.rewardTokenAddress(0), STG);
    }

    function test_invalidInitialization() public useKnownActor(USDS_OWNER) {
        vm.expectRevert("Invalid address");
        strategy.initialize(
            address(0),
            address(0),
            STG,
            STARGATE_FARM,
            BASE_DEPOSIT_SLIPPAGE,
            BASE_WITHDRAW_SLIPPAGE
        );
    }

    function test_updateVaultCore() public useKnownActor(USDS_OWNER) {
        _initializeStrategy();

        address newVault = address(1);
        vm.expectEmit(true, true, false, true);
        emit VaultUpdated(newVault);
        strategy.updateVaultCore(newVault);
    }

    function test_updateHarvestIncentiveRate()
        public
        useKnownActor(USDS_OWNER)
    {
        uint16 newRate = 100;
        _initializeStrategy();

        vm.expectEmit(true, false, false, true);
        emit HarvestIncentiveRateUpdated(newRate);
        strategy.updateHarvestIncentiveRate(newRate);

        newRate = 10001;
        vm.expectRevert("Invalid value");
        strategy.updateHarvestIncentiveRate(newRate);
    }
}

contract StrategySetPToken is StargateStrategyTest {
    function setUp() public override {
        super.setUp();
        vm.startPrank(USDS_OWNER);
        _initializeStrategy();
        vm.stopPrank();
    }

    function test_setPTokenAddress() public useKnownActor(USDS_OWNER) {
        AssetData[] memory data = _getAssetConfig();

        for (uint8 i = 0; i < data.length; ++i) {
            assertEq(strategy.assetToPToken(data[i].asset), address(0));
            assertFalse(strategy.supportsCollateral(data[i].asset));

            vm.expectEmit(true, true, false, true);
            emit PTokenAdded(data[i].asset, data[i].pToken);
            strategy.setPTokenAddress(
                data[i].asset,
                data[i].pToken,
                data[i].pid,
                data[i].rewardPid,
                data[i].intLiqThreshold
            );

            assertEq(strategy.assetToPToken(data[i].asset), data[i].pToken);
            assertTrue(strategy.supportsCollateral(data[i].asset));
            (
                uint256 allocatedAmt,
                uint256 intLiqThreshold,
                uint256 rewardPID,
                uint16 pid
            ) = strategy.assetInfo(data[i].asset);
            assertEq(allocatedAmt, 0);
            assertEq(intLiqThreshold, data[i].intLiqThreshold);
            assertEq(rewardPID, data[i].rewardPid);
            assertEq(pid, data[i].pid);
        }
    }

    function test_revertsWhen_notOwner() public {
        AssetData memory data = _getAssetConfig()[0];

        vm.expectRevert("Ownable: caller is not the owner");
        strategy.setPTokenAddress(
            data.asset,
            data.pToken,
            data.pid,
            data.rewardPid,
            data.intLiqThreshold
        );
    }

    function test_revertsWhen_InvalidPToken() public useKnownActor(USDS_OWNER) {
        AssetData memory data = _getAssetConfig()[0];
        data.pToken = _getAssetConfig()[1].pToken;

        vm.expectRevert("Incorrect asset & pToken pair");
        strategy.setPTokenAddress(
            data.asset,
            data.pToken,
            data.pid,
            data.rewardPid,
            data.intLiqThreshold
        );
    }

    function test_revertsWhen_InvalidPid() public useKnownActor(USDS_OWNER) {
        AssetData memory data = _getAssetConfig()[0];
        data.pid += 1;

        vm.expectRevert("Incorrect pool id");
        strategy.setPTokenAddress(
            data.asset,
            data.pToken,
            data.pid,
            data.rewardPid,
            data.intLiqThreshold
        );
    }

    function test_revertsWhen_InvalidRewardPid()
        public
        useKnownActor(USDS_OWNER)
    {
        AssetData memory data = _getAssetConfig()[0];
        data.rewardPid += 1;

        vm.expectRevert("Incorrect reward pid");
        strategy.setPTokenAddress(
            data.asset,
            data.pToken,
            data.pid,
            data.rewardPid,
            data.intLiqThreshold
        );
    }

    function test_revertsWhen_duplicateAsset()
        public
        useKnownActor(USDS_OWNER)
    {
        AssetData memory data = _getAssetConfig()[0];
        strategy.setPTokenAddress(
            data.asset,
            data.pToken,
            data.pid,
            data.rewardPid,
            data.intLiqThreshold
        );

        vm.expectRevert("pToken already set");
        strategy.setPTokenAddress(
            data.asset,
            data.pToken,
            data.pid,
            data.rewardPid,
            data.intLiqThreshold
        );
    }
}

contract StrategyRemovePToken is StargateStrategyTest {
    using stdStorage for StdStorage;

    function setUp() public override {
        super.setUp();
        vm.startPrank(USDS_OWNER);
        _initializeStrategy();
        _setAssetData();
        vm.stopPrank();
    }

    function test_removePToken() public useKnownActor(USDS_OWNER) {
        AssetData memory data = _getAssetConfig()[0];
        assertTrue(strategy.supportsCollateral(data.asset));
        vm.expectEmit(true, true, false, true);
        emit PTokenRemoved(data.asset, data.pToken);
        strategy.removePToken(0);
        assertFalse(strategy.supportsCollateral(data.asset));
    }

    function test_revertsWhen_notOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        strategy.removePToken(0);
    }

    function test_revertsWhen_assetAllocated()
        public
        useKnownActor(USDS_OWNER)
    {
        AssetData memory data = _getAssetConfig()[0];

        // Mock asset allocation!
        stdstore
            .target(address(strategy))
            .sig("assetInfo(address)")
            .with_key(data.asset)
            .depth(0)
            .checked_write(1e18);

        (uint256 allocatedAmt, , , ) = strategy.assetInfo(data.asset);

        assert(allocatedAmt > 0);
        vm.expectRevert("Collateral allocated");
        strategy.removePToken(0);
    }

    function test_revertsWhen_InvalidId() public useKnownActor(USDS_OWNER) {
        vm.expectRevert("Invalid index");
        strategy.removePToken(_getAssetConfig().length);
    }
}

contract StrategyUpdateIntLiqThreshold is StargateStrategyTest {
    function setUp() public override {
        super.setUp();
        vm.startPrank(USDS_OWNER);
        _initializeStrategy();
        _setAssetData();
        vm.stopPrank();
    }

    function test_updateIntLiqThreshold() public useKnownActor(USDS_OWNER) {
        AssetData memory data = _getAssetConfig()[0];
        uint256 newThreshold = 100e18;
        vm.expectEmit(true, true, false, true);
        emit IntLiqThresholdChanged(data.asset, newThreshold);
        strategy.updateIntLiqThreshold(data.asset, newThreshold);
        (, uint256 intLiqThreshold, , ) = strategy.assetInfo(data.asset);
        assertEq(intLiqThreshold, newThreshold);
    }

    function test_revertsWhen_notOwner() public {
        AssetData memory data = _getAssetConfig()[0];
        vm.expectRevert("Ownable: caller is not the owner");
        strategy.updateIntLiqThreshold(data.asset, 100e18);
    }

    function test_revertsWhen_assetNotSupported()
        public
        useKnownActor(USDS_OWNER)
    {
        vm.expectRevert("Asset not supported");
        strategy.updateIntLiqThreshold(address(0), 100e18);
    }

    function test_revertsWhen_updateToSameValue()
        public
        useKnownActor(USDS_OWNER)
    {
        AssetData memory data = _getAssetConfig()[0];
        (, uint256 intLiqThreshold, , ) = strategy.assetInfo(data.asset);
        vm.expectRevert("Invalid threshold value");
        strategy.updateIntLiqThreshold(address(0), intLiqThreshold);
    }
}

contract StrategyChangeSlippage is StargateStrategyTest {
    uint16 public updatedDepositSippage = 100;
    uint16 public updatedWithdrawSippage = 200;

    function setUp() public override {
        super.setUp();
        vm.startPrank(USDS_OWNER);
        _initializeStrategy();
        vm.stopPrank();
    }

    function test_changeSlippage() public useKnownActor(USDS_OWNER) {
        vm.expectEmit(true, false, false, true);
        emit SlippageChanged(updatedDepositSippage, updatedWithdrawSippage);
        strategy.changeSlippage(updatedDepositSippage, updatedWithdrawSippage);
        assertEq(strategy.depositSlippage(), updatedDepositSippage);
        assertEq(strategy.withdrawSlippage(), updatedWithdrawSippage);
    }

    function test_revertsWhen_notOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        strategy.changeSlippage(updatedDepositSippage, updatedWithdrawSippage);
    }

    function test_revertsWhen_slippageExceedsMax()
        public
        useKnownActor(USDS_OWNER)
    {
        vm.expectRevert("Slippage exceeds 100%");
        strategy.changeSlippage(10001, 10001);
    }
}

contract StrategytoggleRwdValidation is StargateStrategyTest {
    function setUp() public override {
        super.setUp();
        vm.startPrank(USDS_OWNER);
        _initializeStrategy();
        vm.stopPrank();
    }

    function test_toggleRwdValidation() public useKnownActor(USDS_OWNER) {
        bool currentFlag = strategy.skipRwdValidation();
        strategy.toggleRwdValidation();
        assertEq(strategy.skipRwdValidation(), !currentFlag);

        strategy.toggleRwdValidation();
        assertEq(strategy.skipRwdValidation(), currentFlag);
    }

    function test_revertsWhen_notOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        strategy.toggleRwdValidation();
    }
}

contract StrategyDeposit is StargateStrategyTest {
    function setUp() public override {
        super.setUp();
        vm.startPrank(USDS_OWNER);
        _initializeStrategy();
        _setAssetData();
        vm.stopPrank();
    }

    function test_deposit(uint256 amount) public useKnownActor(VAULT) {
        amount = uint256(bound(amount, 1, 1e10));
        AssetData[] memory data = _getAssetConfig();
        for (uint8 i = 0; i < data.length; ++i) {
            uint256 scaledAmt = amount * 10 ** ERC20(data[i].asset).decimals();
            deal(data[i].asset, VAULT, scaledAmt, true);
            ERC20(data[i].asset).approve(address(strategy), scaledAmt);
            vm.recordLogs();
            strategy.deposit(data[i].asset, scaledAmt);

            VmSafe.Log[] memory logs = vm.getRecordedLogs();
            address pToken;
            uint256 amt;
            for (uint8 j = 0; j < logs.length; ++j) {
                if (
                    logs[j].topics[0] ==
                    keccak256("Deposit(address,address,uint256)")
                ) {
                    (pToken, amt) = abi.decode(
                        logs[j].data,
                        (address, uint256)
                    );
                }
            }
            assertEq(strategy.checkBalance(data[i].asset), amt);
        }
    }

    function test_revertsWhen_invalidAmount() public useKnownActor(VAULT) {
        AssetData memory data = _getAssetConfig()[0];
        vm.expectRevert("Invalid amount");
        strategy.deposit(data.asset, 0);
    }

    function test_revertsWhen_notVault() public {
        AssetData memory data = _getAssetConfig()[0];
        vm.expectRevert("Caller is not the Vault");
        strategy.deposit(data.asset, 1000);
    }

    function test_revertsWhen_unsupportedCollateral()
        public
        useKnownActor(VAULT)
    {
        AssetData memory data = _getAssetConfig()[0];
        uint256 amount = 1000000;

        // Remove the asset for testing unsupported collateral.
        changePrank(USDS_OWNER);
        strategy.removePToken(0);

        changePrank(VAULT);
        amount *= 10 ** ERC20(data.asset).decimals();
        deal(data.asset, VAULT, amount, true);
        ERC20(data.asset).approve(address(strategy), amount);

        vm.expectRevert("Collateral not supported");
        strategy.deposit(data.asset, amount);
    }

    function test_revertsWhen_depositSlippageViolated()
        public
        useKnownActor(VAULT)
    {
        AssetData memory data = _getAssetConfig()[0];
        uint256 amount = 1000000;

        // Update the deposit slippage to 0
        changePrank(USDS_OWNER);
        strategy.changeSlippage(0, 0);

        changePrank(VAULT);
        amount *= 10 ** ERC20(data.asset).decimals();
        deal(data.asset, VAULT, amount, true);
        ERC20(data.asset).approve(address(strategy), amount);

        vm.expectRevert("Insufficient deposit amount");
        strategy.deposit(data.asset, amount);
    }

    function test_revertsWhen_notEnoughRwdInFarm() public useKnownActor(VAULT) {
        AssetData memory data = _getAssetConfig()[0];
        uint256 amount = 1000000;

        amount *= 10 ** ERC20(data.asset).decimals();
        deal(data.asset, VAULT, amount, true);
        ERC20(data.asset).approve(address(strategy), amount);

        // Create initial deposit
        strategy.deposit(data.asset, amount / 2);

        _mockInsufficientRwd(data.asset);

        vm.expectRevert("Insufficient rwd fund in farm");
        strategy.deposit(data.asset, amount / 2);
        assertEq(strategy.checkAvailableBalance(data.asset), 0);

        changePrank(USDS_OWNER);
        strategy.toggleRwdValidation();
        assertTrue(strategy.checkAvailableBalance(data.asset) > 0);

        // Test successful deposit
        assert(strategy.skipRwdValidation());
        changePrank(VAULT);
        strategy.deposit(data.asset, amount / 2);
    }
}

contract StrategyHarvestTest is StargateStrategyTest {
    address public yieldReceiver;

    function setUp() public override {
        super.setUp();
        vm.startPrank(USDS_OWNER);
        _initializeStrategy();
        yieldReceiver = actors[0];
        // Mock Vault yieldReceiver function
        vm.mockCall(
            VAULT,
            abi.encodeWithSignature("yieldReceiver()"),
            abi.encode(yieldReceiver)
        );
        _createDeposits();
        vm.stopPrank();
    }
}

contract StrategyCollecReward is StrategyHarvestTest {
    function test_collectReward(uint16 _harvestIncentiveRate) public {
        _harvestIncentiveRate = uint16(bound(_harvestIncentiveRate, 0, 10000));
        vm.prank(USDS_OWNER);
        strategy.updateHarvestIncentiveRate(_harvestIncentiveRate);
        uint256 initialRewards = strategy.checkRewardEarned();

        assert(initialRewards == 0);

        // Do a time travel & mine dummy blocks for accumulating some rewards
        vm.warp(block.timestamp + 10 days);
        vm.roll(block.number + 1000);

        uint256 currentRewards = strategy.checkRewardEarned();
        assert(currentRewards > 0);
        uint256 incentiveAmt = (currentRewards *
            strategy.harvestIncentiveRate()) / strategy.PERCENTAGE_PREC();
        uint256 harvestAmt = currentRewards - incentiveAmt;
        address caller = actors[1];

        if (incentiveAmt > 0) {
            vm.expectEmit(true, true, false, true);
            emit HarvestIncentiveCollected(STG, caller, incentiveAmt);
        }
        vm.expectEmit(true, true, false, true);
        emit RewardTokenCollected(STG, yieldReceiver, harvestAmt);
        vm.prank(caller);
        strategy.collectReward();

        assertEq(ERC20(STG).balanceOf(yieldReceiver), harvestAmt);
        assertEq(ERC20(STG).balanceOf(caller), incentiveAmt);

        currentRewards = strategy.checkRewardEarned();
        assert(currentRewards == 0);
    }
}

contract StrategyCollectIntererst is StrategyHarvestTest {
    using stdStorage for StdStorage;

    function test_collectInterest() public {
        AssetData[] memory data = _getAssetConfig();
        for (uint8 i = 0; i < data.length; ++i) {
            // uint256 initialInterest = strategy.checkInterestEarned(data[i].asset);
            uint256 initialLPBal = strategy.checkLPTokenBalance(data[i].asset);
            uint256 interestAmt = 10 * 10 ** ERC20(data[i].pToken).decimals();
            uint256 mockBal = initialLPBal + interestAmt;

            uint256 initialBal = strategy.checkBalance(data[i].asset);
            uint256 intialAvailableBal = strategy.checkAvailableBalance(
                data[i].asset
            );

            // Mock asset allocation!
            stdstore
                .target(strategy.farm())
                .sig("userInfo(uint256,address)")
                .with_key(data[i].rewardPid)
                .with_key(address(strategy))
                .depth(0)
                .checked_write(mockBal);

            assertEq(
                strategy.checkAvailableBalance(data[i].asset),
                intialAvailableBal
            );
            uint256 interestEarned = strategy.checkInterestEarned(
                data[i].asset
            );
            assertEq(strategy.checkBalance(data[i].asset), initialBal);
            assertEq(strategy.checkLPTokenBalance(data[i].asset), mockBal);
            assertTrue(interestEarned > 0);

            vm.expectEmit(true, false, false, false);
            emit InterestCollected(
                data[i].asset,
                yieldReceiver,
                interestEarned
            );
            strategy.collectInterest(data[i].asset);
            /// @note precision Error from stargate
            assertApproxEqAbs(
                strategy.checkLPTokenBalance(data[i].asset),
                initialLPBal,
                1
            );
        }
    }

    function test_interestLessThanThreshold() public {
        AssetData[] memory data = _getAssetConfig();
        for (uint8 i = 0; i < data.length; ++i) {
            uint256 interestAmt = strategy.checkInterestEarned(data[i].asset);

            vm.prank(USDS_OWNER);
            strategy.updateIntLiqThreshold(data[i].asset, 1);

            strategy.collectInterest(data[i].asset);
            assertEq(strategy.checkInterestEarned(data[i].asset), interestAmt);
        }
    }

    function test_revertsWhen_unsupportedAsset() public {
        vm.expectRevert("Collateral not supported");
        strategy.collectInterest(address(0));
    }
}

contract StrategyWithdraw is StargateStrategyTest {
    using stdStorage for StdStorage;

    function setUp() public override {
        super.setUp();
        vm.startPrank(USDS_OWNER);
        _initializeStrategy();
        _createDeposits();
        vm.stopPrank();
    }

    function test_withdraw() public useKnownActor(VAULT) {
        AssetData[] memory data = _getAssetConfig();
        for (uint8 i = 0; i < data.length; ++i) {
            ERC20 collateral = ERC20(data[i].asset);
            uint256 initialBal = strategy.checkBalance(data[i].asset);
            uint256 initialVaultBal = collateral.balanceOf(VAULT);

            vm.expectEmit(true, false, false, false);
            emit Withdrawal(data[i].asset, data[i].pToken, initialBal);
            strategy.withdraw(VAULT, data[i].asset, initialBal);
            assertApproxEqAbs(
                collateral.balanceOf(VAULT),
                initialVaultBal + initialBal,
                IStargatePool(data[i].pToken).convertRate()
            );
        }
    }

    function test_withdrawToVault() public useKnownActor(USDS_OWNER) {
        AssetData[] memory data = _getAssetConfig();
        for (uint8 i = 0; i < data.length; ++i) {
            ERC20 collateral = ERC20(data[i].asset);
            uint256 initialBal = strategy.checkBalance(data[i].asset);
            uint256 initialVaultBal = collateral.balanceOf(VAULT);

            vm.expectEmit(true, false, false, false);
            emit Withdrawal(data[i].asset, data[i].pToken, initialBal);
            strategy.withdrawToVault(data[i].asset, initialBal);
            assertApproxEqAbs(
                collateral.balanceOf(VAULT),
                initialVaultBal + initialBal,
                1 * IStargatePool(data[i].pToken).convertRate()
            );
        }
    }

    function test_revertsWhen_withdraw0() public useKnownActor(USDS_OWNER) {
        AssetData memory data = _getAssetConfig()[0];
        vm.expectRevert("Must withdraw something");
        strategy.withdrawToVault(data.asset, 0);
    }

    function test_revertsWhen_insufficientRwdInFarm()
        public
        useKnownActor(USDS_OWNER)
    {
        AssetData memory data = _getAssetConfig()[0];
        ERC20 collateral = ERC20(data.asset);
        uint256 initialBal = strategy.checkBalance(data.asset);
        uint256 initialVaultBal = collateral.balanceOf(VAULT);

        _mockInsufficientRwd(data.asset);
        vm.expectRevert("Insufficient rwd fund in farm");
        strategy.withdrawToVault(data.asset, initialBal);

        // Test skipping rwd validation.
        strategy.toggleRwdValidation();
        strategy.withdrawToVault(data.asset, initialBal);
        assertApproxEqAbs(
            collateral.balanceOf(VAULT),
            initialVaultBal + initialBal,
            1 * IStargatePool(data.pToken).convertRate()
        );
        assertEq(strategy.checkPendingRewards(data.asset), 0);
    }

    function test_revertsWhen_SlippageCheckFails()
        public
        useKnownActor(USDS_OWNER)
    {
        AssetData memory data = _getAssetConfig()[0];
        uint256 initialBal = strategy.checkBalance(data.asset);

        // set withdraw slippage to 0 for extreme test.
        strategy.changeSlippage(BASE_DEPOSIT_SLIPPAGE, 0);
        vm.expectRevert("Did not withdraw enough");
        strategy.withdrawToVault(data.asset, initialBal);
    }

    function test_revertsWhen_enoughFundsNotAvailable()
        public
        useKnownActor(USDS_OWNER)
    {
        AssetData memory data = _getAssetConfig()[0];
        uint256 initialBal = strategy.checkBalance(data.asset);

        uint256 initialAvailableBal = strategy.checkAvailableBalance(
            data.asset
        );

        // mock scenario for stargate pool not having enough funds
        stdstore.target(data.pToken).sig("deltaCredit()").checked_write(1);

        assertTrue(
            strategy.checkAvailableBalance(data.asset) < initialAvailableBal
        );

        vm.expectRevert("Did not withdraw enough");
        strategy.withdrawToVault(data.asset, initialBal);
    }
}

contract StrategyEdgeCases is StargateStrategyTest {
    function setUp() public override {
        super.setUp();
        vm.startPrank(USDS_OWNER);
        _initializeStrategy();
        _createDeposits();
        vm.stopPrank();
    }

    function test_balance_onLoss() public {
        AssetData memory data = _getAssetConfig()[0];
        uint256 initialBal = strategy.checkBalance(data.asset);

        // mock scenario
        // note: This scenario is hypothetical an should not happen in reality.
        uint256 initialTotalLiq = IStargatePool(data.pToken).totalLiquidity();
        vm.mockCall(
            data.pToken,
            abi.encodeWithSignature("totalLiquidity()"),
            abi.encode(initialTotalLiq / 2)
        );

        assertTrue(strategy.checkBalance(data.asset) < initialBal);
    }
}
