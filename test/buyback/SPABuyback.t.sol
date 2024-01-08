// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {BaseTest} from "../utils/BaseTest.sol";
import {SPABuyback, Helpers} from "../../contracts/buyback/SPABuyback.sol";
import {UpgradeUtil} from "../utils/UpgradeUtil.sol";
import {MasterPriceOracle} from "../../contracts/oracle/MasterPriceOracle.sol";
import {IOracle} from "../../contracts/interfaces/IOracle.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IveSPARewarder} from "../../contracts/interfaces/IveSPARewarder.sol";
import {IUSDs} from "../../contracts/interfaces/IUSDs.sol";

contract SPABuybackTestSetup is BaseTest {
    SPABuyback internal spaBuyback;
    SPABuyback internal spaBuybackImpl;
    UpgradeUtil internal upgradeUtil;
    IOracle.PriceData internal usdsData;
    IOracle.PriceData internal spaData;

    address internal user;
    address internal constant VESPA_REWARDER = 0x5eD5C72D24fF0931E5a38C2969160dFE259E7C05;
    uint256 internal constant MAX_PERCENTAGE = 10000;
    uint256 internal rewardPercentage;
    uint256 internal minUSDsOut;
    uint256 internal spaIn;

    modifier mockOracle() {
        vm.mockCall(address(ORACLE), abi.encodeWithSignature("getPrice(address)", USDS), abi.encode(99526323, 1e8));
        vm.mockCall(address(ORACLE), abi.encodeWithSignature("getPrice(address)", SPA), abi.encode(472939, 1e8));
        _;
        vm.clearMockedCalls();
    }

    function setUp() public virtual override {
        super.setUp();
        address proxy;
        setArbitrumFork();
        user = actors[0];
        rewardPercentage = 5000; // 50%
        vm.startPrank(USDS_OWNER);
        spaBuybackImpl = new SPABuyback();
        upgradeUtil = new UpgradeUtil();
        proxy = upgradeUtil.deployErc1967Proxy(address(spaBuybackImpl));
        spaBuyback = SPABuyback(proxy);

        spaBuyback.initialize(VESPA_REWARDER, rewardPercentage);
        spaBuyback.updateOracle(ORACLE);
        vm.stopPrank();
    }

    // Internal helper functions
    function _calculateUSDsForSpaIn(uint256 _spaIn) internal returns (uint256) {
        usdsData = IOracle(ORACLE).getPrice(USDS);
        spaData = IOracle(ORACLE).getPrice(SPA);
        return ((_spaIn * spaData.price * usdsData.precision) / (usdsData.price * spaData.precision));
    }

    function _calculateSpaReqdForUSDs(uint256 _usdsAmount) internal returns (uint256) {
        usdsData = IOracle(ORACLE).getPrice(USDS);
        spaData = IOracle(ORACLE).getPrice(SPA);
        return (_usdsAmount * usdsData.price * spaData.precision) / (spaData.price * usdsData.precision);
    }

    function _getWeek(uint256 _n) internal view returns (uint256) {
        uint256 week = 7 days;
        uint256 thisWeek = (block.timestamp / week) * week;
        return thisWeek + (_n * week);
    }
}

contract Test_Init is SPABuybackTestSetup {
    SPABuyback private _spaBuybackImpl;
    SPABuyback private _spaBuyback;

    function test_initialize() public {
        address _proxy;
        vm.startPrank(USDS_OWNER);
        _spaBuybackImpl = new SPABuyback();
        _proxy = upgradeUtil.deployErc1967Proxy(address(_spaBuybackImpl));
        _spaBuyback = SPABuyback(_proxy);

        _spaBuyback.initialize(VESPA_REWARDER, 5000);
        vm.stopPrank();
    }

    function test_revertsWhen_alreadyInitialized() public useKnownActor(USDS_OWNER) {
        vm.expectRevert("Initializable: contract is already initialized");
        spaBuyback.initialize(VESPA_REWARDER, rewardPercentage);
    }

    function test_revertsWhen_initializingImplementation() public useKnownActor(USDS_OWNER) {
        vm.expectRevert("Initializable: contract is already initialized");
        spaBuybackImpl.initialize(VESPA_REWARDER, rewardPercentage);
    }

    function test_initParams() public {
        assertEq(spaBuyback.veSpaRewarder(), VESPA_REWARDER);
        assertEq(spaBuyback.rewardPercentage(), rewardPercentage);
    }
}

