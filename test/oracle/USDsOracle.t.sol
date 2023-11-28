// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {USDsOracle} from "../../contracts/oracle/USDsOracle.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {BaseUniOracleTest} from "./SPAOracle.t.sol";

abstract contract USDsOracleTest is BaseUniOracleTest {
    uint24 public constant FEE_TIER = 10000;
    uint32 public constant MA_PERIOD = 600;
    uint128 public constant USDS_PRICE_PRECISION = 1e8;

    USDsOracle public usdsOracle;

    function setUp() public override {
        super.setUp();
        vm.prank(USDS_OWNER);
        usdsOracle = new USDsOracle(masterOracle, USDCe, FEE_TIER, MA_PERIOD);
    }
}

contract Test_Init is USDsOracleTest {
    function test_initialization() public {
        assertEq(usdsOracle.pool(), IUniswapV3Factory(UNISWAP_FACTORY).getPool(USDS, USDCe, FEE_TIER));
        assertEq(uint256(usdsOracle.maPeriod()), uint256(MA_PERIOD));
    }
}

contract Test_FetchPrice is USDsOracleTest {
    function test_fetchPrice() public {
        (uint256 price, uint256 precision) = usdsOracle.getPrice();
        assertEq(precision, USDS_PRICE_PRECISION);
        assertGt(price, 0);
    }

    function testFuzz_fetchPrice_when_period_value_below_minTwapPeriod(uint256 period) public {
        // this test is to make sure that even if the twap period value is less than MIN_TWAP_PERIOD (10 mins)
        // we still get the price based on MIN_TWAP_PERIOD (10 mins)
        vm.assume(period < 10 minutes);
        address UNISWAP_UTILS = usdsOracle.UNISWAP_UTILS();
        vm.mockCall(
            UNISWAP_UTILS,
            abi.encodeWithSignature("getOldestObservationSecondsAgo(address)", usdsOracle.pool()),
            abi.encode(period)
        );
        (uint256 price0, uint256 precision0) = usdsOracle.getPrice();

        vm.mockCall(
            UNISWAP_UTILS,
            abi.encodeWithSignature("getOldestObservationSecondsAgo(address)", usdsOracle.pool()),
            abi.encode(10 minutes)
        );
        (uint256 price1, uint256 precision1) = usdsOracle.getPrice();

        assertEq(price0, price1);
        assertEq(precision0, precision1);
    }
}
