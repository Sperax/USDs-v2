pragma solidity 0.8.16;

/// @dev Oracle contract for fetching a certain token price
/// Centralization issue still exists when adopting this contract for global uses
/// For special uses of supporting built-in protocols only
interface IVstOracle {
    /// @dev returns current price data including price, round & time of last update
    function getPriceData()
        external
        view
        returns (
            uint256 _currentPrice,
            uint256 _lastPrice,
            uint256 _lastUpdate
        );
}

contract VSTOracle {
    address public constant PRICE_FEED =
        0x46bAc6210DcB43b4269ffe766f31B36267C41EdE;
    uint256 public constant VST_PRICE_PRECISION = 1e8;

    /// @notice Gets the price feed for vst
    function getPrice() external view returns (uint256 price, uint256) {
        (price, , ) = IVstOracle(PRICE_FEED).getPriceData();
        return (price, VST_PRICE_PRECISION);
    }
}