contract Test_GetUSDsOutForSpa is SPABuybackTestSetup {
    uint256 private usdsAmount;

    function setUp() public override {
        super.setUp();
        usdsAmount = 1e20;
        spaIn = 1e23;
    }

    function test_GetUsdsOutForSpa() public mockOracle {
        uint256 calculateUSDsOut = _calculateUSDsForSpaIn(spaIn);
        uint256 usdsOutByContract = spaBuyback.getUsdsOutForSpa(spaIn);
        assertEq(calculateUSDsOut, usdsOutByContract);
    }

    function test_revertsWhen_invalidAmount() public mockOracle {
        vm.expectRevert(abi.encodeWithSelector(Helpers.InvalidAmount.selector));
        spaBuyback.getUsdsOutForSpa(0);
    }
}

contract Test_GetSPAReqdForUSDs is SPABuybackTestSetup {
    uint256 private usdsAmount;

    function setUp() public override {
        super.setUp();
        usdsAmount = 1e20;
        spaIn = 1e23;
    }

    function test_getSPAReqdForUSDs() public mockOracle {
        uint256 calculatedSpaReqd = _calculateSpaReqdForUSDs(usdsAmount);
        uint256 spaReqdByContract = spaBuyback.getSPAReqdForUSDs(usdsAmount);
        assertEq(calculatedSpaReqd, spaReqdByContract);
    }

    function test_revertsWhen_invalidAmount() public mockOracle {
        vm.expectRevert(abi.encodeWithSelector(Helpers.InvalidAmount.selector));
        spaBuyback.getSPAReqdForUSDs(0);
    }
}

contract Test_UpdateRewardPercentage is SPABuybackTestSetup {
    event RewardPercentageUpdated(uint256 newRewardPercentage);

    function test_revertsWhen_callerNotOwner() external useActor(0) {
        vm.expectRevert("Ownable: caller is not the owner");
        spaBuyback.updateRewardPercentage(9000);
    }

    // function updateRewardPercentage
    function test_revertsWhen_percentageIsZero() external useKnownActor(USDS_OWNER) {
        vm.expectRevert(abi.encodeWithSelector(Helpers.InvalidAmount.selector));
        spaBuyback.updateRewardPercentage(0);
    }

    function test_revertsWhen_percentageMoreThanMax() external useKnownActor(USDS_OWNER) {
        vm.expectRevert(abi.encodeWithSelector(Helpers.GTMaxPercentage.selector, 10001));
        spaBuyback.updateRewardPercentage(10001);
    }

    function test_updateRewardPercentage() external useKnownActor(USDS_OWNER) {
        uint256 newRewardPercentage = 8000;
        vm.expectEmit(true, true, true, true, address(spaBuyback));
        emit RewardPercentageUpdated(newRewardPercentage);
        spaBuyback.updateRewardPercentage(8000);
        assertEq(spaBuyback.rewardPercentage(), newRewardPercentage);
    }
}

contract Test_UpdateOracle is SPABuybackTestSetup {
    event OracleUpdated(address newOracle);

    function test_revertsWhen_callerNotOwner() external useActor(0) {
        vm.expectRevert("Ownable: caller is not the owner");
        spaBuyback.updateOracle(actors[0]);
    }

    function test_revertsWhen_invalidOracleAddress() external useKnownActor(USDS_OWNER) {
        vm.expectRevert(abi.encodeWithSelector(Helpers.InvalidAddress.selector));
        spaBuyback.updateOracle(address(0));
    }

    function test_updateOracle() external useKnownActor(USDS_OWNER) {
        address newOracle = actors[1];
        vm.expectEmit(true, true, true, true, address(spaBuyback));
        emit OracleUpdated(newOracle);
        spaBuyback.updateOracle(newOracle);
        assertEq(spaBuyback.oracle(), newOracle);
    }
}

