// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {YieldReserve, Helpers} from "../../contracts/buyback/YieldReserve.sol";
import {IVault} from "../../contracts/interfaces/IVault.sol";
import {IOracle} from "../../contracts/interfaces/IOracle.sol";
import {VaultCore} from "../../contracts/vault/VaultCore.sol";
import {IERC20, ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {PreMigrationSetup} from "../utils/DeploymentSetup.sol";

contract YieldReserveTest is PreMigrationSetup {
    YieldReserve internal yieldReserve;
    IVault internal vault;
    uint256 USDCePrecision;
    uint256 SPAPrecision;
    uint256 USDsPrecision;
    uint256 DAIPrecision;
    uint256 internal constant PRICE_PRECISION = 1e8;

    function setUp() public virtual override {
        super.setUp();
        USDsPrecision = 10 ** ERC20(USDS).decimals();
        USDCePrecision = 10 ** ERC20(USDCe).decimals();
        DAIPrecision = 10 ** ERC20(DAI).decimals();
        SPAPrecision = 10 ** ERC20(SPA).decimals();

        vm.startPrank(USDS_OWNER);
        yieldReserve = new YieldReserve(BUYBACK, VAULT, ORACLE, DRIPPER);
        vm.stopPrank();
    }

    function mintUSDs(uint256 amountIn) public {
        deal(address(USDCe), USDS_OWNER, amountIn * USDCePrecision);
        IERC20(USDCe).approve(VAULT, amountIn);
        IVault(VAULT).mintBySpecifyingCollateralAmt(USDCe, amountIn, 0, 0, block.timestamp + 1200);
    }

    function mockPrice(address token, uint256 price, uint256 precision) public {
        vm.mockCall(ORACLE, abi.encodeWithSignature("getPrice(address)", token), abi.encode([price, precision]));
    }

    function getTokenData(address token) public view returns (YieldReserve.TokenData memory) {
        (bool srcAllowed, bool dstAllowed, uint160 conversionFactor) = yieldReserve.tokenData(token);
        return YieldReserve.TokenData(srcAllowed, dstAllowed, conversionFactor);
    }
}

contract ToggleSrcTokenPermissionTest is YieldReserveTest {
    event SrcTokenPermissionUpdated(address indexed token, bool isAllowed);

    function setUp() public override {
        super.setUp();
        mockPrice(SPA, 10, SPAPrecision);
    }

    function test_revertsWhen_callerNotOwner() public useActor(0) {
        vm.expectRevert("Ownable: caller is not the owner");
        yieldReserve.toggleSrcTokenPermission(SPA, true);
    }

    function test_revertsWhen_AlreadyInDesiredState() public useKnownActor(USDS_OWNER) {
        yieldReserve.toggleSrcTokenPermission(SPA, true);
        vm.expectRevert(abi.encodeWithSelector(YieldReserve.AlreadyInDesiredState.selector));
        yieldReserve.toggleSrcTokenPermission(SPA, true);
    }

    function test_ToggleSrcTokenFalse() public useKnownActor(USDS_OWNER) {
        yieldReserve.toggleSrcTokenPermission(SPA, true);
        vm.expectEmit(true, true, true, true, address(yieldReserve));
        emit SrcTokenPermissionUpdated(SPA, false);
        yieldReserve.toggleSrcTokenPermission(SPA, false);
        YieldReserve.TokenData memory tokenData = getTokenData(SPA);
        assertFalse(tokenData.srcAllowed);
        assertEq(tokenData.conversionFactor, 1);
    }

    function test_revertsWhen_priceFeeDoesNotExist() public useKnownActor(USDS_OWNER) {
        address randomTokenAddress = address(0x9);

        vm.expectRevert(abi.encodeWithSelector(YieldReserve.TokenPriceFeedMissing.selector));
        yieldReserve.toggleSrcTokenPermission(randomTokenAddress, true);
    }

    function test_toggleSrcTokenPermission() public useKnownActor(USDS_OWNER) {
        assertTrue(IOracle(ORACLE).priceFeedExists(SPA));
        vm.expectEmit(true, true, true, true, address(yieldReserve));
        emit SrcTokenPermissionUpdated(SPA, true);
        yieldReserve.toggleSrcTokenPermission(SPA, true);
        YieldReserve.TokenData memory tokenData = getTokenData(SPA);
        assertTrue(tokenData.srcAllowed);
        assertEq(tokenData.conversionFactor, 1);
    }
}

contract ToggleDstTokenPermissionTest is YieldReserveTest {
    event DstTokenPermissionUpdated(address indexed token, bool isAllowed);

    function setUp() public override {
        super.setUp();
        mockPrice(SPA, 10, SPAPrecision);
    }

    function test_revertsWhen_callerNotOwner() public useActor(0) {
        vm.expectRevert("Ownable: caller is not the owner");
        yieldReserve.toggleDstTokenPermission(SPA, true);
    }

    function test_revertsWhen_AlreadyInDesiredState() public useKnownActor(USDS_OWNER) {
        yieldReserve.toggleDstTokenPermission(SPA, true);
        vm.expectRevert(abi.encodeWithSelector(YieldReserve.AlreadyInDesiredState.selector));
        yieldReserve.toggleDstTokenPermission(SPA, true);
    }

    function test_ToggleDstTokenFalse() public useKnownActor(USDS_OWNER) {
        yieldReserve.toggleDstTokenPermission(SPA, true);
        vm.expectEmit(true, true, true, true, address(yieldReserve));
        emit DstTokenPermissionUpdated(SPA, false);
        yieldReserve.toggleDstTokenPermission(SPA, false);
        YieldReserve.TokenData memory tokenData = getTokenData(SPA);
        assertFalse(tokenData.dstAllowed);
        assertEq(tokenData.conversionFactor, 1);
    }

    function test_revertsWhen_priceFeeDoesNotExist() public useKnownActor(USDS_OWNER) {
        address randomTokenAddress = address(0x9);

        vm.expectRevert(abi.encodeWithSelector(YieldReserve.TokenPriceFeedMissing.selector));
        yieldReserve.toggleDstTokenPermission(randomTokenAddress, true);
    }

    function test_toggleDstTokenPermission() public useKnownActor(USDS_OWNER) {
        assertTrue(IOracle(ORACLE).priceFeedExists(SPA));
        vm.expectEmit(true, true, true, true, address(yieldReserve));
        emit DstTokenPermissionUpdated(SPA, true);
        yieldReserve.toggleDstTokenPermission(SPA, true);
        YieldReserve.TokenData memory tokenData = getTokenData(SPA);
        assertTrue(tokenData.dstAllowed);
        assertEq(tokenData.conversionFactor, 1);
    }
}

contract WithdrawTest is YieldReserveTest {
    address token;
    address receiver;
    uint256 amount;

    function setUp() public override {
        super.setUp();
        token = SPA;
        receiver = USDS_OWNER;
        amount = 1e21;
    }

    function test_revertsWhen_callerNotOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        yieldReserve.withdraw(token, receiver, amount);
    }

    function test_revertsWhen_invalidToken() public useKnownActor(USDS_OWNER) {
        vm.expectRevert("Address: call to non-contract");
        yieldReserve.withdraw(address(0), receiver, amount);
    }

    function test_revertsWhen_invalidReceiver() public useKnownActor(USDS_OWNER) {
        vm.expectRevert("ERC20: transfer to the zero address");
        yieldReserve.withdraw(token, address(0), amount);
    }

    function test_revertsWhen_invalidAmount() public useKnownActor(USDS_OWNER) {
        vm.expectRevert(abi.encodeWithSelector(Helpers.InvalidAmount.selector));
        yieldReserve.withdraw(token, receiver, 0);
    }

    function test_withdraw() public useKnownActor(USDS_OWNER) {
        deal(address(SPA), address(yieldReserve), amount);

        uint256 initialBal = IERC20(SPA).balanceOf(USDS_OWNER);

        yieldReserve.withdraw(SPA, USDS_OWNER, amount);

        uint256 newBal = IERC20(SPA).balanceOf(USDS_OWNER);

        assertEq(amount + initialBal, newBal);
    }
}

