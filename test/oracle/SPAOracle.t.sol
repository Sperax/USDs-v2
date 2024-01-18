// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SPAOracle, IDiaOracle} from "../../contracts/oracle/SPAOracle.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {BaseTest} from "../utils/BaseTest.sol";

interface IChainlinkOracle {
    struct TokenData {
        address source;
        uint96 timeout;
        uint256 precision;
    }

    function setTokenData(address _token, TokenData memory _tokenData) external;

    function getTokenPrice(address _token) external view returns (uint256, uint256);
}

interface IMasterOracle {
    function updateTokenPriceFeed(address token, address source, bytes calldata msgData) external;

    function removeTokenPriceFeed(address _token) external;
}

abstract contract BaseUniOracleTest is BaseTest {
    address public constant UNISWAP_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address masterOracle;
    address chainlinkOracle;

    event UniMAPriceDataChanged(address quoteToken, uint24 feeTier, uint32 maPeriod);
    event MasterOracleUpdated(address newOracle);

    error FeedUnavailable();
    error InvalidAddress();
    error QuoteTokenFeedMissing();

    function setUp() public virtual override {
        super.setUp();
        setArbitrumFork();
        vm.startPrank(USDS_OWNER);
        masterOracle = deployCode("MasterPriceOracle.sol");

        chainlinkOracle = deployCode("ChainlinkOracle.sol", abi.encode(new IChainlinkOracle.TokenData[](0)));
        IChainlinkOracle.TokenData memory usdcData =
            IChainlinkOracle.TokenData(0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3, 25 hours, 1e8);

        IChainlinkOracle(chainlinkOracle).setTokenData(USDCe, usdcData);

        IMasterOracle(masterOracle).updateTokenPriceFeed(
            USDCe, address(chainlinkOracle), abi.encodeWithSelector(IChainlinkOracle.getTokenPrice.selector, USDCe)
        );

        vm.stopPrank();
    }
}

contract SPAOracleTest is BaseUniOracleTest {
    address public constant DIA_ORACLE = 0x7919D08e0f41398cBc1e0A8950Df831e4895c19b;
    uint128 public constant SPA_PRICE_PRECISION = 1e8;
    uint24 public constant FEE_TIER = 10000;
    uint32 public constant MA_PERIOD = 600;
    uint256 public constant WEIGHT_DIA = 70;

    SPAOracle public spaOracle;

    event DIAParamsUpdated(uint256 weightDIA, uint128 maxTime);

    error InvalidWeight();
    error InvalidTime();
    error PriceTooOld();

    function setUp() public override {
        super.setUp();
        vm.startPrank(USDS_OWNER);
        spaOracle = new SPAOracle(masterOracle, USDCe, FEE_TIER, MA_PERIOD, WEIGHT_DIA);
        spaOracle.updateDIAParams(WEIGHT_DIA, type(uint128).max);
        vm.stopPrank();
    }
}

contract Test_Init is SPAOracleTest {
    function test_initialization() public {
        assertEq(spaOracle.pool(), IUniswapV3Factory(UNISWAP_FACTORY).getPool(SPA, USDCe, FEE_TIER));
        assertEq(uint256(spaOracle.maPeriod()), uint256(MA_PERIOD));
        assertEq(spaOracle.weightDIA(), WEIGHT_DIA);
    }

    function test_revertWhen_QuoteTokenFeedMissing() public {
        vm.expectRevert(abi.encodeWithSelector(QuoteTokenFeedMissing.selector));
        new SPAOracle(masterOracle, USDS, FEE_TIER, MA_PERIOD, WEIGHT_DIA); // USDS is not added to master oracle
    }
}

contract Test_GetPrice is SPAOracleTest {
    function test_revertWhen_PriceTooOld() public {
        vm.startPrank(USDS_OWNER);
        spaOracle.updateDIAParams(WEIGHT_DIA, 121);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(PriceTooOld.selector));
        spaOracle.getPrice();
    }

    function test_GetPrice() public {
        (uint256 price, uint256 precision) = spaOracle.getPrice();
        assertEq(precision, SPA_PRICE_PRECISION);
        assertGt(price, 0);
    }

    function testFuzz_GetPrice_when_period_value_below_minTwapPeriod(uint256 period) public {
        // this test is to make sure that even if the twap period value is less than MIN_TWAP_PERIOD (10 mins)
        // we still get the price based on MIN_TWAP_PERIOD (10 mins)
        vm.assume(period < 10 minutes);
        address UNISWAP_UTILS = spaOracle.UNISWAP_UTILS();
        vm.mockCall(
            UNISWAP_UTILS,
            abi.encodeWithSignature("getOldestObservationSecondsAgo(address)", spaOracle.pool()),
            abi.encode(period)
        );
        (uint256 price0, uint256 precision0) = spaOracle.getPrice();

        vm.mockCall(
            UNISWAP_UTILS,
            abi.encodeWithSignature("getOldestObservationSecondsAgo(address)", spaOracle.pool()),
            abi.encode(10 minutes)
        );
        (uint256 price1, uint256 precision1) = spaOracle.getPrice();

        assertEq(price0, price1);
        assertEq(precision0, precision1);
    }
}