contract Test_UpdateRewarder is SPABuybackTestSetup {
    event VeSpaRewarderUpdated(address newVeSpaRewarder);

    function test_revertsWhen_callerNotOwner() external useActor(0) {
        vm.expectRevert("Ownable: caller is not the owner");
        spaBuyback.updateVeSpaRewarder(actors[0]);
    }

    function test_revertsWhen_invalidRewarderAddress() external useKnownActor(USDS_OWNER) {
        vm.expectRevert(abi.encodeWithSelector(Helpers.InvalidAddress.selector));
        spaBuyback.updateVeSpaRewarder(address(0));
    }

    function test_updateVeSpaRewarder() external useKnownActor(USDS_OWNER) {
        address newRewarder = actors[1];
        vm.expectEmit(true, true, true, true, address(spaBuyback));
        emit VeSpaRewarderUpdated(newRewarder);
        spaBuyback.updateVeSpaRewarder(newRewarder);
        assertEq(spaBuyback.veSpaRewarder(), newRewarder);
    }
}

contract Test_Withdraw is SPABuybackTestSetup {
    address private token;
    uint256 private amount;

    event Withdrawn(address indexed token, address indexed receiver, uint256 amount);

    function setUp() public override {
        super.setUp();
        token = USDS;
        amount = 1e20;

        vm.prank(VAULT);
        IUSDs(USDS).mint(address(spaBuyback), amount);
    }

    function test_revertsWhen_CallerNotOwner() public useActor(0) {
        vm.expectRevert("Ownable: caller is not the owner");
        spaBuyback.withdraw(token, user, amount);
    }

    function test_revertsWhen_withdrawSPA() public useKnownActor(USDS_OWNER) {
        token = SPA;
        vm.expectRevert(abi.encodeWithSelector(SPABuyback.CannotWithdrawSPA.selector));
        spaBuyback.withdraw(token, user, amount);
    }

    function test_revertsWhen_withdrawMoreThanBalance() public useKnownActor(USDS_OWNER) {
        amount = IERC20(USDS).balanceOf(address(spaBuyback));
        amount = amount + 1e20;
        vm.expectRevert("Transfer greater than balance");
        spaBuyback.withdraw(token, user, amount);
    }

    function test_withdraw() public useKnownActor(USDS_OWNER) {
        uint256 balBefore = IERC20(USDS).balanceOf(user);
        vm.expectEmit(true, true, true, true, address(spaBuyback));
        emit Withdrawn(token, user, amount);
        spaBuyback.withdraw(token, user, amount);
        uint256 balAfter = IERC20(USDS).balanceOf(user);
        assertEq(balAfter - balBefore, amount);
    }
}

