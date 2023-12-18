// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IOracle} from "../interfaces/IOracle.sol";

/// @title Master Price Oracle for USDs protocol
/// @author Sperax Foundation
/// @notice Communicates with different price feeds to get the price
contract MasterPriceOracle is Ownable, IOracle {
    // Handles price feed data for a give token.
    mapping(address => PriceFeedData) public tokenPriceFeed;

    event PriceFeedUpdated(address indexed token, address indexed source, bytes msgData);
    event PriceFeedRemoved(address indexed token);

    error UnableToFetchPriceFeed(address token);
    error InvalidPriceFeed(address token);
    error PriceFeedNotFound(address token);

    /// @notice Update/Add price feed for `_token`
    /// @param _token address of the desired token.
    /// @dev Have to be extra cautious while updating the price feed.
    /// @param _source price feed source.
    /// @param _data call data for fetching the price feed.
    function updateTokenPriceFeed(address _token, address _source, bytes memory _data) external onlyOwner {
        // Validate if the price feed is being emitted correctly.
        _getPriceFeed(_token, _source, _data);

        tokenPriceFeed[_token] = PriceFeedData(_source, _data);
        emit PriceFeedUpdated(_token, _source, _data);
    }

    /// @notice Remove an existing price feed for `token`.
    /// @param _token Address of the token.
    function removeTokenPriceFeed(address _token) external onlyOwner {
        if (tokenPriceFeed[_token].source == address(0)) {
            revert PriceFeedNotFound(_token);
        }
        delete tokenPriceFeed[_token];
        emit PriceFeedRemoved(_token);
    }

    /// @inheritdoc IOracle
    function getPrice(address _token) external view returns (PriceData memory) {
        PriceFeedData memory data = tokenPriceFeed[_token];
        return _getPriceFeed(_token, data.source, data.msgData);
    }

    /// @inheritdoc IOracle
    function priceFeedExists(address _token) external view returns (bool) {
        if (tokenPriceFeed[_token].source == address(0)) return false;
        return true;
    }

    /// @notice Gets the price feed for a `_token` given the feed data.
    /// @param _token address of the desired token.
    /// @param _source price feed source.
    /// @param _msgData call data for fetching feed.
    /// @return priceData (uint256 price, uint256 precision).
    function _getPriceFeed(address _token, address _source, bytes memory _msgData)
        private
        view
        returns (PriceData memory priceData)
    {
        if (_source == address(0)) revert InvalidPriceFeed(_token);
        (bool success, bytes memory response) = _source.staticcall(_msgData);
        if (success) {
            priceData = abi.decode(response, (PriceData));
            return priceData;
        }
        revert UnableToFetchPriceFeed(_token);
    }
}
