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

        // impl = new AaveStrategy();
        // upgradeUtil = new UpgradeUtil();
        // proxyAddress = upgradeUtil.deployErc1967Proxy(address(impl));

        // aaveStrategy = AaveStrategy(proxyAddress);
        // vm.stopPrank();
    }

    function test_toggleSrcTokenPermission() public useKnownActor(USDS_OWNER) {
        vm.mockCall(
            ORACLE,
            abi.encodeWithSignature("getPrice(address)", SPA),
            abi.encode([10, 1000000])
        );

        yieldReserve.toggleSrcTokenPermission(SPA, true);
    }

    function test_toggleDstTokenPermission() public useKnownActor(USDS_OWNER) {
        vm.mockCall(
            ORACLE,
            abi.encodeWithSignature("getPrice(address)", SPA),
            abi.encode([10, 1000000])
        );

        yieldReserve.toggleDstTokenPermission(SPA, true);
    }

    function test_withdraw() public useKnownActor(USDS_OWNER) {
        deal(address(SPA), address(yieldReserve), 1 ether);
        yieldReserve.withdraw(SPA, USDS_OWNER, 10);
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

    function mintUSDs(uint256 amountIn) public {
        // deal(address(USDCe), USDS_OWNER, 1 ether);
        // IERC20(USDCe).approve(VAULT, amountIn);
        // (uint256 _minUSDSAmt, ) = IVault(VAULT).mintView(
        //     USDCe,
        //     amountIn
        // );
        // IVault(VAULT).mint(
        //     USDCe,
        //     amountIn,
        //     _minUSDSAmt,
        //     block.timestamp + 1200
        // );
    }

    function test_swap() public useKnownActor(USDS_OWNER) {
        deal(address(USDCe), USDS_OWNER, 1 ether);
        mintUSDs(1000000);

        IERC20(USDCe).approve(address(yieldReserve), 1000);

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

        vm.mockCall(
            ORACLE,
            abi.encodeWithSignature("getPrice(address)", USDS),
            abi.encode([10, 1000000])
        );

        yieldReserve.toggleSrcTokenPermission(USDCe, true);
        yieldReserve.toggleDstTokenPermission(USDS, true);

        //yieldReserve.swap(USDCe, USDS, 1, 0);
    }
}
