// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {YieldReserve} from "../../contracts/buyback/YieldReserve.sol";
import {IVault} from "../../contracts/interfaces/IVault.sol";
import {VaultCore} from "../../contracts/vault/VaultCore.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {PreMigrationSetup} from "../utils/DeploymentSetup.sol";

contract YieldReserveTest is PreMigrationSetup {
    YieldReserve internal yieldReserve;
    IVault internal vault;
    uint256 USDCePrecesion = 10 ** 6;
    uint256 SPAPrecesion = 10 ** 18;
    uint256 USDsPrecesion = 10 ** 18;

    function setUp() public virtual override {
        super.setUp();
        vm.startPrank(USDS_OWNER);
        yieldReserve = new YieldReserve(BUYBACK, VAULT, ORACLE, DRIPPER);
        vm.stopPrank();
    }

    function mintUSDs(uint256 amountIn) public {
        deal(address(USDCe), USDS_OWNER, amountIn * USDCePrecesion);
        IERC20(USDCe).approve(VAULT, amountIn);
        IVault(VAULT).mintBySpecifyingCollateralAmt(
            USDCe,
            amountIn,
            0,
            0,
            block.timestamp + 1200
        );
    }

    function mockPrice(address token, uint256 price, uint256 precision) public {
        vm.mockCall(
            ORACLE,
            abi.encodeWithSignature("getPrice(address)", token),
            abi.encode([price, precision])
        );
    }

    function test_toggleSrcTokenPermission_auth_error() public useActor(0) {
        vm.expectRevert("Ownable: caller is not the owner");
        yieldReserve.toggleSrcTokenPermission(SPA, true);
    }

    function test_toggleSrcTokenPermission() public useKnownActor(USDS_OWNER) {
        mockPrice(SPA, 10, SPAPrecesion);

        yieldReserve.toggleSrcTokenPermission(SPA, true);

        assertEq(yieldReserve.isAllowedSrc(SPA), true);

        vm.expectRevert("Already in desired state");
        yieldReserve.toggleSrcTokenPermission(SPA, true);
    }

    function test_toggleDstTokenPermission_auth_error() public useActor(0) {
        vm.expectRevert("Ownable: caller is not the owner");
        yieldReserve.toggleDstTokenPermission(SPA, true);
    }

    function test_toggleDstTokenPermission() public useKnownActor(USDS_OWNER) {
        mockPrice(SPA, 10, SPAPrecesion);

        yieldReserve.toggleDstTokenPermission(SPA, true);

        assertEq(yieldReserve.isAllowedDst(SPA), true);

        vm.expectRevert("Already in desired state");
        yieldReserve.toggleDstTokenPermission(SPA, true);
    }

    function test_withdraw_auth_error() public useActor(0) {
        vm.expectRevert("Ownable: caller is not the owner");
        yieldReserve.withdraw(SPA, USDS_OWNER, 10);
    }

    function test_withdraw_inputs() public useKnownActor(USDS_OWNER) {
        vm.expectRevert("Invalid address");
        yieldReserve.withdraw(address(0), USDS_OWNER, 10);

        vm.expectRevert("Invalid address");
        yieldReserve.withdraw(SPA, address(0), 10);

        vm.expectRevert("Invalid amount");
        yieldReserve.withdraw(SPA, USDS_OWNER, 0);
    }

    function test_withdraw() public useKnownActor(USDS_OWNER) {
        uint256 inputBal = 10000;
        deal(address(SPA), address(yieldReserve), inputBal * SPAPrecesion);

        uint256 initialBal = IERC20(SPA).balanceOf(USDS_OWNER);

        yieldReserve.withdraw(SPA, USDS_OWNER, inputBal);

        uint256 newBal = IERC20(SPA).balanceOf(USDS_OWNER);

        assertEq(inputBal + initialBal, newBal);
    }

    function test_updateBuybackPercentage_auth_error() public useActor(0) {
        vm.expectRevert("Ownable: caller is not the owner");
        yieldReserve.updateBuybackPercentage(2000);
    }

    function test_updateBuybackPercentage_inputs()
        public
        useKnownActor(USDS_OWNER)
    {
        uint256 perc = 10001;
        vm.expectRevert("% exceeds 100%");
        yieldReserve.updateBuybackPercentage(perc);

        perc = 0;
        vm.expectRevert("% must be > 0");
        yieldReserve.updateBuybackPercentage(perc);
    }

    function test_updateBuybackPercentage() public useKnownActor(USDS_OWNER) {
        uint256 perc = 2000;
        yieldReserve.updateBuybackPercentage(perc);

        assertEq(yieldReserve.buybackPercentage(), perc);
    }

    function test_updateBuybackAddress_auth_error() public useActor(0) {
        vm.expectRevert("Ownable: caller is not the owner");
        yieldReserve.updateBuybackAddress(VAULT);
    }

    function test_updateBuybackAddress_inputs()
        public
        useKnownActor(USDS_OWNER)
    {
        vm.expectRevert("Invalid address");
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

    function test_updateOracleAddress_inputs()
        public
        useKnownActor(USDS_OWNER)
    {
        vm.expectRevert("Invalid address");
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

    function test_updateDripperAddress_inputs()
        public
        useKnownActor(USDS_OWNER)
    {
        vm.expectRevert("Invalid address");
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
        vm.expectRevert("Invalid address");
        yieldReserve.updateVaultAddress(address(0));
    }

    function test_updateVaultAddress() public useKnownActor(USDS_OWNER) {
        yieldReserve.updateVaultAddress(ORACLE);
        assertEq(yieldReserve.vault(), ORACLE);
    }

    function test_getTokenBforTokenA_inputs() public useKnownActor(USDS_OWNER) {
        mockPrice(USDCe, 10, USDCePrecesion);
        mockPrice(USDS, 10, USDsPrecesion);

        vm.expectRevert("Source token is not allowed");
        yieldReserve.getTokenBforTokenA(USDS, 10000, USDCe);
        yieldReserve.toggleSrcTokenPermission(USDS, true);

        vm.expectRevert("Destination token is not allowed");
        yieldReserve.getTokenBforTokenA(USDS, 10000, USDCe);
        yieldReserve.toggleDstTokenPermission(USDCe, true);

        vm.expectRevert("Invalid amount");
        yieldReserve.getTokenBforTokenA(USDS, 0, USDCe);
    }

    function test_getTokenBforTokenA() public useKnownActor(USDS_OWNER) {
        uint256 amountIn = 100;
        mockPrice(USDCe, 1, USDCePrecesion);
        mockPrice(USDS, 1, USDsPrecesion);

        yieldReserve.toggleSrcTokenPermission(USDS, true);
        yieldReserve.toggleDstTokenPermission(USDCe, true);

        uint256 amount = yieldReserve.getTokenBforTokenA(
            USDS,
            amountIn * USDsPrecesion,
            USDCe
        );

        assertEq(amount, amountIn * USDCePrecesion);
    }
}

contract SwapTest is YieldReserveTest {
    function setUp() public override {
        super.setUp();
        vm.startPrank(USDS_OWNER);
        deal(address(USDCe), USDS_OWNER, 1 ether);
        deal(address(USDCe), address(yieldReserve), 1 ether);

        mockPrice(USDCe, 1e8, USDCePrecesion);
        mockPrice(USDS, 1e8, USDsPrecesion);

        mintUSDs(1e7);

        vm.stopPrank();
    }

    function test_swap_slippage_error() public useKnownActor(USDS_OWNER) {
        uint256 amt = 10;
        IERC20(USDS).approve(address(yieldReserve), amt * USDsPrecesion);

        yieldReserve.toggleSrcTokenPermission(USDS, true);
        yieldReserve.toggleDstTokenPermission(USDCe, true);

        vm.expectRevert("Slippage more than expected");
        yieldReserve.swap(
            USDS,
            USDCe,
            amt * USDsPrecesion,
            (amt + 1) * USDCePrecesion
        );
    }

    function test_swap() public useKnownActor(USDS_OWNER) {
        uint256 amt = 10;
        IERC20(USDS).approve(address(yieldReserve), amt * USDsPrecesion);

        yieldReserve.toggleSrcTokenPermission(USDS, true);
        yieldReserve.toggleDstTokenPermission(USDCe, true);

        yieldReserve.swap(USDS, USDCe, amt * USDsPrecesion, 0);
    }

    function test_swap_non_USDS() public useKnownActor(USDS_OWNER) {
        yieldReserve.toggleSrcTokenPermission(USDCe, true);
        yieldReserve.toggleDstTokenPermission(USDS, true);
        uint256 amt = 10;

        vm.mockCall(
            VAULT,
            abi.encodeWithSignature(
                "mintView(address, uint256)",
                USDCe,
                amt * USDCePrecesion
            ),
            abi.encode(10)
        );

        uint256 timestamp = block.timestamp + 1200;
        vm.mockCall(
            VAULT,
            abi.encodeWithSignature(
                "mint(address, uint256, uint256, uint256)",
                USDCe,
                amt * USDCePrecesion,
                10 * USDsPrecesion,
                timestamp
            ),
            abi.encode()
        );

        IERC20(USDCe).approve(address(yieldReserve), amt * USDCePrecesion);
        yieldReserve.swap(USDCe, USDS, amt * USDCePrecesion, 0);
    }
}
