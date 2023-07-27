// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {FlagsInterface} from "@chainlink/contracts/src/v0.8/interfaces/FlagsInterface.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract ChainlinkOracle is Ownable {
    struct TokenData {
        address tokenAddr;
        address priceFeed;
        uint256 pricePrecision;
    }

    address public constant CHAINLINK_SEQ_UPTIME_FEED =
        0xFdB631F5EE196F0ed6FAa767959853A9F217697D;
    uint256 private constant GRACE_PERIOD_TIME = 3600;

    address private constant FLAG_ARBITRUM_SEQ_OFFLINE =
        address(
            bytes20(
                bytes32(
                    uint256(keccak256("chainlink.flags.arbitrum-seq-offline")) -
                        1
                )
            )
        );
    mapping(address => TokenData) public getTokenData;

    event TokenDataChanged(
        address indexed tokenAddr,
        address priceFeed,
        uint256 pricePrecision
    );

    constructor(TokenData[] memory _priceFeedData) {
        for (uint256 i = 0; i < _priceFeedData.length; ++i) {
            setTokenData(_priceFeedData[i]);
        }
    }

    /// @notice Configures chainlink price feed for an asset
    /// @param _tokenData Token price feed configuration
    function setTokenData(TokenData memory _tokenData) public onlyOwner {
        getTokenData[_tokenData.tokenAddr] = _tokenData;
        emit TokenDataChanged(
            _tokenData.tokenAddr,
            _tokenData.priceFeed,
            _tokenData.pricePrecision
        );
    }

    /// @notice Gets the token price and price precision
    /// @param _token Address of the desired token
    function getTokenPrice(
        address _token
    ) public view returns (uint256, uint256) {
        TokenData memory collateralInfo = getTokenData[_token];
        require(collateralInfo.pricePrecision != 0, "Collateral not supported");

        (, int256 answer, uint256 startedAt, , ) = AggregatorV3Interface(
            CHAINLINK_SEQ_UPTIME_FEED
        ).latestRoundData();

        // Answer == 0: Sequencer is up
        // Answer == 1: Sequencer is down
        bool isSequencerUp = answer == 0;
        if (!isSequencerUp) {
            revert("Chainlink sequencer down");
        }

        // Make sure the grace period has passed after the sequencer is back up.
        uint256 timeSinceUp = block.timestamp - startedAt;
        if (timeSinceUp <= GRACE_PERIOD_TIME) {
            revert("Chainlink sequencer down");
        }

        (, int256 price, , , ) = AggregatorV3Interface(collateralInfo.priceFeed)
            .latestRoundData();

        return (uint256(price), collateralInfo.pricePrecision);
    }
}
