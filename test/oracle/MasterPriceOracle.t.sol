// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {BaseTest} from "../utils/BaseTest.sol";
import {MasterPriceOracle} from "../../contracts/oracle/MasterPriceOracle.sol";
import {SPAOracle} from "../../contracts/oracle/SPAOracle.sol";
import {USDsOracle} from "../../contracts/oracle/USDsOracle.sol";
import {ChainlinkOracle} from "../../contracts/oracle/ChainlinkOracle.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface ICustomOracle {
    function updateDIAParams(uint256 _weightDIA, uint128 _maxTime) external;

    function getPrice() external view returns (uint256, uint256);
}

contract MasterPriceOracleTest is BaseTest {
    struct PriceFeedData {
        address token;
        address source;
        bytes msgData;
    }

    address constant USDCe_PRICE_FEED = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;
    address constant FRAX_PRICE_FEED = 0x0809E3d38d1B4214958faf06D8b1B1a2b73f2ab8;
    address constant DAI_PRICE_FEED = 0xc5C8E77B397E531B8EC06BFb0048328B30E9eCfB;
    uint96 constant TOKEN_DATA_TIMEOUT = 25 hours;
    uint256 constant TOKEN_DATA_PRECISION = 1e8;
    uint24 constant SPA_ORACLE_USDCe_FEE_TIER = 10000;
    uint24 constant USDs_ORACLE_USDCe_FEE_TIER = 500;
    uint32 constant USDCe_MA_PERIOD = 600;
    uint256 constant USDCe_WEIGHT_DIA = 70;
    uint128 constant DIA_MAX_TIME_THRESHOLD = type(uint128).max;
    uint256 constant DUMMY_PRICE = 1e7;
    uint256 constant DUMMY_PREC = 1e8;

    MasterPriceOracle public masterOracle;
    ChainlinkOracle public chainlinkOracle;
    address spaOracle;
    address usdsOracle;

    // Events from the actual contract.
    event PriceFeedUpdated(address indexed token, address indexed source, bytes msgData);
    event PriceFeedRemoved(address indexed token);

    function setUp() public virtual override {
        super.setUp();
        setArbitrumFork();
        vm.startPrank(USDS_OWNER);
        masterOracle = new MasterPriceOracle();

        // @dev Deploy and configure all the underlying oracles
        deployAndConfigureChainlink();
        // A pre-requisite for initializing SPA and USDs oracles
        masterOracle.updateTokenPriceFeed(
            USDCe, address(chainlinkOracle), abi.encodeWithSelector(ChainlinkOracle.getTokenPrice.selector, USDCe)
        );
        spaOracle = address(
            new SPAOracle(address(masterOracle), USDCe, SPA_ORACLE_USDCe_FEE_TIER, USDCe_MA_PERIOD, USDCe_WEIGHT_DIA)
        );
        ICustomOracle(spaOracle).updateDIAParams(USDCe_WEIGHT_DIA, DIA_MAX_TIME_THRESHOLD);

        usdsOracle = address(new USDsOracle(address(masterOracle), USDCe, USDs_ORACLE_USDCe_FEE_TIER, USDCe_MA_PERIOD));
        vm.stopPrank();
    }

    function dummyPrice() public view returns (uint256 price, uint256 prec) {
        (price, prec) = ICustomOracle(spaOracle).getPrice();
    }

    function dummySPAPrice() public pure returns (uint256 price, uint256 prec) {
        prec = DUMMY_PREC;
        price = DUMMY_PRICE;
    }

    function dummyInvalidPriceFeed() public pure returns (uint256) {
        revert("Invalid Price feed");
    }

    function deployAndConfigureChainlink() private {
        ChainlinkOracle.SetupTokenData[] memory chainlinkFeeds = new ChainlinkOracle.SetupTokenData[](3);
        chainlinkFeeds[0] = ChainlinkOracle.SetupTokenData(
            USDCe, ChainlinkOracle.TokenData(USDCe_PRICE_FEED, TOKEN_DATA_TIMEOUT, TOKEN_DATA_PRECISION)
        );
        chainlinkFeeds[1] = ChainlinkOracle.SetupTokenData(
            FRAX, ChainlinkOracle.TokenData(FRAX_PRICE_FEED, TOKEN_DATA_TIMEOUT, TOKEN_DATA_PRECISION)
        );
        chainlinkFeeds[2] = ChainlinkOracle.SetupTokenData(
            DAI, ChainlinkOracle.TokenData(DAI_PRICE_FEED, TOKEN_DATA_TIMEOUT, TOKEN_DATA_PRECISION)
        );
        chainlinkOracle = new ChainlinkOracle(chainlinkFeeds);
    }

    function getPriceFeedConfig() internal view returns (PriceFeedData[] memory) {
        PriceFeedData[] memory feedData = new PriceFeedData[](4);
        feedData[0] = PriceFeedData(
            FRAX, address(chainlinkOracle), abi.encodeWithSelector(ChainlinkOracle.getTokenPrice.selector, FRAX)
        );
        feedData[1] = PriceFeedData(
            DAI, address(chainlinkOracle), abi.encodeWithSelector(ChainlinkOracle.getTokenPrice.selector, DAI)
        );
        feedData[2] = PriceFeedData(SPA, spaOracle, abi.encodeWithSelector(ICustomOracle.getPrice.selector));
        feedData[3] = PriceFeedData(USDS, usdsOracle, abi.encodeWithSelector(ICustomOracle.getPrice.selector));
        return feedData;
    }
}

