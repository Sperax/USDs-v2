// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {YieldReserve, Helpers} from "../../contracts/buyback/YieldReserve.sol";
import {IVault} from "../../contracts/interfaces/IVault.sol";
import {IOracle} from "../../contracts/interfaces/IOracle.sol";
import {VaultCore} from "../../contracts/vault/VaultCore.sol";
import {IERC20, ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {PreMigrationSetup} from "../utils/DeploymentSetup.t.sol";

contract YieldReserveSetup is PreMigrationSetup {
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

contract YieldReserveTest is YieldReserveSetup {
    function test_toggleSrcTokenPermission_auth_error() public useActor(0) {
        vm.expectRevert("Ownable: caller is not the owner");
        yieldReserve.toggleSrcTokenPermission(SPA, true);
    }

    function test_toggleSrcTokenPermission() public useKnownActor(USDS_OWNER) {
        mockPrice(SPA, 10, SPAPrecision);

        yieldReserve.toggleSrcTokenPermission(SPA, true);
        YieldReserve.TokenData memory tokenData = getTokenData(SPA);
        assertTrue(tokenData.srcAllowed);
        assertEq(tokenData.conversionFactor, 1);

        assertTrue(IOracle(ORACLE).priceFeedExists(SPA));

        vm.expectRevert(abi.encodeWithSelector(YieldReserve.AlreadyInDesiredState.selector));
        yieldReserve.toggleSrcTokenPermission(SPA, true);

        // toggle to false case
        yieldReserve.toggleSrcTokenPermission(SPA, false);

        tokenData = getTokenData(SPA);
        assertFalse(tokenData.srcAllowed);

        vm.expectRevert(abi.encodeWithSelector(YieldReserve.AlreadyInDesiredState.selector));
        yieldReserve.toggleSrcTokenPermission(SPA, false);

        // priceFeed doesn't exist case.
        address randomTokenAddress = address(0x9);

        vm.expectRevert(abi.encodeWithSelector(YieldReserve.TokenPriceFeedMissing.selector));
        yieldReserve.toggleSrcTokenPermission(randomTokenAddress, true);
    }

    function test_toggleDstTokenPermission_auth_error() public useActor(0) {
        vm.expectRevert("Ownable: caller is not the owner");
        yieldReserve.toggleDstTokenPermission(SPA, true);
    }

    function test_toggleDstTokenPermission() public useKnownActor(USDS_OWNER) {
        mockPrice(SPA, 10, SPAPrecision);

        yieldReserve.toggleDstTokenPermission(SPA, true);

        YieldReserve.TokenData memory tokenData = getTokenData(SPA);
        assertTrue(tokenData.dstAllowed);
        assertEq(tokenData.conversionFactor, 1);

        assertTrue(IOracle(ORACLE).priceFeedExists(SPA));

        vm.expectRevert(abi.encodeWithSelector(YieldReserve.AlreadyInDesiredState.selector));
        yieldReserve.toggleDstTokenPermission(SPA, true);

        // toggle to false case
        yieldReserve.toggleDstTokenPermission(SPA, false);

        tokenData = getTokenData(SPA);
        assertFalse(tokenData.dstAllowed);

        vm.expectRevert(abi.encodeWithSelector(YieldReserve.AlreadyInDesiredState.selector));
        yieldReserve.toggleSrcTokenPermission(SPA, false);

        // priceFeed doesn't exist case.
        address randomTokenAddress = address(0x9);

        vm.expectRevert(abi.encodeWithSelector(YieldReserve.TokenPriceFeedMissing.selector));
        yieldReserve.toggleDstTokenPermission(randomTokenAddress, true);
    }

    function test_withdraw_auth_error() public useActor(0) {
        vm.expectRevert("Ownable: caller is not the owner");
        yieldReserve.withdraw(SPA, USDS_OWNER, 10);
    }

    function test_withdraw_inputs() public useKnownActor(USDS_OWNER) {
        vm.expectRevert("Address: call to non-contract");
        yieldReserve.withdraw(address(0), USDS_OWNER, 10);

        vm.expectRevert("ERC20: transfer to the zero address");
        yieldReserve.withdraw(SPA, address(0), 10);

        vm.expectRevert(abi.encodeWithSelector(Helpers.InvalidAmount.selector));
        yieldReserve.withdraw(SPA, USDS_OWNER, 0);
    }

    function test_withdraw() public useKnownActor(USDS_OWNER) {
        uint256 inputBal = 10000;
        deal(address(SPA), address(yieldReserve), inputBal * SPAPrecision);

        uint256 initialBal = IERC20(SPA).balanceOf(USDS_OWNER);

        yieldReserve.withdraw(SPA, USDS_OWNER, inputBal);

        uint256 newBal = IERC20(SPA).balanceOf(USDS_OWNER);

        assertEq(inputBal + initialBal, newBal);
    }

    function test_updateBuybackPercentage_auth_error() public useActor(0) {
        vm.expectRevert("Ownable: caller is not the owner");
        yieldReserve.updateBuybackPercentage(2000);
    }

    function test_updateBuybackPercentage_inputs() public useKnownActor(USDS_OWNER) {
        uint256 buybackPercentage = 10001;
        vm.expectRevert(abi.encodeWithSelector(Helpers.GTMaxPercentage.selector, buybackPercentage));
        yieldReserve.updateBuybackPercentage(buybackPercentage);

        buybackPercentage = 0;
        vm.expectRevert(abi.encodeWithSelector(Helpers.InvalidAmount.selector));
        yieldReserve.updateBuybackPercentage(buybackPercentage);
    }

    function test_updateBuybackPercentage() public useKnownActor(USDS_OWNER) {
        uint256 buybackPercentage = 2000;
        yieldReserve.updateBuybackPercentage(buybackPercentage);

        assertEq(yieldReserve.buybackPercentage(), buybackPercentage);
    }

    function test_updateBuybackAddress_auth_error() public useActor(0) {
        vm.expectRevert("Ownable: caller is not the owner");
        yieldReserve.updateBuybackAddress(VAULT);
    }

    function test_updateBuybackAddress_inputs() public useKnownActor(USDS_OWNER) {
        vm.expectRevert(abi.encodeWithSelector(Helpers.InvalidAddress.selector));
        yieldReserve.updateBuybackAddress(address(0));
    }

    function test_updateBuybackAddress() public useKnownActor(USDS_OWNER) {
        yieldReserve.updateBuybackAddress(VAULT);
        assertEq(yieldReserve.buyback(), VAULT);
    }

    function test_updateOracleAddress_auth_error() public useActor(0) {
        vm.expectRevert("Ownable: caller is not the owner");
        yieldReserve.updateOracleAddress(VAULT);
    }

    function test_updateOracleAddress_inputs() public useKnownActor(USDS_OWNER) {
        vm.expectRevert(abi.encodeWithSelector(Helpers.InvalidAddress.selector));
        yieldReserve.updateOracleAddress(address(0));
    }

    function test_updateOracleAddress() public useKnownActor(USDS_OWNER) {
        yieldReserve.updateOracleAddress(VAULT);
        assertEq(yieldReserve.oracle(), VAULT);
    }

    function test_updateDripperAddress_auth_error() public useActor(0) {
        vm.expectRevert("Ownable: caller is not the owner");
        yieldReserve.updateDripperAddress(VAULT);
    }

    function test_updateDripperAddress_inputs() public useKnownActor(USDS_OWNER) {
        vm.expectRevert(abi.encodeWithSelector(Helpers.InvalidAddress.selector));
        yieldReserve.updateDripperAddress(address(0));
    }

    function test_updateDripperAddress() public useKnownActor(USDS_OWNER) {
        yieldReserve.updateDripperAddress(VAULT);
        assertEq(yieldReserve.dripper(), VAULT);
    }

    function test_updateVaultAddress_auth_error() public useActor(0) {
        vm.expectRevert("Ownable: caller is not the owner");
        yieldReserve.updateVaultAddress(VAULT);
    }

    function test_updateVaultAddress_inputs() public useKnownActor(USDS_OWNER) {
        vm.expectRevert(abi.encodeWithSelector(Helpers.InvalidAddress.selector));
        yieldReserve.updateVaultAddress(address(0));
    }

    function test_updateVaultAddress() public useKnownActor(USDS_OWNER) {
        yieldReserve.updateVaultAddress(ORACLE);
        assertEq(yieldReserve.vault(), ORACLE);
    }

    function test_getTokenBForTokenA_inputs() public useKnownActor(USDS_OWNER) {
        mockPrice(USDCe, 10e8, PRICE_PRECISION);
        mockPrice(USDS, 10e8, PRICE_PRECISION);

        vm.expectRevert(abi.encodeWithSelector(YieldReserve.InvalidSourceToken.selector));
        yieldReserve.getTokenBForTokenA(USDS, USDCe, 10000);
        yieldReserve.toggleSrcTokenPermission(USDS, true);

        vm.expectRevert(abi.encodeWithSelector(YieldReserve.InvalidDestinationToken.selector));
        yieldReserve.getTokenBForTokenA(USDS, USDCe, 10000);
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

contract SwapTest is YieldReserveSetup {
    function setUp() public override {
        super.setUp();
        vm.startPrank(USDS_OWNER);
        deal(address(USDCe), USDS_OWNER, 1 ether);
        deal(address(USDCe), address(yieldReserve), 100 ether);
        deal(address(DAI), address(yieldReserve), 100 ether);

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
