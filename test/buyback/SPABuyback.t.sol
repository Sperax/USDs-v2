// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {BaseTest} from "../utils/BaseTest.sol";
import {SPABuyback, Helpers} from "../../contracts/buyback/SPABuyback.sol";
import {UpgradeUtil} from "../utils/UpgradeUtil.sol";
import {MasterPriceOracle} from "../../contracts/oracle/MasterPriceOracle.sol";
import {IOracle} from "../../contracts/interfaces/IOracle.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IUSDs} from "../../contracts/interfaces/IUSDs.sol";

contract SPABuybackTestSetup is BaseTest {
    SPABuyback internal spaBuyback;
    SPABuyback internal spaBuybackImpl;
    UpgradeUtil internal upgradeUtil;
    IOracle.PriceData internal usdsData;
    IOracle.PriceData internal spaData;

    address internal user;
    address internal constant VESPA_REWARDER = 0x2CaB3abfC1670D1a452dF502e216a66883cDf079;
    uint256 internal constant MAX_PERCENTAGE = 10000;
    uint256 internal rewardPercentage;
    uint256 internal minUSDsOut;
    uint256 internal spaIn;

    modifier mockOracle() {
        vm.mockCall(
            address(ORACLE), abi.encodeWithSignature("getPrice(address)", USDS), abi.encode(995263234350000000, 1e18)
        );
        vm.mockCall(
            address(ORACLE), abi.encodeWithSignature("getPrice(address)", SPA), abi.encode(4729390000000000, 1e18)
        );
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
}

contract TestInit is SPABuybackTestSetup {
    SPABuyback private _spaBuybackImpl;
    SPABuyback private _spaBuyback;

    function testInitialize() public {
        address _proxy;
        vm.startPrank(USDS_OWNER);
        _spaBuybackImpl = new SPABuyback();
        _proxy = upgradeUtil.deployErc1967Proxy(address(_spaBuybackImpl));
        _spaBuyback = SPABuyback(_proxy);

        _spaBuyback.initialize(VESPA_REWARDER, 5000);
        vm.stopPrank();
    }

    function testCannotInitializeTwice() public useKnownActor(USDS_OWNER) {
        vm.expectRevert("Initializable: contract is already initialized");
        spaBuyback.initialize(VESPA_REWARDER, rewardPercentage);
    }

    function testCannotInitializeImplementation() public useKnownActor(USDS_OWNER) {
        vm.expectRevert("Initializable: contract is already initialized");
        spaBuybackImpl.initialize(VESPA_REWARDER, rewardPercentage);
    }

    function testInit() public {
        assertEq(spaBuyback.veSpaRewarder(), VESPA_REWARDER);
        assertEq(spaBuyback.rewardPercentage(), rewardPercentage);
    }
}

contract TestGetters is SPABuybackTestSetup {
    uint256 private usdsAmount;
    uint256 private spaReqd;

    function setUp() public override {
        super.setUp();
        usdsAmount = 100e18;
        spaIn = 100000e18;
    }

    function testGetSpaReqdForUSDs() public mockOracle {
        uint256 calculatedSpaReqd = _calculateSpaReqdForUSDs(usdsAmount);
        uint256 spaReqdByContract = spaBuyback.getSPAReqdForUSDs(usdsAmount);
        assertEq(calculatedSpaReqd, spaReqdByContract);
    }

    function testGetUsdsOutForSpa() public mockOracle {
        uint256 calculateUSDsOut = _calculateUSDsForSpaIn(spaIn);
        uint256 usdsOutByContract = spaBuyback.getUsdsOutForSpa(spaIn);
        assertEq(calculateUSDsOut, usdsOutByContract);
    }

    function testCannotIfInvalidAmount() public mockOracle {
        vm.expectRevert(abi.encodeWithSelector(Helpers.InvalidAmount.selector));
        spaBuyback.getUsdsOutForSpa(0);
    }
}

contract TestSetters is SPABuybackTestSetup {
    event RewardPercentageUpdated(uint256 newRewardPercentage);
    event VeSpaRewarderUpdated(address newVeSpaRewarder);
    event OracleUpdated(address newOracle);

    function testCannotIfCallerNotOwner() external useActor(0) {
        vm.expectRevert("Ownable: caller is not the owner");
        spaBuyback.updateRewardPercentage(9000);
        vm.expectRevert("Ownable: caller is not the owner");
        spaBuyback.updateVeSpaRewarder(actors[0]);
        vm.expectRevert("Ownable: caller is not the owner");
        spaBuyback.updateOracle(actors[0]);
    }

    // function updateRewardPercentage
    function testCannotIfPercentageIsZero() external useKnownActor(USDS_OWNER) {
        vm.expectRevert(abi.encodeWithSelector(Helpers.InvalidAmount.selector));
        spaBuyback.updateRewardPercentage(0);
    }

    function testCannotIfPercentageMoreThanMax() external useKnownActor(USDS_OWNER) {
        vm.expectRevert(abi.encodeWithSelector(Helpers.GTMaxPercentage.selector, 10001));
        spaBuyback.updateRewardPercentage(10001);
    }

    function testUpdateRewardPercentage() external useKnownActor(USDS_OWNER) {
        uint256 newRewardPercentage = 8000;
        vm.expectEmit(true, true, true, true, address(spaBuyback));
        emit RewardPercentageUpdated(newRewardPercentage);
        spaBuyback.updateRewardPercentage(8000);
        assertEq(spaBuyback.rewardPercentage(), newRewardPercentage);
    }

    // function updateVeSpaRewarder
    function testCannotIfInvalidAddress() external useKnownActor(USDS_OWNER) {
        vm.expectRevert(abi.encodeWithSelector(Helpers.InvalidAddress.selector));
        spaBuyback.updateVeSpaRewarder(address(0));
    }

    function testUpdateVeSpaRewarder() external useKnownActor(USDS_OWNER) {
        address newRewarder = actors[1];
        vm.expectEmit(true, true, true, true, address(spaBuyback));
        emit VeSpaRewarderUpdated(newRewarder);
        spaBuyback.updateVeSpaRewarder(newRewarder);
        assertEq(spaBuyback.veSpaRewarder(), newRewarder);
    }

    // function updateOracle
    function testCannotIfInvalidAddressOracle() external useKnownActor(USDS_OWNER) {
        vm.expectRevert(abi.encodeWithSelector(Helpers.InvalidAddress.selector));
        spaBuyback.updateOracle(address(0));
    }

    function testUpdateOracle() external useKnownActor(USDS_OWNER) {
        address newOracle = actors[1];
        vm.expectEmit(true, true, true, true, address(spaBuyback));
        emit OracleUpdated(newOracle);
        spaBuyback.updateOracle(newOracle);
        assertEq(spaBuyback.oracle(), newOracle);
    }
}

contract TestWithdraw is SPABuybackTestSetup {
    address private token;
    uint256 private amount;

    event Withdrawn(address indexed token, address indexed receiver, uint256 amount);

    function setUp() public override {
        super.setUp();
        token = USDS;
        amount = 100e18;

        vm.prank(VAULT);
        IUSDs(USDS).mint(address(spaBuyback), amount);
    }

    function testCannotIfCallerNotOwner() public useActor(0) {
        vm.expectRevert("Ownable: caller is not the owner");
        spaBuyback.withdraw(token, user, amount);
    }

    function testCannotWithdrawSPA() public useKnownActor(USDS_OWNER) {
        token = SPA;
        vm.expectRevert(abi.encodeWithSelector(SPABuyback.CannotWithdrawSPA.selector));
        spaBuyback.withdraw(token, user, amount);
    }

    function testCannotWithdrawMoreThanBalance() public useKnownActor(USDS_OWNER) {
        amount = IERC20(USDS).balanceOf(address(spaBuyback));
        amount = amount + 100e18;
        vm.expectRevert("Transfer greater than balance");
        spaBuyback.withdraw(token, user, amount);
    }

    function testWithdraw() public useKnownActor(USDS_OWNER) {
        uint256 balBefore = IERC20(USDS).balanceOf(user);
        vm.expectEmit(true, true, true, true, address(spaBuyback));
        emit Withdrawn(token, user, amount);
        spaBuyback.withdraw(token, user, amount);
        uint256 balAfter = IERC20(USDS).balanceOf(user);
        assertEq(balAfter - balBefore, amount);
    }
}

contract TestBuyUSDs is SPABuybackTestSetup {
    struct BalComparison {
        uint256 balBefore;
        uint256 balAfter;
    }

    BalComparison private spaTotalSupply;
    BalComparison private spaBal;

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
        spaIn = 100000e18;
        minUSDsOut = 1;
    }

    function testCannotIfSpaAmountTooLow() public mockOracle {
        spaIn = 100;
        vm.expectRevert(abi.encodeWithSelector(Helpers.CustomError.selector, "SPA Amount too low"));
        spaBuyback.buyUSDs(spaIn, minUSDsOut);
    }

    function testCannotIfSlippageMoreThanExpected() public mockOracle {
        minUSDsOut = spaBuyback.getUsdsOutForSpa(spaIn) + 100e18;
        vm.expectRevert(abi.encodeWithSelector(Helpers.MinSlippageError.selector, minUSDsOut - 100e18, minUSDsOut));
        spaBuyback.buyUSDs(spaIn, minUSDsOut);
    }

    function testCannotIfInsufficientUSDsBalance() public mockOracle {
        minUSDsOut = spaBuyback.getUsdsOutForSpa(spaIn);
        vm.expectRevert(abi.encodeWithSelector(SPABuyback.InsufficientUSDsBalance.selector, minUSDsOut, 0));
        spaBuyback.buyUSDs(spaIn, minUSDsOut);
    }

    function testBuyUSDs() public mockOracle {
        minUSDsOut = _calculateUSDsForSpaIn(spaIn);
        vm.prank(VAULT);
        IUSDs(USDS).mint(address(spaBuyback), minUSDsOut + 10e18);
        spaTotalSupply.balBefore = IERC20(SPA).totalSupply();
        spaBal.balBefore = IERC20(SPA).balanceOf(VESPA_REWARDER);
        deal(SPA, user, spaIn);
        vm.startPrank(user);
        IERC20(SPA).approve(address(spaBuyback), spaIn);
        spaData = IOracle(ORACLE).getPrice(SPA);
        vm.expectEmit(true, true, false, true, address(spaBuyback));
        emit BoughtBack(user, user, spaData.price, spaIn, minUSDsOut);
        vm.expectEmit(true, true, true, true, address(spaBuyback));
        emit SPARewarded(spaIn / 2);
        vm.expectEmit(true, true, true, true, address(spaBuyback));
        emit SPABurned(spaIn / 2);
        spaBuyback.buyUSDs(spaIn, minUSDsOut);
        vm.stopPrank();
        spaTotalSupply.balAfter = IERC20(SPA).totalSupply();
        spaBal.balAfter = IERC20(SPA).balanceOf(VESPA_REWARDER);
        assertEq(spaBal.balAfter - spaBal.balBefore, spaIn / 2);
        assertEq(spaTotalSupply.balBefore - spaTotalSupply.balAfter, spaIn / 2);
    }

    // Testing with fuzzing
    function testBuyUSDs(uint256 spaIn, uint256 spaPrice, uint256 usdsPrice) public {
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
            vm.expectEmit(true, true, true, true, address(spaBuyback));
            emit BoughtBack(user, user, spaData.price, spaIn, minUSDsOut);
            vm.expectEmit(true, true, true, false, address(spaBuyback));
            emit SPARewarded(spaIn / 2);
            vm.expectEmit(true, true, true, false, address(spaBuyback));
            emit SPABurned(spaIn / 2);
            spaBuyback.buyUSDs(spaIn, minUSDsOut);
            vm.stopPrank();
            vm.clearMockedCalls();
            emit log_named_uint("SPA spent", spaIn);
        }
    }
}