contract UpdateBuybackPercentageTest is YieldReserveTest {
    event BuybackPercentageUpdated(uint256 toBuyback);

    function test_revertsWhen_callerNotOwner() public useActor(0) {
        vm.expectRevert("Ownable: caller is not the owner");
        yieldReserve.updateBuybackPercentage(2000);
    }

    function test_revertsWhen_percentageGTMax() public useKnownActor(USDS_OWNER) {
        uint256 buybackPercentage = 10001;
        vm.expectRevert(abi.encodeWithSelector(Helpers.GTMaxPercentage.selector, buybackPercentage));
        yieldReserve.updateBuybackPercentage(buybackPercentage);
    }

    function test_revertsWhen_percentageIsZero() public useKnownActor(USDS_OWNER) {
        uint256 buybackPercentage = 0;
        vm.expectRevert(abi.encodeWithSelector(Helpers.InvalidAmount.selector));
        yieldReserve.updateBuybackPercentage(buybackPercentage);
    }

    function test_updateBuybackPercentage() public useKnownActor(USDS_OWNER) {
        uint256 buybackPercentage = 2000;
        vm.expectEmit(address(yieldReserve));
        emit BuybackPercentageUpdated(buybackPercentage);
        yieldReserve.updateBuybackPercentage(buybackPercentage);

        assertEq(yieldReserve.buybackPercentage(), buybackPercentage);
    }
}

