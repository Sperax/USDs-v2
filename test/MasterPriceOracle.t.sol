// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {BaseTest} from "./utils/BaseTest.sol";
import {MasterPriceOracle} from "../contracts/oracle/MasterPriceOracle.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface ITestOracle {
    function getSPAprice() external view returns (uint256);
}

contract MasterPriceOracleTest is BaseTest {
    MasterPriceOracle public oracle;
    address public constant SPA_ORACLE =
        0xf3f98086f7B61a32be4EdF8d8A4b964eC886BBcd;

    // Events from the actual contract.
    event PriceFeedUpdated(
        address indexed token,
        address indexed source,
        bytes msgData
    );
    event PriceFeedRemoved(address indexed token);

    function setUp() public override {
        super.setUp();
        setArbitrumFork();
        oracle = new MasterPriceOracle();
        oracle.transferOwnership(USDS_OWNER);
    }

    function test_revertsWhen_unAuthorizedUpdate() public useActor(0) {
        vm.expectRevert("Ownable: caller is not the owner");
        oracle.updateTokenPriceFeed(
            SPA,
            address(this),
            abi.encode(this.dummyPrice.selector)
        );
    }

    function test_revertsWhen_unAuthorizedRemoveRequest() public useActor(0) {
        vm.expectRevert("Ownable: caller is not the owner");
        oracle.removeTokenPriceFeed(SPA);
    }

    function test_revertsWhen_removingNonExistingFeed()
        public
        useKnownActor(USDS_OWNER)
    {
        vm.expectRevert(
            abi.encodeWithSelector(
                MasterPriceOracle.PriceFeedNotFound.selector,
                SPA
            )
        );
        oracle.removeTokenPriceFeed(SPA);
    }

    function test_updateTokenPriceFeed() public useKnownActor(USDS_OWNER) {
        address token = SPA;
        address source = address(this);
        bytes memory data = abi.encode(this.dummyPrice.selector);
        vm.expectEmit(true, true, false, true);
        emit PriceFeedUpdated(SPA, source, data);
        oracle.updateTokenPriceFeed(token, source, data);
    }

    function test_getPriceFeed() public useKnownActor(USDS_OWNER) {
        oracle.updateTokenPriceFeed(
            SPA,
            address(this),
            abi.encode(this.dummySPAPrice.selector)
        );
        MasterPriceOracle.PriceData memory data = oracle.getPrice(SPA);
        assertEqUint(data.price, 1e7);
        assertEqUint(data.precision, 1e8);
    }

    function test_removeTokenPriceFeed() public useKnownActor(USDS_OWNER) {
        oracle.updateTokenPriceFeed(
            SPA,
            address(this),
            abi.encode(this.dummyPrice.selector)
        );

        vm.expectEmit(true, false, false, false);
        emit PriceFeedRemoved(SPA);
        oracle.removeTokenPriceFeed(SPA);
    }

    function test_revertsWhen_invalidPriceFeed()
        public
        useKnownActor(USDS_OWNER)
    {
        vm.expectRevert(
            abi.encodeWithSelector(
                MasterPriceOracle.InvalidPriceFeed.selector,
                SPA
            )
        );
        oracle.updateTokenPriceFeed(
            SPA,
            address(0),
            abi.encode(this.dummyPrice.selector)
        );
    }

    function test_revertsWhen_feedNotFetched()
        public
        useKnownActor(USDS_OWNER)
    {
        vm.expectRevert(
            abi.encodeWithSelector(
                MasterPriceOracle.UnableToFetchPriceFeed.selector,
                SPA
            )
        );
        oracle.updateTokenPriceFeed(
            SPA,
            address(this),
            abi.encode(this.dummyInvalidPriceFeed.selector)
        );
    }

    function dummyPrice() public view returns (uint256 price, uint256 prec) {
        prec = 1e8;
        price = ITestOracle(SPA_ORACLE).getSPAprice();
    }

    function dummySPAPrice() public pure returns (uint256 price, uint256 prec) {
        prec = 1e8;
        price = 1e7;
    }

    function dummyInvalidPriceFeed() public pure returns (uint256) {
        revert("Invalid Price feed");
    }
}
