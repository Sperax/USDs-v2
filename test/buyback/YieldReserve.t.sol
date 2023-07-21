// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {BaseTest} from "../utils/BaseTest.sol";
import {YieldReserve} from "../../contracts/buyback/YieldReserve.sol";
import {IVault} from "../../contracts/interfaces/IVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract YieldReserveTest is BaseTest {
    YieldReserve internal yieldReserve;
    address public constant USDCe = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;

    function setUp() public virtual override {
        super.setUp();

        setArbitrumFork();
        vm.startPrank(USDS_OWNER);
        yieldReserve = new YieldReserve(BUYBACK, VAULT, ORACLE, DRIPPER);
        vm.stopPrank();
    }

    function mintUSDs(uint256 amountIn) public {
        deal(address(USDCe), USDS_OWNER, 1 ether);
        IERC20(USDCe).approve(VAULT, amountIn);
        IVault(VAULT).mintBySpecifyingCollateralAmt(
            USDCe,
            amountIn,
            0,
            0,
            block.timestamp + 1200
        );
    }

    function test_toggleSrcTokenPermission_auth_error() public useActor(0) {
        vm.expectRevert("Ownable: caller is not the owner");
        yieldReserve.toggleSrcTokenPermission(SPA, true);
    }

    function test_toggleSrcTokenPermission() public useKnownActor(USDS_OWNER) {
        vm.mockCall(
            ORACLE,
            abi.encodeWithSignature("getPrice(address)", SPA),
            abi.encode([10, 1000000])
        );

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
        vm.mockCall(
            ORACLE,
            abi.encodeWithSignature("getPrice(address)", SPA),
            abi.encode([10, 1000000])
        );

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
        deal(address(SPA), address(yieldReserve), 1 ether);

        uint256 initialBal = IERC20(SPA).balanceOf(USDS_OWNER);

        yieldReserve.withdraw(SPA, USDS_OWNER, inputBal);

        uint256 newBal = IERC20(SPA).balanceOf(USDS_OWNER);

        assertEq(inputBal + initialBal, newBal);
    }

    // require(_toBuyback <= MAX_PERCENTAGE, "% exceeds 100%");
    // require(_toBuyback > 0, "% must be > 0");

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

    function test_updateBuybackAddress() public useKnownActor(USDS_OWNER) {
        yieldReserve.updateBuybackAddress(VAULT);
    }

    function test_updateOracleAddress() public useKnownActor(USDS_OWNER) {
        yieldReserve.updateOracleAddress(VAULT);
    }

    function test_updateDripperAddress() public useKnownActor(USDS_OWNER) {
        yieldReserve.updateDripperAddress(VAULT);
    }

    function test_updateVaultAddress() public useKnownActor(USDS_OWNER) {
        yieldReserve.updateVaultAddress(ORACLE);
    }

    function test_getTokenBforTokenA() public useKnownActor(USDS_OWNER) {
        vm.mockCall(
            ORACLE,
            abi.encodeWithSignature("getPrice(address)", USDCe),
            abi.encode([10, 1000000])
        );

        vm.mockCall(
            ORACLE,
            abi.encodeWithSignature("getPrice(address)", USDS),
            abi.encode([10, 1000000])
        );

        yieldReserve.toggleSrcTokenPermission(USDS, true);
        yieldReserve.toggleDstTokenPermission(USDCe, true);

        yieldReserve.getTokenBforTokenA(USDS, 10000, USDCe);
    }
}

contract SwapTest is YieldReserveTest {
    function setUp() public override {
        super.setUp();
        vm.startPrank(USDS_OWNER);
        deal(address(USDCe), USDS_OWNER, 1 ether);
        mintUSDs(1000000);

        vm.mockCall(
            ORACLE,
            abi.encodeWithSignature("getPrice(address)", USDCe),
            abi.encode([10, 1000000])
        );
        vm.mockCall(
            ORACLE,
            abi.encodeWithSignature("getPrice(address)", USDS),
            abi.encode([10, 1000000])
        );

        vm.stopPrank();
    }

    function test_swap() public useKnownActor(USDS_OWNER) {
        IERC20(USDS).approve(address(yieldReserve), 1000);

        yieldReserve.toggleSrcTokenPermission(USDS, true);
        yieldReserve.toggleDstTokenPermission(USDCe, true);

        IERC20(USDS).approve(address(yieldReserve), 1000);

        yieldReserve.swap(USDS, USDCe, 1000, 0);
    }

    function test_swap_non_USDS() public useKnownActor(USDS_OWNER) {
        yieldReserve.toggleSrcTokenPermission(USDCe, true);
        yieldReserve.toggleDstTokenPermission(USDS, true);

        vm.mockCall(
            VAULT,
            abi.encodeWithSignature("mintView(address, uint256)", USDCe, 1000),
            abi.encode(10)
        );

        uint256 timestamp = block.timestamp + 1200;
        vm.mockCall(
            VAULT,
            abi.encodeWithSignature(
                "mint(address, uint256, uint256, uint256)",
                USDCe,
                1000,
                10,
                timestamp
            ),
            abi.encode()
        );

        IERC20(USDCe).approve(address(yieldReserve), 1000);
        yieldReserve.swap(USDCe, USDS, 1000, 0);
    }
}