contract UpdateBuybackAddressTest is YieldReserveTest {
    event BuybackAddressUpdated(address newBuyback);

    function test_revertsWhen_callerNotOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        yieldReserve.updateBuybackAddress(VAULT);
    }

    function test_revertsWhen_InvalidAddress() public useKnownActor(USDS_OWNER) {
        vm.expectRevert(abi.encodeWithSelector(Helpers.InvalidAddress.selector));
        yieldReserve.updateBuybackAddress(address(0));
    }

    function test_updateBuybackAddress() public useKnownActor(USDS_OWNER) {
        vm.expectEmit(address(yieldReserve));
        emit BuybackAddressUpdated(VAULT);
        yieldReserve.updateBuybackAddress(VAULT);
        assertEq(yieldReserve.buyback(), VAULT);
    }
}

contract UpdateOracleAddressTest is YieldReserveTest {
    event OracleUpdated(address newOracle);

    function test_revertsWhen_callerNotOwner() public useActor(0) {
        vm.expectRevert("Ownable: caller is not the owner");
        yieldReserve.updateOracleAddress(VAULT);
    }

    function test_revertsWhen_invalidAddress() public useKnownActor(USDS_OWNER) {
        vm.expectRevert(abi.encodeWithSelector(Helpers.InvalidAddress.selector));
        yieldReserve.updateOracleAddress(address(0));
    }

    function test_updateOracleAddress() public useKnownActor(USDS_OWNER) {
        vm.expectEmit(address(yieldReserve));
        emit OracleUpdated(VAULT);
        yieldReserve.updateOracleAddress(VAULT);
        assertEq(yieldReserve.oracle(), VAULT);
    }
}

contract UpdateDripperAddressTest is YieldReserveTest {
    event DripperAddressUpdated(address newDripper);

    function test_revertsWhen_callerNotOwner() public useActor(0) {
        vm.expectRevert("Ownable: caller is not the owner");
        yieldReserve.updateDripperAddress(VAULT);
    }

    function test_revertsWhen_invalidAddress() public useKnownActor(USDS_OWNER) {
        vm.expectRevert(abi.encodeWithSelector(Helpers.InvalidAddress.selector));
        yieldReserve.updateDripperAddress(address(0));
    }

    function test_updateDripperAddress() public useKnownActor(USDS_OWNER) {
        vm.expectEmit(address(yieldReserve));
        emit DripperAddressUpdated(VAULT);
        yieldReserve.updateDripperAddress(VAULT);
        assertEq(yieldReserve.dripper(), VAULT);
    }
}

