// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {BaseTest} from "../utils/BaseTest.sol";
import {UpgradeUtil} from "../utils/UpgradeUtil.sol";
import {AaveStrategy} from "../../contracts/strategies/aave/AaveStrategy.sol";
import {InitializableAbstractStrategy} from "../../contracts/strategies/InitializableAbstractStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

address constant AAVE_POOL_PROVIDER = 0xa97684ead0e402dC232d5A977953DF7ECBaB3CDb;
address constant VAULT_ADDRESS = 0xa97684ead0e402dC232d5A977953DF7ECBaB3CDb;
address constant ASSET = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
address constant P_TOKEN = 0xe50fA9b3c56FfB159cB0FCA61F5c9D750e8128c8;
address constant DUMMY_ADDRESS = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

contract AaveStrategyTest is BaseTest {
    AaveStrategy internal aaveStrategy;
    AaveStrategy internal impl;
    UpgradeUtil internal upgradeUtil;
    address internal proxyAddress;

    event IntLiqThresholdChanged(
        address indexed asset,
        uint256 intLiqThreshold
    );
    event PTokenRemoved(address indexed asset, address pToken);
    event PTokenAdded(address indexed asset, address pToken);
    event InterestCollected(
        address indexed asset,
        address indexed recipient,
        uint256 amount
    );
    event Withdrawal(address indexed asset, address pToken, uint256 amount);

    function setUp() public virtual override {
        super.setUp();
        setArbitrumFork();
        vm.startPrank(USDS_OWNER);
        impl = new AaveStrategy();
        upgradeUtil = new UpgradeUtil();
        proxyAddress = upgradeUtil.deployErc1967Proxy(address(impl));

        aaveStrategy = AaveStrategy(proxyAddress);
        vm.stopPrank();
    }

    function _initializeStrategy() internal {
        aaveStrategy.initialize(AAVE_POOL_PROVIDER, VAULT_ADDRESS);
    }

    function _deposit() internal {
        aaveStrategy.setPTokenAddress(ASSET, P_TOKEN, 0);
        changePrank(VAULT_ADDRESS);
        deal(address(ASSET), VAULT_ADDRESS, 1 ether);
        IERC20(ASSET).approve(address(aaveStrategy), 1000);
        aaveStrategy.deposit(ASSET, 1);
        changePrank(USDS_OWNER);
    }

    function _mockInsufficientAsset() internal {
        vm.startPrank(aaveStrategy.assetToPToken(ASSET));
        IERC20(ASSET).transfer(
            actors[0],
            IERC20(ASSET).balanceOf(aaveStrategy.assetToPToken(ASSET))
        );
        vm.stopPrank();
    }
}

contract InitializeTests is AaveStrategyTest {
    function test_empty_address() public useKnownActor(USDS_OWNER) {
        vm.expectRevert("Invalid address");

        aaveStrategy.initialize(address(0), VAULT_ADDRESS);

        vm.expectRevert("Invalid address");

        aaveStrategy.initialize(AAVE_POOL_PROVIDER, address(0));
    }

    function test_success() public useKnownActor(USDS_OWNER) {
        assertEq(impl.owner(), address(0));
        assertEq(aaveStrategy.owner(), address(0));

        _initializeStrategy();

        assertEq(impl.owner(), address(0));
        assertEq(aaveStrategy.owner(), USDS_OWNER);
        assertEq(aaveStrategy.vaultAddress(), VAULT_ADDRESS);
        assertNotEq(aaveStrategy.aavePool.address, address(0));
    }
}

