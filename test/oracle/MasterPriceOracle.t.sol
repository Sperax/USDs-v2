// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {BaseTest} from "../utils/BaseTest.t.sol";
import {MasterPriceOracle} from "../../contracts/oracle/MasterPriceOracle.sol";
import {ChainlinkOracle} from "../../contracts/oracle/ChainlinkOracle.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// import {console} from "forge-std/console.sol";

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

    MasterPriceOracle public masterOracle;
    ChainlinkOracle public chainlinkOracle;
    address spaOracle;
    address usdsOracle;

    // Events from the actual contract.
    event PriceFeedUpdated(address indexed token, address indexed source, bytes msgData);
    event PriceFeedRemoved(address indexed token);

    function setUp() public override {
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
        spaOracle = deployCode("SPAOracle.sol:SPAOracle", abi.encode(address(masterOracle), USDCe, 10000, 600, 70));

        ICustomOracle(spaOracle).updateDIAParams(70, type(uint128).max);

        usdsOracle = deployCode("USDsOracle.sol", abi.encode(address(masterOracle), USDCe, 500, 600));
        vm.stopPrank();
    }

    function test_revertsWhen_unAuthorizedUpdate() public useActor(0) {
        vm.expectRevert("Ownable: caller is not the owner");
        masterOracle.updateTokenPriceFeed(SPA, address(this), abi.encode(this.dummyPrice.selector));
    }

    function test_revertsWhen_unAuthorizedRemoveRequest() public useActor(0) {
        vm.expectRevert("Ownable: caller is not the owner");
        masterOracle.removeTokenPriceFeed(SPA);
    }

    function test_revertsWhen_removingNonExistingFeed() public useKnownActor(USDS_OWNER) {
        vm.expectRevert(abi.encodeWithSelector(MasterPriceOracle.PriceFeedNotFound.selector, SPA));
        masterOracle.removeTokenPriceFeed(SPA);
    }

    function test_updateTokenPriceFeed() public useKnownActor(USDS_OWNER) {
        PriceFeedData[] memory priceFeeds = getPriceFeedConfig();
        for (uint8 i = 0; i < priceFeeds.length; ++i) {
            vm.expectEmit(true, true, false, true);
            emit PriceFeedUpdated(priceFeeds[i].token, priceFeeds[i].source, priceFeeds[i].msgData);
            masterOracle.updateTokenPriceFeed(priceFeeds[i].token, priceFeeds[i].source, priceFeeds[i].msgData);
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
        masterOracle.updateTokenPriceFeed(SPA, address(this), abi.encode(this.dummySPAPrice.selector));
        MasterPriceOracle.PriceData memory data = masterOracle.getPrice(SPA);
        assertEqUint(data.price, 1e7);
        assertEqUint(data.precision, 1e8);
    }

    function test_removeTokenPriceFeed() public useKnownActor(USDS_OWNER) {
        masterOracle.updateTokenPriceFeed(SPA, address(this), abi.encode(this.dummyPrice.selector));

        vm.expectEmit(true, false, false, false);
        emit PriceFeedRemoved(SPA);
        masterOracle.removeTokenPriceFeed(SPA);
    }

    function test_revertsWhen_invalidPriceFeed() public useKnownActor(USDS_OWNER) {
        vm.expectRevert(abi.encodeWithSelector(MasterPriceOracle.InvalidPriceFeed.selector, SPA));
        masterOracle.updateTokenPriceFeed(SPA, address(0), abi.encode(this.dummyPrice.selector));
    }

    function test_revertsWhen_feedNotFetched() public useKnownActor(USDS_OWNER) {
        vm.expectRevert(abi.encodeWithSelector(MasterPriceOracle.UnableToFetchPriceFeed.selector, SPA));
        masterOracle.updateTokenPriceFeed(SPA, address(this), abi.encode(this.dummyInvalidPriceFeed.selector));
    }

    function dummyPrice() public view returns (uint256 price, uint256 prec) {
        (price, prec) = ICustomOracle(spaOracle).getPrice();
    }

    function dummySPAPrice() public pure returns (uint256 price, uint256 prec) {
        prec = 1e8;
        price = 1e7;
    }

    function dummyInvalidPriceFeed() public pure returns (uint256) {
        revert("Invalid Price feed");
    }

    function deployAndConfigureChainlink() private {
        ChainlinkOracle.SetupTokenData[] memory chainlinkFeeds = new ChainlinkOracle.SetupTokenData[](3);
        chainlinkFeeds[0] = ChainlinkOracle.SetupTokenData(
            USDCe, ChainlinkOracle.TokenData(0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3, 25 hours, 1e8)
        );
        chainlinkFeeds[1] = ChainlinkOracle.SetupTokenData(
            FRAX, ChainlinkOracle.TokenData(0x0809E3d38d1B4214958faf06D8b1B1a2b73f2ab8, 25 hours, 1e8)
        );
        chainlinkFeeds[2] = ChainlinkOracle.SetupTokenData(
            DAI, ChainlinkOracle.TokenData(0xc5C8E77B397E531B8EC06BFb0048328B30E9eCfB, 25 hours, 1e8)
        );
        chainlinkOracle = new ChainlinkOracle(chainlinkFeeds);
    }

    function getPriceFeedConfig() private view returns (PriceFeedData[] memory) {
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