contract UpdateVaultAddressTest is YieldReserveTest {
    event VaultAddressUpdated(address newVault);

    function test_revertsWhen_callerNotOwner() public useActor(0) {
        vm.expectRevert("Ownable: caller is not the owner");
        yieldReserve.updateVaultAddress(VAULT);
    }

    function test_revertsWhen_invalidAddress() public useKnownActor(USDS_OWNER) {
        vm.expectRevert(abi.encodeWithSelector(Helpers.InvalidAddress.selector));
        yieldReserve.updateVaultAddress(address(0));
    }

    function test_updateVaultAddress() public useKnownActor(USDS_OWNER) {
        vm.expectEmit(address(yieldReserve));
        emit VaultAddressUpdated(ORACLE);
        yieldReserve.updateVaultAddress(ORACLE);
        assertEq(yieldReserve.vault(), ORACLE);
    }
}

contract GetTokenBForTokenATest is YieldReserveTest {
    function setUp() public override {
        super.setUp();
        mockPrice(USDCe, 1e8, PRICE_PRECISION);
        mockPrice(USDS, 1e8, PRICE_PRECISION);
    }

    function test_revertsWhen_invalidSourceToken() public {
        vm.expectRevert(abi.encodeWithSelector(YieldReserve.InvalidSourceToken.selector));
        yieldReserve.getTokenBForTokenA(USDS, USDCe, 10000);
    }

    function test_revertsWhen_invalidDestinationToken() public useKnownActor(USDS_OWNER) {
        yieldReserve.toggleSrcTokenPermission(USDS, true);
        vm.expectRevert(abi.encodeWithSelector(YieldReserve.InvalidDestinationToken.selector));
        yieldReserve.getTokenBForTokenA(USDS, USDCe, 10000);
    }

    function test_revertsWhen_invalidAmount() public useKnownActor(USDS_OWNER) {
        yieldReserve.toggleSrcTokenPermission(USDS, true);
        yieldReserve.toggleDstTokenPermission(USDCe, true);
        vm.expectRevert(abi.encodeWithSelector(Helpers.InvalidAmount.selector));
        yieldReserve.getTokenBForTokenA(USDS, USDCe, 0);
    }

    function test_getTokenBForTokenA() public useKnownActor(USDS_OWNER) {
        uint256 amountIn = 100;
        mockPrice(USDCe, 1e8, PRICE_PRECISION);
        mockPrice(USDS, 1e8, PRICE_PRECISION);

        yieldReserve.toggleSrcTokenPermission(USDS, true);
        yieldReserve.toggleDstTokenPermission(USDCe, true);

        assertEq(getTokenData(USDCe).conversionFactor, 1e12);
        assertEq(getTokenData(USDS).conversionFactor, 1);

        uint256 amount = yieldReserve.getTokenBForTokenA(USDS, USDCe, amountIn * USDsPrecision);

        assertEq(amount, amountIn * USDCePrecision);
    }

    function test_getTokenBForTokenA_SamePrecision() public useKnownActor(USDS_OWNER) {
        uint256 amountIn = 100;
        mockPrice(DAI, 1e8, PRICE_PRECISION);
        mockPrice(USDS, 1e8, PRICE_PRECISION);

        yieldReserve.toggleSrcTokenPermission(USDS, true);
        yieldReserve.toggleDstTokenPermission(DAI, true);

        assertEq(getTokenData(DAI).conversionFactor, 1);
        assertEq(getTokenData(USDS).conversionFactor, 1);

        uint256 amount = yieldReserve.getTokenBForTokenA(USDS, DAI, amountIn * USDsPrecision);

        assertEq(amount, amountIn * DAIPrecision);
    }
}