contract PtokenTest is AaveStrategyTest {
    function setUp() public override {
        super.setUp();
        vm.startPrank(USDS_OWNER);
        _initializeStrategy();
        vm.stopPrank();
    }

    function test_revertsWhen_unAuthorized_SetPtoken() public useActor(0) {
        vm.expectRevert("Ownable: caller is not the owner");
        aaveStrategy.setPTokenAddress(ASSET, P_TOKEN, 0);
    }

    function test_setPtoken_invalid_pair() public useKnownActor(USDS_OWNER) {
        vm.expectRevert("Incorrect asset-lpToken pair");
        aaveStrategy.setPTokenAddress(
            ASSET,
            0x625E7708f30cA75bfd92586e17077590C60eb4cD,
            0
        );
    }

    function test_SetPtoken() public useKnownActor(USDS_OWNER) {
        vm.expectEmit(true, false, false, false);
        assertEq(aaveStrategy.assetToPToken(ASSET), address(0));

        emit PTokenAdded(address(ASSET), address(P_TOKEN));

        aaveStrategy.setPTokenAddress(ASSET, P_TOKEN, 0);

        (, uint256 intLiqThreshold) = aaveStrategy.assetInfo(ASSET);

        assertEq(intLiqThreshold, 0);
        assertEq(aaveStrategy.assetToPToken(ASSET), P_TOKEN);
        assertTrue(aaveStrategy.supportsCollateral(ASSET));
    }

    function test_revert_ptoken_already_set() public useKnownActor(USDS_OWNER) {
        aaveStrategy.setPTokenAddress(ASSET, P_TOKEN, 0);
        vm.expectRevert("pToken already set");
        aaveStrategy.setPTokenAddress(ASSET, P_TOKEN, 0);
    }

    function test_revertsWhen_unAuthorized_updateIntLiqThreshold()
        public
        useActor(0)
    {
        vm.expectRevert("Ownable: caller is not the owner");

        aaveStrategy.updateIntLiqThreshold(P_TOKEN, 2);
    }

    function test_revert_Collateral_not_supported_updateIntLiqThreshold()
        public
        useKnownActor(USDS_OWNER)
    {
        vm.expectRevert("Collateral not supported");

        aaveStrategy.updateIntLiqThreshold(P_TOKEN, 2);
    }

    function test_updateIntLiqThreshold() public useKnownActor(USDS_OWNER) {
        aaveStrategy.setPTokenAddress(ASSET, P_TOKEN, 0);

        vm.expectEmit(true, false, false, false);
        emit IntLiqThresholdChanged(address(ASSET), uint256(2));

        aaveStrategy.updateIntLiqThreshold(ASSET, 2);

        (, uint256 intLiqThreshold) = aaveStrategy.assetInfo(ASSET);
        assertEq(intLiqThreshold, 2);
    }

    function test_auth_failures() public useActor(0) {
        vm.expectRevert("Ownable: caller is not the owner");
        aaveStrategy.removePToken(0);
    }

    function test_invalid_index() public useKnownActor(USDS_OWNER) {
        vm.expectRevert("Invalid index");
        aaveStrategy.removePToken(5);
    }

    function test_collateral_allocated_failures()
        public
        useKnownActor(USDS_OWNER)
    {
        _deposit();
        vm.expectRevert("Collateral allocated");
        aaveStrategy.removePToken(0);
    }

    function test_RemovePToken() public useKnownActor(USDS_OWNER) {
        aaveStrategy.setPTokenAddress(ASSET, P_TOKEN, 1);

        vm.expectEmit(true, false, false, false);
        emit PTokenRemoved(address(ASSET), address(P_TOKEN));

        aaveStrategy.removePToken(0);

        (uint256 allocatedAmt, uint256 intLiqThreshold) = aaveStrategy
            .assetInfo(ASSET);

        assertEq(allocatedAmt, 0);
        assertEq(intLiqThreshold, 0);
        assertEq(aaveStrategy.assetToPToken(ASSET), address(0));
        assertFalse(aaveStrategy.supportsCollateral(ASSET));
    }
}