contract Test_BuyUSDs is SPABuybackTestSetup {
    struct BalComparison {
        uint256 balBefore;
        uint256 balAfter;
    }

    BalComparison private spaTotalSupply;
    BalComparison private rewarderSPABal;

    event BoughtBack(
        address indexed receiverOfUSDs,
        address indexed senderOfSPA,
        uint256 spaPrice,
        uint256 spaAmount,
        uint256 usdsAmount
    );
    event SPARewarded(uint256 spaAmount);
    event SPABurned(uint256 spaAmount);
    event Transfer(address from, address to, uint256 amount);

    function setUp() public override {
        super.setUp();
        spaIn = 1e23;
        minUSDsOut = 1;
    }

    function test_revertsWhen_SpaAmountTooLow() public mockOracle {
        spaIn = 100;
        vm.expectRevert(abi.encodeWithSelector(Helpers.CustomError.selector, "SPA Amount too low"));
        spaBuyback.buyUSDs(spaIn, minUSDsOut);
    }

    function test_revertsWhen_SlippageMoreThanExpected() public mockOracle {
        minUSDsOut = spaBuyback.getUsdsOutForSpa(spaIn) + 1e20;
        vm.expectRevert(abi.encodeWithSelector(Helpers.MinSlippageError.selector, minUSDsOut - 1e20, minUSDsOut));
        spaBuyback.buyUSDs(spaIn, minUSDsOut);
    }

    function test_revertsWhen_InsufficientUSDsBalance() public mockOracle {
        minUSDsOut = spaBuyback.getUsdsOutForSpa(spaIn);
        vm.expectRevert(abi.encodeWithSelector(SPABuyback.InsufficientUSDsBalance.selector, minUSDsOut, 0));
        spaBuyback.buyUSDs(spaIn, minUSDsOut);
    }

    function test_buyUSDs() public mockOracle {
        minUSDsOut = _calculateUSDsForSpaIn(spaIn);
        vm.prank(VAULT);
        IUSDs(USDS).mint(address(spaBuyback), minUSDsOut + 1e19);
        spaTotalSupply.balBefore = IERC20(SPA).totalSupply();
        rewarderSPABal.balBefore = IERC20(SPA).balanceOf(VESPA_REWARDER);
        deal(SPA, user, spaIn);
        vm.startPrank(user);
        IERC20(SPA).approve(address(spaBuyback), spaIn);
        spaData = IOracle(ORACLE).getPrice(SPA);

        // Calculate SPA to be distributed and burnt
        uint256 spaRewarded = spaIn * spaBuyback.rewardPercentage() / Helpers.MAX_PERCENTAGE;
        uint256 spaBurnt = spaIn - spaRewarded;

        uint256 initialRewards = IveSPARewarder(VESPA_REWARDER).rewardsPerWeek(_getWeek(1), SPA);
        vm.expectEmit(true, true, false, true, address(spaBuyback));
        emit BoughtBack(user, user, spaData.price, spaIn, minUSDsOut);
        vm.expectEmit(true, true, true, true, address(spaBuyback));
        emit SPARewarded(spaRewarded);
        vm.expectEmit(true, true, true, true, address(spaBuyback));
        emit SPABurned(spaBurnt);
        spaBuyback.buyUSDs(spaIn, minUSDsOut);
        vm.stopPrank();
        uint256 rewardsAfter = IveSPARewarder(VESPA_REWARDER).rewardsPerWeek(_getWeek(1), SPA);
        spaTotalSupply.balAfter = IERC20(SPA).totalSupply();
        rewarderSPABal.balAfter = IERC20(SPA).balanceOf(VESPA_REWARDER);
        assertEq(rewarderSPABal.balAfter - rewarderSPABal.balBefore, spaRewarded);
        assertEq(initialRewards + (spaRewarded), rewardsAfter);
        assertEq(spaTotalSupply.balBefore - spaTotalSupply.balAfter, spaBurnt);
    }

    // Testing with fuzzing
    function test_buyUSDs(uint256 spaIn, uint256 spaPrice, uint256 usdsPrice) public {
        usdsPrice = bound(usdsPrice, 7e17, 13e17);
        spaPrice = bound(spaPrice, 1e15, 1e20);
        spaIn = bound(spaIn, 1e18, 1e27);
        uint256 swapValue = (spaIn * spaPrice) / 1e18;
        vm.mockCall(address(ORACLE), abi.encodeWithSignature("getPrice(address)", USDS), abi.encode(usdsPrice, 1e18));
        vm.mockCall(address(ORACLE), abi.encodeWithSignature("getPrice(address)", SPA), abi.encode(spaPrice, 1e18));
        minUSDsOut = _calculateUSDsForSpaIn(spaIn);
        if (swapValue > 1e18 && minUSDsOut > 1e18) {
            vm.prank(VAULT);
            IUSDs(USDS).mint(address(spaBuyback), minUSDsOut);
            deal(SPA, user, spaIn);
            vm.startPrank(user);
            IERC20(SPA).approve(address(spaBuyback), spaIn);
            uint256 initialRewards = IveSPARewarder(VESPA_REWARDER).rewardsPerWeek(_getWeek(1), SPA);
            vm.expectEmit(true, true, true, true, address(spaBuyback));
            emit BoughtBack(user, user, spaData.price, spaIn, minUSDsOut);
            vm.expectEmit(true, true, true, false, address(spaBuyback));
            emit SPARewarded(spaIn / 2);
            vm.expectEmit(true, true, true, false, address(spaBuyback));
            emit SPABurned(spaIn / 2);
            spaBuyback.buyUSDs(spaIn, minUSDsOut);
            vm.stopPrank();
            uint256 rewardsAfter = IveSPARewarder(VESPA_REWARDER).rewardsPerWeek(_getWeek(1), SPA);
            assertEq(initialRewards + (spaIn / 2), rewardsAfter);
            vm.clearMockedCalls();
            emit log_named_uint("SPA spent", spaIn);
        }
    }
}