contract SwapTest is YieldReserveTest {
    function setUp() public override {
        super.setUp();
        vm.startPrank(USDS_OWNER);
        deal(address(USDCe), USDS_OWNER, 1e18);
        deal(address(USDCe), address(yieldReserve), 1e20);
        deal(address(DAI), address(yieldReserve), 1e20);

        mockPrice(USDCe, 1e8, PRICE_PRECISION);
        mockPrice(USDS, 1e8, PRICE_PRECISION);
        mockPrice(DAI, 1e8, PRICE_PRECISION);

        mintUSDs(1e7);

        vm.stopPrank();
    }

    function test_swap_slippage_error() public useKnownActor(USDS_OWNER) {
        uint256 amt = 10;
        IERC20(USDS).approve(address(yieldReserve), amt * USDsPrecision);

        yieldReserve.toggleSrcTokenPermission(USDS, true);
        yieldReserve.toggleDstTokenPermission(USDCe, true);

        uint256 toSend = yieldReserve.getTokenBForTokenA(USDS, USDCe, amt * USDsPrecision);
        vm.expectRevert(abi.encodeWithSelector(Helpers.MinSlippageError.selector, toSend, (amt + 1) * USDCePrecision));
        yieldReserve.swap(USDS, USDCe, amt * USDsPrecision, (amt + 1) * USDCePrecision);
    }

    function test_swap() public useKnownActor(USDS_OWNER) {
        uint256 amt = 10;
        IERC20(USDS).approve(address(yieldReserve), amt * USDsPrecision);

        yieldReserve.toggleSrcTokenPermission(USDS, true);
        yieldReserve.toggleDstTokenPermission(USDCe, true);

        uint256 initialBal = IERC20(USDCe).balanceOf(currentActor);
        uint256 expectedAmt = yieldReserve.getTokenBForTokenA(USDS, USDCe, amt * USDsPrecision);
        yieldReserve.swap(USDS, USDCe, amt * USDsPrecision, 0);
        assertEq(IERC20(USDCe).balanceOf(currentActor), initialBal + expectedAmt);
    }

    function test_swap_samePrecision() public useKnownActor(USDS_OWNER) {
        uint256 amt = 10;
        IERC20(USDS).approve(address(yieldReserve), amt * USDsPrecision);

        yieldReserve.toggleSrcTokenPermission(USDS, true);
        yieldReserve.toggleDstTokenPermission(DAI, true);
        uint256 initialBal = IERC20(DAI).balanceOf(currentActor);
        uint256 expectedAmt = yieldReserve.getTokenBForTokenA(USDS, DAI, amt * USDsPrecision);
        yieldReserve.swap(USDS, DAI, amt * USDsPrecision, 0);
        assertEq(IERC20(DAI).balanceOf(currentActor), initialBal + expectedAmt);
    }

    function test_swap_non_USDS() public useKnownActor(USDS_OWNER) {
        yieldReserve.toggleSrcTokenPermission(USDCe, true);
        yieldReserve.toggleDstTokenPermission(USDS, true);
        uint256 amt = 10;

        vm.mockCall(
            VAULT, abi.encodeWithSignature("mintView(address, uint256)", USDCe, amt * USDCePrecision), abi.encode(10)
        );

        uint256 timestamp = block.timestamp + 1200;
        vm.mockCall(
            VAULT,
            abi.encodeWithSignature(
                "mint(address, uint256, uint256, uint256)", USDCe, amt * USDCePrecision, 10 * USDsPrecision, timestamp
            ),
            abi.encode()
        );

        IERC20(USDCe).approve(address(yieldReserve), amt * USDCePrecision);
        yieldReserve.swap(USDCe, USDS, amt * USDCePrecision, 0);
    }
}