contract DepositTest is AaveStrategyTest {
    function setUp() public override {
        super.setUp();
        vm.startPrank(USDS_OWNER);
        _initializeStrategy();
        aaveStrategy.setPTokenAddress(ASSET, P_TOKEN, 0);
        vm.stopPrank();
    }

    function test_deposit_unauthorized_call() public useActor(0) {
        vm.expectRevert("Caller is not the Vault");
        aaveStrategy.deposit(DUMMY_ADDRESS, 1);
    }

    function test_deposit_Collateral_not_supported()
        public
        useKnownActor(VAULT_ADDRESS)
    {
        vm.expectRevert("Collateral not supported");
        aaveStrategy.deposit(DUMMY_ADDRESS, 1);
    }

    function test_deposit_invalid_deposit()
        public
        useKnownActor(VAULT_ADDRESS)
    {
        vm.expectRevert("Must deposit something");
        aaveStrategy.deposit(ASSET, 0);
    }

    function test_deposit() public useKnownActor(VAULT_ADDRESS) {
        uint256 initial_bal = aaveStrategy.checkBalance(ASSET);

        deal(address(ASSET), VAULT_ADDRESS, 1 ether);
        IERC20(ASSET).approve(address(aaveStrategy), 1000);
        aaveStrategy.deposit(ASSET, 1);

        uint256 newl_bal = aaveStrategy.checkBalance(ASSET);
        assertEq(initial_bal + 1, newl_bal);
    }
}

contract CollectInterestTest is AaveStrategyTest {
    address public yieldReceiver;

    function setUp() public override {
        super.setUp();
        yieldReceiver = actors[0];
        vm.startPrank(USDS_OWNER);
        _initializeStrategy();
        aaveStrategy.setPTokenAddress(ASSET, P_TOKEN, 0);

        changePrank(VAULT_ADDRESS);
        deal(address(ASSET), VAULT_ADDRESS, 1 ether);
        IERC20(ASSET).approve(address(aaveStrategy), 1000);
        aaveStrategy.deposit(ASSET, 1000);
        vm.stopPrank();
    }

    function test_collect_interest_faliures() public useKnownActor(USDS_OWNER) {
        vm.expectRevert("Caller is not the Vault");
        aaveStrategy.collectInterest(DUMMY_ADDRESS);
    }

    function test_collect_interest() public useKnownActor(VAULT_ADDRESS) {
        vm.warp(block.timestamp + 10 days);
        vm.roll(block.number + 1000);

        uint256 initial_bal = IERC20(ASSET).balanceOf(yieldReceiver);

        vm.mockCall(
            VAULT_ADDRESS,
            abi.encodeWithSignature("yieldReceiver()"),
            abi.encode(yieldReceiver)
        );

        uint256 interestEarned = aaveStrategy.checkInterestEarned(ASSET);

        assert(interestEarned > 0);

        uint256 harvestAmount = (interestEarned * 10) / 10000;

        //vm.expectEmit(true, false, false, true);

        //emit InterestCollected(ASSET, yieldReceiver, harvestAmount);

        aaveStrategy.collectInterest(ASSET);

        uint256 current_bal = IERC20(ASSET).balanceOf(yieldReceiver);

        uint256 newinterestEarned = aaveStrategy.checkInterestEarned(ASSET);

        assertEq(newinterestEarned, 0);
        //assertEq(current_bal, (initial_bal + interestAmts[0]));
    }
}

