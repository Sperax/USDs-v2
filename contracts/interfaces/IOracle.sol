// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IOracle {
    struct PriceData {
        uint256 price;
        uint256 precision;
    }

    struct PriceFeedData {
        address source;
        bytes msgData;
    }

    /// @notice Validates if price feed exists for a `_token`
    /// @param _token address of the desired token.
    /// @return bool if price feed exists.
    /// @dev Function reverts if price feed not set.
    function priceFeedExists(address _token) external view returns (bool);

    /// @notice Gets the price feed for `_token`.
    /// @param _token address of the desired token.
    /// @return (uint256 price, uint256 precision).
    /// @dev Function reverts if the price feed does not exists.
    function getPrice(address _token) external view returns (PriceData memory);
}
