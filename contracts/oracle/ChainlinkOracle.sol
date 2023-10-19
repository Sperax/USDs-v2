// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title Chainlink Oracle contract for USDs protocol
/// @notice This contract provides functionality for obtaining price data from Chainlink's price feeds for various assets.
/// @author Sperax Foundation
contract ChainlinkOracle is Ownable {
    // Struct to store price feed and precision information for each token
    struct TokenData {
        address priceFeed; // Address of the Chainlink price feed
        uint256 pricePrecision; // Precision factor for the token's price
    }

    // Struct to set up token data during contract deployment
    struct SetupTokenData {
        address token; // Address of the token
        TokenData data; // Token price feed configuration
    }

    // Address of Chainlink's sequencer uptime feed
    address public constant CHAINLINK_SEQ_UPTIME_FEED = 0xFdB631F5EE196F0ed6FAa767959853A9F217697D;

    // Grace period time in seconds
    uint256 private constant GRACE_PERIOD_TIME = 3600;

    // Mapping to store price feed and precision data for each supported token
    mapping(address => TokenData) public getTokenData;

    // Events
    event TokenDataChanged(address indexed tokenAddr, address priceFeed, uint256 pricePrecision);

    // Custom error messages
    error TokenNotSupported(address token);
    error ChainlinkSequencerDown();
    error GracePeriodNotPassed(uint256 timeSinceUp);

    /// @notice Constructor to set up initial token data during contract deployment
    /// @param _priceFeedData Array of token setup data containing token addresses and price feed configurations
    constructor(SetupTokenData[] memory _priceFeedData) {
        for (uint256 i; i < _priceFeedData.length;) {
            setTokenData(_priceFeedData[i].token, _priceFeedData[i].data);
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Configures Chainlink price feed for an asset
    /// @param _token Address of the desired token
    /// @param _tokenData Token price feed configuration
    /// @dev Only the contract owner can call this function
    function setTokenData(address _token, TokenData memory _tokenData) public onlyOwner {
        getTokenData[_token] = _tokenData;
        emit TokenDataChanged(_token, _tokenData.priceFeed, _tokenData.pricePrecision);
    }

    /// @notice Gets the price and price precision of a supported token
    /// @param _token Address of the desired token
    /// @dev Ref: https://docs.chain.link/data-feeds/l2-sequencer-feeds
    /// @return (uint256, uint256) The token's price and its price precision
    function getTokenPrice(address _token) public view returns (uint256, uint256) {
        TokenData memory tokenInfo = getTokenData[_token];

        // Check if the token is supported
        if (tokenInfo.pricePrecision == 0) revert TokenNotSupported(_token);

        // Retrieve the latest data from Chainlink's sequencer uptime feed.
        (, int256 answer, uint256 startedAt,,) = AggregatorV3Interface(CHAINLINK_SEQ_UPTIME_FEED).latestRoundData();

        // Answer == 0: Sequencer is up
        // Answer == 1: Sequencer is down
        bool isSequencerUp = answer == 0;
        if (!isSequencerUp) revert ChainlinkSequencerDown();

        // Ensure the grace period has passed since the sequencer is back up.
        uint256 timeSinceUp = block.timestamp - startedAt;
        if (timeSinceUp <= GRACE_PERIOD_TIME) {
            revert GracePeriodNotPassed(timeSinceUp);
        }

        // Retrieve the latest price data for the token from its Chainlink price feed.
        (, int256 price,,,) = AggregatorV3Interface(tokenInfo.priceFeed).latestRoundData();

        return (uint256(price), tokenInfo.pricePrecision);
    }
}