contract WithdrawTest is AaveStrategyTest {
    address public yieldReceiver;

    function setUp() public override {
        super.setUp();
        yieldReceiver = actors[0];
        vm.startPrank(USDS_OWNER);
        _initializeStrategy();
        aaveStrategy.setPTokenAddress(ASSET, P_TOKEN, 0);

        changePrank(VAULT_ADDRESS);
        deal(address(ASSET), VAULT_ADDRESS, 1 ether);
        IERC20(ASSET).approve(address(aaveStrategy), 1000);
        aaveStrategy.deposit(ASSET, 1000);
        vm.stopPrank();
    }

    function test_withdraw_Invalid_address()
        public
        useKnownActor(VAULT_ADDRESS)
    {
        vm.expectRevert("Invalid address");
        aaveStrategy.withdraw(address(0), ASSET, 1);

        vm.expectRevert("Invalid amount");
        aaveStrategy.withdraw(VAULT_ADDRESS, ASSET, 0);
    }

    function test_withdraw_auth_errors() public useActor(0) {
        vm.expectRevert("Caller is not the Vault");
        aaveStrategy.withdraw(VAULT_ADDRESS, ASSET, 1);
    }

    function test_withdraw() public useKnownActor(VAULT_ADDRESS) {
        uint256 initialVaultBal = IERC20(ASSET).balanceOf(VAULT_ADDRESS);
        uint256 amt = 1000;

        vm.expectEmit(true, false, false, true);
        emit Withdrawal(ASSET, aaveStrategy.assetToPToken(ASSET), amt);

        vm.warp(block.timestamp + 10 days);
        vm.roll(block.number + 1000);

        aaveStrategy.withdraw(VAULT_ADDRESS, ASSET, amt);
        assertEq(initialVaultBal + amt, IERC20(ASSET).balanceOf(VAULT_ADDRESS));
    }

    function test_withdrawToVault() public useKnownActor(USDS_OWNER) {
        uint256 initialVaultBal = IERC20(ASSET).balanceOf(VAULT_ADDRESS);
        uint256 amt = 1000;

        vm.warp(block.timestamp + 10 days);
        vm.roll(block.number + 1000);

        vm.expectEmit(true, false, false, true);
        emit Withdrawal(ASSET, aaveStrategy.assetToPToken(ASSET), amt);

        aaveStrategy.withdrawToVault(ASSET, amt);
        assertEq(initialVaultBal + amt, IERC20(ASSET).balanceOf(VAULT_ADDRESS));
    }
}

contract MiscellaneousTest is AaveStrategyTest {
    function setUp() public override {
        super.setUp();
        vm.startPrank(USDS_OWNER);
        _initializeStrategy();
        aaveStrategy.setPTokenAddress(ASSET, P_TOKEN, 0);
    }

    function test_checkRewardEarned() public {
        assertEq(aaveStrategy.checkRewardEarned(), 0);
    }

    function test_checkBalance() public {
        (uint256 balance, ) = aaveStrategy.assetInfo(ASSET);
        uint256 bal = aaveStrategy.checkBalance(ASSET);
        assertEq(bal, balance);
    }

    function test_checkAvailableBalance() public {
        vm.startPrank(VAULT_ADDRESS);
        deal(address(ASSET), VAULT_ADDRESS, 1 ether);
        IERC20(ASSET).approve(address(aaveStrategy), 1000);
        aaveStrategy.deposit(ASSET, 1000);
        vm.stopPrank();

        uint256 bal_after = aaveStrategy.checkAvailableBalance(ASSET);
        assertEq(bal_after, 1000);
    }

    function test_checkAvailableBalance_unsufficent_tokens() public {
        vm.startPrank(VAULT_ADDRESS);
        deal(address(ASSET), VAULT_ADDRESS, 1 ether);
        IERC20(ASSET).approve(address(aaveStrategy), 1000);
        aaveStrategy.deposit(ASSET, 1000);
        vm.stopPrank();

        _mockInsufficientAsset();

        uint256 bal_after = aaveStrategy.checkAvailableBalance(ASSET);
        assertEq(
            bal_after,
            IERC20(ASSET).balanceOf(aaveStrategy.assetToPToken(ASSET))
        );
    }

    function test_collectReward() public {
        vm.expectRevert("No reward incentive for AAVE");
        aaveStrategy.collectReward();
    }

    function test_checkInterestEarned_empty() public {
        uint256 interest = aaveStrategy.checkInterestEarned(ASSET);
        assertEq(interest, 0);
    }
}