contract Test_setUniMAPriceData is SPAOracleTest {
    error InvalidMaPeriod();

    function test_revertsWhen_notOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        spaOracle.setUniMAPriceData(SPA, USDCe, 10000, 600);
    }

    function test_revertsWhen_invalidData() public useKnownActor(USDS_OWNER) {
        vm.expectRevert(abi.encodeWithSelector(FeedUnavailable.selector));
        spaOracle.setUniMAPriceData(SPA, FRAX, 3000, 600);
    }

    function test_setUniMAPriceData() public useKnownActor(USDS_OWNER) {
        vm.expectEmit(true, true, true, true);
        emit UniMAPriceDataChanged(USDCe, 10000, 700);
        spaOracle.setUniMAPriceData(SPA, USDCe, 10000, 700);
        assertEq(spaOracle.quoteToken(), USDCe);
        assertEq(spaOracle.maPeriod(), 700);
        assertEq(spaOracle.quoteTokenPrecision(), uint128(10) ** ERC20(USDCe).decimals());
    }

    function test_revertsWhen_invalidMaPeriod() public useKnownActor(USDS_OWNER) {
        vm.expectRevert(abi.encodeWithSelector(InvalidMaPeriod.selector));
        spaOracle.setUniMAPriceData(SPA, USDCe, 10000, 599);

        vm.expectRevert(abi.encodeWithSelector(InvalidMaPeriod.selector));
        spaOracle.setUniMAPriceData(SPA, USDCe, 10000, 7201);
    }
}

contract Test_updateMasterOracle is SPAOracleTest {
    function test_revertsWhen_notOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        spaOracle.updateMasterOracle(masterOracle);
    }

    function test_revertsWhen_invalidAddress() public useKnownActor(USDS_OWNER) {
        vm.expectRevert(abi.encodeWithSelector(InvalidAddress.selector));
        spaOracle.updateMasterOracle(address(0));
    }

    function test_revertsWhen_quoteTokenPriceFeedUnavailable() public useKnownActor(USDS_OWNER) {
        IMasterOracle(masterOracle).removeTokenPriceFeed(USDCe);
        vm.expectRevert(abi.encodeWithSelector(QuoteTokenFeedMissing.selector));
        spaOracle.updateMasterOracle(masterOracle);
    }

    function test_updateMasterOracle() public useKnownActor(USDS_OWNER) {
        vm.expectEmit(true, true, true, true);
        emit MasterOracleUpdated(masterOracle);
        spaOracle.updateMasterOracle(masterOracle);
        assertEq(spaOracle.masterOracle(), masterOracle);
    }
}

contract Test_UpdateDIAWeight is SPAOracleTest {
    function test_revertsWhen_notOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        spaOracle.updateDIAParams(60, 600);
    }

    function test_revertsWhen_invalidWeight() public useKnownActor(USDS_OWNER) {
        uint256 newWeight = spaOracle.MAX_WEIGHT() + 10;
        vm.expectRevert(abi.encodeWithSelector(InvalidWeight.selector));
        spaOracle.updateDIAParams(newWeight, 600);
    }

    function test_revertsWhen_invalidTime() public useKnownActor(USDS_OWNER) {
        vm.expectRevert(abi.encodeWithSelector(InvalidTime.selector));
        spaOracle.updateDIAParams(80, 80);
    }

    function test_updateDIAParams() public useKnownActor(USDS_OWNER) {
        uint256 newWeight = 80;
        uint128 maxTime = 600;
        vm.expectEmit(true, true, true, true);
        emit DIAParamsUpdated(newWeight, maxTime);
        spaOracle.updateDIAParams(newWeight, maxTime);
        assertEq(spaOracle.weightDIA(), newWeight);
        assertEq(spaOracle.diaMaxTimeThreshold(), maxTime);
    }
}