contract UpdateTokenPriceFeed is MasterPriceOracleTest {
    address token;
    address source;
    bytes msgData;

    function setUp() public virtual override {
        super.setUp();

        token = SPA;
        source = address(this);
        msgData = abi.encode(this.dummyPrice.selector);
    }

    function test_RevertWhen_NotOwner() public useActor(0) {
        vm.expectRevert("Ownable: caller is not the owner");
        masterOracle.updateTokenPriceFeed(token, source, msgData);
    }

    function test_RevertWhen_InvalidPriceFeed() public useKnownActor(USDS_OWNER) {
        vm.expectRevert(abi.encodeWithSelector(MasterPriceOracle.InvalidPriceFeed.selector, token));
        masterOracle.updateTokenPriceFeed(token, address(0), msgData);
    }

    function test_RevertWhen_UnableToFetchPriceFeed() public useKnownActor(USDS_OWNER) {
        vm.expectRevert(abi.encodeWithSelector(MasterPriceOracle.UnableToFetchPriceFeed.selector, token));
        masterOracle.updateTokenPriceFeed(token, source, abi.encode(this.dummyInvalidPriceFeed.selector));
    }

    function test_updateTokenPriceFeed() public useKnownActor(USDS_OWNER) {
        PriceFeedData[] memory priceFeeds = getPriceFeedConfig();
        for (uint8 i = 0; i < priceFeeds.length; ++i) {
            assertEq(masterOracle.priceFeedExists(priceFeeds[i].token), false);

            vm.expectEmit(address(masterOracle));
            emit PriceFeedUpdated(priceFeeds[i].token, priceFeeds[i].source, priceFeeds[i].msgData);
            masterOracle.updateTokenPriceFeed(priceFeeds[i].token, priceFeeds[i].source, priceFeeds[i].msgData);

            assertEq(masterOracle.priceFeedExists(priceFeeds[i].token), true);
            (address _source, bytes memory _msgData) = masterOracle.tokenPriceFeed(priceFeeds[i].token);
            assertEq(_source, priceFeeds[i].source);
            assertEq(_msgData, priceFeeds[i].msgData);

            MasterPriceOracle.PriceData memory data = masterOracle.getPrice(priceFeeds[i].token);
            (bool success, bytes memory actualData) = address(priceFeeds[i].source).call(priceFeeds[i].msgData);

            if (success) {
                (uint256 actualPrice, uint256 actualPrecision) = abi.decode(actualData, (uint256, uint256));
                assertEq(data.price, actualPrice);
                assertEq(data.precision, actualPrecision);
            } else {
                assert(false);
            }
        }
    }

    function test_getPriceFeed() public useKnownActor(USDS_OWNER) {
        masterOracle.updateTokenPriceFeed(token, source, abi.encode(this.dummySPAPrice.selector));
        MasterPriceOracle.PriceData memory data = masterOracle.getPrice(token);
        assertEqUint(data.price, DUMMY_PRICE);
        assertEqUint(data.precision, DUMMY_PREC);
    }
}

contract RemoveTokenPriceFeed is MasterPriceOracleTest {
    address token;
    address source;
    bytes msgData;

    function setUp() public virtual override {
        super.setUp();

        token = SPA;
        source = address(this);
        msgData = abi.encode(this.dummyPrice.selector);
    }

    function test_RevertWhen_NotOwner() public useActor(0) {
        vm.expectRevert("Ownable: caller is not the owner");
        masterOracle.removeTokenPriceFeed(token);
    }

    function test_RevertWhen_PriceFeedNotFound() public useKnownActor(USDS_OWNER) {
        vm.expectRevert(abi.encodeWithSelector(MasterPriceOracle.PriceFeedNotFound.selector, token));
        masterOracle.removeTokenPriceFeed(token);
    }

    function test_removeTokenPriceFeed() public useKnownActor(USDS_OWNER) {
        masterOracle.updateTokenPriceFeed(token, source, msgData);

        vm.expectEmit(address(masterOracle));
        emit PriceFeedRemoved(token);
        masterOracle.removeTokenPriceFeed(token);

        assertEq(masterOracle.priceFeedExists(token), false);
        (address _source, bytes memory _msgData) = masterOracle.tokenPriceFeed(token);
        assertEq(_source, address(0));
        assertEq(_msgData, bytes(""));
    }
}
