// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {BaseTest} from "../BaseTest.sol";
import {UpgradeUtil} from "../utils/UpgradeUtil.sol";
import {AaveStrategy} from "../../contracts/strategies/aave/AaveStrategy.sol";
import {InitializableAbstractStrategy} from "../../contracts/strategies/InitializableAbstractStrategy.sol";
import "forge-std/console.sol";
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
        aaveStrategy.initialize(
            AAVE_POOL_PROVIDER,
            VAULT_ADDRESS
        );
    }

    function _deposit() internal {

        aaveStrategy.setPTokenAddress(
                ASSET, 
                P_TOKEN, 0
        );
        changePrank(VAULT_ADDRESS);
            deal(address(ASSET), VAULT_ADDRESS, 1 ether);
            IERC20(ASSET).approve(address(aaveStrategy), 1000);
            aaveStrategy.deposit(ASSET, 1);
        changePrank(USDS_OWNER);  
    }
}


contract InitializeTests is AaveStrategyTest {

    function test_empty_address() public useKnownActor(USDS_OWNER) {
        vm.expectRevert("Invalid address");

        aaveStrategy.initialize(
            address(0), 
            VAULT_ADDRESS
        );

        vm.expectRevert("Invalid address");

        aaveStrategy.initialize(
            AAVE_POOL_PROVIDER,
            address(0)
        );

    } 

    function test_revertsWhen_unAuthorized() public useActor(0) {
        aaveStrategy.initialize(
            AAVE_POOL_PROVIDER,
            VAULT_ADDRESS
        );
    }

    function test_success() public {
        _initializeStrategy();
        assert(true);
    }


} 

contract PtokenTest is AaveStrategyTest {
    event PTokenAdded(address indexed asset, address pToken);
    event IntLiqThresholdChanged(
        address indexed asset,
        uint256 intLiqThreshold
    );

    function setUp() public override { 
        super.setUp();
        vm.startPrank(USDS_OWNER);
            _initializeStrategy();
        vm.stopPrank();
    }

    function test_revertsWhen_unAuthorized_SetPtoken() public useActor(0){
        vm.expectRevert("Ownable: caller is not the owner");
        aaveStrategy.setPTokenAddress(
            ASSET, 
            P_TOKEN, 0
        );
    }

    function test_SetPtoken()  public useKnownActor(USDS_OWNER) {

        vm.expectEmit(true, false, false, false);

        emit PTokenAdded(address(ASSET), address(P_TOKEN));

        aaveStrategy.setPTokenAddress(
            ASSET, 
            P_TOKEN, 0
        );
    }

    function test_revertsWhen_unAuthorized_updateIntLiqThreshold() public useActor(0) {
        vm.expectRevert("Ownable: caller is not the owner");

        aaveStrategy.updateIntLiqThreshold(P_TOKEN, 2);
    }

    function test_revert_Collateral_not_supported_updateIntLiqThreshold() public useKnownActor(USDS_OWNER) {
        vm.expectRevert("Collateral not supported");

        aaveStrategy.updateIntLiqThreshold(P_TOKEN, 2);
    }

    function test_updateIntLiqThreshold() public useKnownActor(USDS_OWNER) {      
        aaveStrategy.setPTokenAddress(
            ASSET, 
            P_TOKEN, 0
        );

        vm.expectEmit(true, false, false, false);

        emit IntLiqThresholdChanged(address(ASSET), uint256(2));
        aaveStrategy.updateIntLiqThreshold(ASSET, 2);
    }

    function test_RemovePToken_failures() public {
        vm.expectRevert("Ownable: caller is not the owner");
        aaveStrategy.removePToken(0);

        vm.startPrank(USDS_OWNER);
            vm.expectRevert("Invalid index");
            aaveStrategy.removePToken(5);

            _deposit();

            vm.expectRevert("Collateral allocted");
            aaveStrategy.removePToken(0);

        vm.stopPrank();
    }

    function test_RemovePToken() public  useKnownActor(USDS_OWNER){
        aaveStrategy.setPTokenAddress(
            ASSET, 
            P_TOKEN, 0
        );
        aaveStrategy.removePToken(0);
        (uint256 a, uint256 b) = aaveStrategy.assetInfo(ASSET);
        assert(a == 0);
        assert(b == 0);
    }
}

contract DepositTest is AaveStrategyTest {

    function setUp() public override { 
        super.setUp();
        vm.startPrank(USDS_OWNER);     
            _initializeStrategy();
            aaveStrategy.setPTokenAddress(
                ASSET, 
                P_TOKEN, 0
            );
        vm.stopPrank();
    }

    function test_deposit_failures() public useKnownActor(VAULT_ADDRESS) {
        vm.expectRevert("Collateral not supported");
        aaveStrategy.deposit(DUMMY_ADDRESS, 1);

        vm.expectRevert("Must deposit something");
        aaveStrategy.deposit(ASSET, 0);
    }

    function test_deposit()  useKnownActor(VAULT_ADDRESS) public  {
        deal(address(ASSET), VAULT_ADDRESS, 1 ether);
        IERC20(ASSET).approve(address(aaveStrategy), 1000);
        aaveStrategy.deposit(ASSET, 1);
    }

}


