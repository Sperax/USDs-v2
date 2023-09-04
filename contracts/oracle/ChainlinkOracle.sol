// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title Chainlink Oracle contract of USDs protocol
/// @author Sperax Foundation
/// @notice Has all the base functionalities, variables etc to be implemented by child contracts
contract ChainlinkOracle is Ownable {
    struct TokenData {
        address priceFeed;
        uint256 pricePrecision;
    }

    struct SetupTokenData {
        address token;
        TokenData data;
    }

    address public constant CHAINLINK_SEQ_UPTIME_FEED =
        0xFdB631F5EE196F0ed6FAa767959853A9F217697D;
    uint256 private constant GRACE_PERIOD_TIME = 3600;

    mapping(address => TokenData) public getTokenData;

    event TokenDataChanged(
        address indexed tokenAddr,
        address priceFeed,
        uint256 pricePrecision
    );

    error TokenNotSupported(address token);
    error ChainlinkSequencerDown();
    error GracePeriodNotPassed(uint256 timeSinceUp);

    constructor(SetupTokenData[] memory _priceFeedData) {
        for (uint256 i = 0; i < _priceFeedData.length; ++i) {
            setTokenData(_priceFeedData[i].token, _priceFeedData[i].data);
        }
    }

    /// @notice Configures chainlink price feed for an asset
    /// @param _token Address of the desired token
    /// @param _tokenData Token price feed configuration
    function setTokenData(
        address _token,
        TokenData memory _tokenData
    ) public onlyOwner {
        getTokenData[_token] = _tokenData;
        emit TokenDataChanged(
            _token,
            _tokenData.priceFeed,
            _tokenData.pricePrecision
        );
    }

    /// @notice Gets the token price and price precision
    /// @param _token Address of the desired token
    /// @dev Ref: https://docs.chain.link/data-feeds/l2-sequencer-feeds
    /// @return (uint256, uint256) price and pricePrecision
    function getTokenPrice(
        address _token
    ) public view returns (uint256, uint256) {
        TokenData memory tokenInfo = getTokenData[_token];
        if (tokenInfo.pricePrecision == 0) revert TokenNotSupported(_token);

        (, int256 answer, uint256 startedAt, , ) = AggregatorV3Interface(
            CHAINLINK_SEQ_UPTIME_FEED
        ).latestRoundData();
        // Answer == 0: Sequencer is up
        // Answer == 1: Sequencer is down
        bool isSequencerUp = answer == 0;
        if (!isSequencerUp) revert ChainlinkSequencerDown();

        // Make sure the grace period has passed after the sequencer is back up.
        uint256 timeSinceUp = block.timestamp - startedAt;
        if (timeSinceUp <= GRACE_PERIOD_TIME)
            revert GracePeriodNotPassed(timeSinceUp);

        (, int256 price, , , ) = AggregatorV3Interface(tokenInfo.priceFeed)
            .latestRoundData();

        return (uint256(price), tokenInfo.pricePrecision);
    }
}
