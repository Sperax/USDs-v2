pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

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
}