contract collect_interestTest is AaveStrategyTest {
    address public yieldReceiver;

    function setUp() public override {
        super.setUp();
        yieldReceiver = actors[0];
        vm.startPrank(USDS_OWNER);
            _initializeStrategy();
            aaveStrategy.setPTokenAddress(
                ASSET, 
                P_TOKEN, 0
            );
       
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

    function test_collect_interest()  useKnownActor(VAULT_ADDRESS) public  {

        vm.warp(block.timestamp + 10 days);
        vm.roll(block.number + 1000);

        uint256 initial_bal = IERC20(ASSET).balanceOf(yieldReceiver);

        console.log(initial_bal);

        vm.mockCall(
            VAULT_ADDRESS,
            abi.encodeWithSignature("yieldReceiver()"),
            abi.encode(yieldReceiver)
        );

        uint256 interestEarned =  aaveStrategy.checkInterestEarned(ASSET);

   
        (uint256 a, uint256 b) = aaveStrategy.assetInfo(ASSET);
 
        (address[] memory interestAssets, uint256[] memory interestAmts) = aaveStrategy.collectInterest(ASSET);

        uint256 current_bal = IERC20(ASSET).balanceOf(yieldReceiver);

        assert(current_bal  == (initial_bal + interestAmts[0]));
    }

}


contract WithdrawTest is AaveStrategyTest {
    address public yieldReceiver;

    function setUp() public override {
        super.setUp();
        yieldReceiver = actors[0];
        vm.startPrank(USDS_OWNER);
            _initializeStrategy();
            aaveStrategy.setPTokenAddress(
                ASSET, 
                P_TOKEN, 0
            );
       
        changePrank(VAULT_ADDRESS);
            deal(address(ASSET), VAULT_ADDRESS, 1 ether);
            IERC20(ASSET).approve(address(aaveStrategy), 1000);
            aaveStrategy.deposit(ASSET, 1000);
        vm.stopPrank(); 
    }

    function test_withdraw_faliures() useKnownActor(VAULT_ADDRESS) public {
        vm.expectRevert("Invalid address");
        aaveStrategy.withdraw(address(0), ASSET, 1);

        vm.expectRevert("Invalid amount");
        aaveStrategy.withdraw(VAULT_ADDRESS, ASSET, 0);

        changePrank(address(0));
        vm.expectRevert("Caller is not the Vault");
        aaveStrategy.withdraw(VAULT_ADDRESS, ASSET, 1);
    }

    function test_withdraw()  useKnownActor(VAULT_ADDRESS) public  {

        vm.warp(block.timestamp + 10 days);
        vm.roll(block.number + 1000);
 
        aaveStrategy.withdraw(VAULT_ADDRESS, ASSET, 1);
    }

    function test_withdrawToVault()  useKnownActor(USDS_OWNER) public  {
        vm.warp(block.timestamp + 10 days);
        vm.roll(block.number + 1000);
 
        aaveStrategy.withdrawToVault(ASSET, 1);
    }    

}

contract MiscellaneousTest is AaveStrategyTest {

    function setUp() public override {
        super.setUp();
        vm.startPrank(USDS_OWNER);
            _initializeStrategy();
            aaveStrategy.setPTokenAddress(
                ASSET, 
                P_TOKEN, 0
            );
    }

    function test_checkRewardEarned() public {
       uint256 reward = aaveStrategy.checkRewardEarned();
       assert(reward == 0);
    }

    function test_checkBalance() public {
        (uint256 balance,  uint256 intLiqThreshold) = aaveStrategy.assetInfo(ASSET);
        uint256 bal = aaveStrategy.checkBalance(ASSET);
        assert(bal == balance);
    }

    function test_checkAvailableBalance() public {

        uint256 bal_before = aaveStrategy.checkAvailableBalance(ASSET);

        assert(bal_before == 0);

        vm.startPrank(VAULT_ADDRESS);
            deal(address(ASSET), VAULT_ADDRESS, 1 ether);
            IERC20(ASSET).approve(address(aaveStrategy), 1000);
            aaveStrategy.deposit(ASSET, 1000);
        vm.stopPrank(); 

        uint256 bal_after = aaveStrategy.checkAvailableBalance(ASSET);
        assert(bal_after > 0);
    }

    function test_collectReward() public {
        vm.expectRevert("No reward incentive for AAVE");
        aaveStrategy.collectReward();
    }

    function test_checkInterestEarned_empty() public {
        uint256 interest =  aaveStrategy.checkInterestEarned(ASSET);
        assert(interest == 0);
    }
}