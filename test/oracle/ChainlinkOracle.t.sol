pragma solidity 0.8.16;

import {ChainlinkOracle, AggregatorV3Interface} from "../../contracts/oracle/ChainlinkOracle.sol";

import {BaseTest} from "../utils/BaseTest.sol";

contract ChainlinkOracleTest is BaseTest {
    ChainlinkOracle public chainlinkOracle;

    event TokenDataChanged(
        address indexed tokenAddr,
        address priceFeed,
        uint256 pricePrecision
    );

    function setUp() public virtual override {
        super.setUp();
        setArbitrumFork();
        vm.prank(USDS_OWNER);
        chainlinkOracle = new ChainlinkOracle(
            new ChainlinkOracle.SetupTokenData[](0)
        );
    }

    function _getTokenData()
        internal
        pure
        returns (ChainlinkOracle.SetupTokenData[] memory)
    {
        ChainlinkOracle.SetupTokenData[]
            memory chainlinkFeeds = new ChainlinkOracle.SetupTokenData[](3);
        chainlinkFeeds[0] = ChainlinkOracle.SetupTokenData(
            USDCe,
            ChainlinkOracle.TokenData(
                0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3,
                1e8
            )
        );
        chainlinkFeeds[1] = ChainlinkOracle.SetupTokenData(
            FRAX,
            ChainlinkOracle.TokenData(
                0x0809E3d38d1B4214958faf06D8b1B1a2b73f2ab8,
                1e8
            )
        );
        chainlinkFeeds[2] = ChainlinkOracle.SetupTokenData(
            DAI,
            ChainlinkOracle.TokenData(
                0xc5C8E77B397E531B8EC06BFb0048328B30E9eCfB,
                1e8
            )
        );
        return chainlinkFeeds;
    }
}

contract Test_SetTokenData is ChainlinkOracleTest {
    function test_revertsWhen_notOwner() public {
        ChainlinkOracle.SetupTokenData memory tokenData = _getTokenData()[0];
        vm.expectRevert("Ownable: caller is not the owner");
        chainlinkOracle.setTokenData(tokenData.token, tokenData.data);
    }

    function test_setTokenData() public useKnownActor(USDS_OWNER) {
        ChainlinkOracle.SetupTokenData memory tokenData = _getTokenData()[0];
        vm.expectEmit(true, true, true, true);
        emit TokenDataChanged(
            tokenData.token,
            tokenData.data.priceFeed,
            tokenData.data.pricePrecision
        );
        chainlinkOracle.setTokenData(tokenData.token, tokenData.data);

        (address priceFeed, uint256 precision) = chainlinkOracle.getTokenData(
            tokenData.token
        );
        assertEq(priceFeed, tokenData.data.priceFeed);
        assertEq(precision, tokenData.data.pricePrecision);
    }
}

contract Test_GetTokenPrice is ChainlinkOracleTest {
    function setUp() public override {
        super.setUp();
        vm.startPrank(USDS_OWNER);
        ChainlinkOracle.SetupTokenData[] memory setupData = _getTokenData();
        for (uint8 i = 0; i < setupData.length; ++i) {
            chainlinkOracle.setTokenData(setupData[i].token, setupData[i].data);
        }
        vm.stopPrank();
    }

    function test_revertsWhen_unSupportedCollateral() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ChainlinkOracle.TokenNotSupported.selector,
                USDS
            )
        );
        chainlinkOracle.getTokenPrice(USDS);
    }

    function test_revertsWhen_sequencerDown() public {
        (
            uint80 roundId,
            ,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = AggregatorV3Interface(chainlinkOracle.CHAINLINK_SEQ_UPTIME_FEED())
                .latestRoundData();

        vm.mockCall(
            chainlinkOracle.CHAINLINK_SEQ_UPTIME_FEED(),
            abi.encodeWithSignature("latestRoundData()"),
            abi.encode(roundId, 1, startedAt, updatedAt, answeredInRound)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ChainlinkOracle.ChainlinkSequencerDown.selector
            )
        );
        chainlinkOracle.getTokenPrice(USDCe);
    }

    function test_revertsWhen_gracePeriodNotPassed() public {
        (
            uint80 roundId,
            ,
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = AggregatorV3Interface(chainlinkOracle.CHAINLINK_SEQ_UPTIME_FEED())
                .latestRoundData();

        vm.mockCall(
            chainlinkOracle.CHAINLINK_SEQ_UPTIME_FEED(),
            abi.encodeWithSignature("latestRoundData()"),
            abi.encode(
                roundId,
                0,
                block.timestamp - 1000,
                updatedAt,
                answeredInRound
            )
        );
        (, , uint256 startedAt, , ) = AggregatorV3Interface(
            0xFdB631F5EE196F0ed6FAa767959853A9F217697D
        ).latestRoundData();
        vm.expectRevert(
            abi.encodeWithSelector(
                ChainlinkOracle.GracePeriodNotPassed.selector,
                block.timestamp - startedAt
            )
        );
        chainlinkOracle.getTokenPrice(USDCe);
    }

    function test_getTokenPrice() public {
        ChainlinkOracle.TokenData memory usdcData = _getTokenData()[0].data;
        (uint256 price, uint256 precision) = chainlinkOracle.getTokenPrice(
            USDCe
        );
        assertEq(precision, usdcData.pricePrecision);
        assertGt(price, 0);
    }
}
