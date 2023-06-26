// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {BaseTest} from "../utils/BaseTest.sol";
import {UpgradeUtil} from "../utils/UpgradeUtil.sol";
import {stdStorage, StdStorage} from "forge-std/StdStorage.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {StargateStrategy} from "../../contracts/strategies/stargate/StargateStrategy.sol";

contract StargateStrategyTest is BaseTest {
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
    uint256 public constant BASE_DEPOSIT_SLIPPAGE = 20;
    uint256 public constant BASE_WITHDRAW_SLIPPAGE = 20;

    // Test variables
    UpgradeUtil internal upgradeUtil;
    StargateStrategy internal impl;
    StargateStrategy internal strategy;
    address internal proxyAddress;

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
            name: "USDT",
            asset: 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9,
            pToken: 0xB6CfcF89a7B22988bfC96632aC2A9D6daB60d641,
            pid: 2,
            rewardPid: 1,
            intLiqThreshold: 0
        });
        return data;
    }
}

contract StrategyInitializationTest is StargateStrategyTest {
    function test_validInitialization() external useKnownActor(USDS_OWNER) {
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
        vm.stopPrank();
    }

    function test_removePToken() public useKnownActor(USDS_OWNER) {
        AssetData[] memory data = _getAssetConfig();
        assertTrue(strategy.supportsCollateral(data[0].asset));
        strategy.removePToken(0);
        assertFalse(strategy.supportsCollateral(data[0].asset));
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
        vm.stopPrank();
    }

    function test_updateIntLiqThreshold() public useKnownActor(USDS_OWNER) {
        AssetData memory data = _getAssetConfig()[0];
        uint256 newThreshold = 100e18;
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
    uint256 public updatedDepositSippage = 100;
    uint256 public updatedWithdrawSippage = 100;

    function setUp() public override {
        super.setUp();
        vm.startPrank(USDS_OWNER);
        _initializeStrategy();
        vm.stopPrank();
    }

    function test_changeSlippage() public useKnownActor(USDS_OWNER) {
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
        vm.stopPrank();
    }

    function test_deposit(uint256 amount) public useKnownActor(VAULT) {
        amount = uint256(bound(amount, 1, 1e10));
        AssetData[] memory data = _getAssetConfig();
        for (uint8 i = 0; i < data.length; ++i) {
            amount *= 10 ** ERC20(data[i].asset).decimals();
            deal(data[i].asset, VAULT, amount, true);
            ERC20(data[i].asset).approve(address(strategy), amount);
            strategy.deposit(data[i].asset, amount);
            assertApproxEqAbs(
                strategy.checkBalance(data[i].asset),
                amount,
                1e2
            );
            // @todo fix error in checkAvailableBal
            // assertApproxEqAbs(strategy.checkAvailableBalance(data[i].asset), amount, 1e2);
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

        // Do a time travel & mine dummy blocks for accumulating some rewards
        vm.warp(block.timestamp + 10 days);
        vm.roll(block.number + 1000);

        uint256 pendingRewards = strategy.checkPendingRewards(data.asset);
        assert(pendingRewards > 0);

        // MOCK: Withdraw rewards from the farm.
        changePrank(strategy.farm());
        ERC20(STG).transfer(actors[0], ERC20(STG).balanceOf(strategy.farm()));

        changePrank(VAULT);
        vm.expectRevert("Insufficient rwd fund in farm");
        strategy.deposit(data.asset, amount / 2);

        changePrank(USDS_OWNER);
        strategy.toggleRwdValidation();

        // Test successful deposit
        assert(strategy.skipRwdValidation());
        changePrank(VAULT);
        strategy.deposit(data.asset, amount / 2);
    }
}

contract StrategyHarvest is StargateStrategyTest {
    address public yieldReceiver;

    function setUp() public override {
        super.setUp();
        vm.startPrank(USDS_OWNER);
        _initializeStrategy();
        uint256 amount = 1000000;
        yieldReceiver = actors[0];

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

        changePrank(VAULT);
        for (uint8 i = 0; i < data.length; ++i) {
            amount *= 10 ** ERC20(data[i].asset).decimals();
            deal(data[i].asset, VAULT, amount, true);
            ERC20(data[i].asset).approve(address(strategy), amount);
            strategy.deposit(data[i].asset, amount);
        }
        vm.stopPrank();
    }

    function test_collectReward() public {
        uint256 initialRewards = strategy.checkRewardEarned();
        assert(initialRewards == 0);

        // Do a time travel & mine dummy blocks for accumulating some rewards
        vm.warp(block.timestamp + 10 days);
        vm.roll(block.number + 1000);

        uint256 currentRewards = strategy.checkRewardEarned();
        assert(currentRewards > 0);

        // Mock Vault yieldReceiver function
        vm.mockCall(
            VAULT,
            abi.encodeWithSignature("yieldReceiver()"),
            abi.encode(yieldReceiver)
        );

        strategy.collectReward();

        assertEq(ERC20(STG).balanceOf(yieldReceiver), currentRewards);

        currentRewards = strategy.checkRewardEarned();
        assert(currentRewards == 0);
    }
}
