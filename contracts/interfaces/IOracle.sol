pragma solidity 0.8.18;

interface IOracle {
    struct PriceData {
        uint256 price;
        uint256 precision;
    }

    /// @notice Gets the price feed for `_token`.
    /// @param _token address of the desired token.
    /// @dev Function reverts if the price feed does not exists.
    /// @return (uint256 price, uint256 precision).
    function getPrice(address _token) external view returns (PriceData memory);
}
