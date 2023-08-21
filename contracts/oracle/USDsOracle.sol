// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {BaseUniOracle} from "./BaseUniOracle.sol";

/// @title Oracle contract of USDs protocol
/// @dev providing USDs prices (from Uniswap V3 pools)
/// @author Sperax Inc
contract USDsOracle is BaseUniOracle {
    address public constant USDS = 0xD74f5255D557944cf7Dd0E45FF521520002D5748;
    uint128 private constant USDS_PRECISION = 1e18;
    uint128 private constant USDS_PRICE_PRECISION = 1e8;

    constructor(
        address _masterOracle,
        address _quoteToken,
        uint24 _feeTier,
        uint32 _maPeriod
    ) public {
        _isNonZeroAddr(_masterOracle);
        masterOracle = _masterOracle;
        setUniMAPriceData(USDS, _quoteToken, _feeTier, _maPeriod);
    }

    /// @notice Gets the USDs price from chainlink
    function getPrice() external view override returns (uint256, uint256) {
        uint256 quoteTokenAmtPerUSDs = _getUniMAPrice(USDS, USDS_PRECISION);
        (
            uint256 quoteTokenPrice,
            uint256 quoteTokenPricePrecision
        ) = _getQuoteTokenPrice();
        uint256 usdsPrice = quoteTokenPrice
            .mul(quoteTokenAmtPerUSDs)
            .mul(USDS_PRICE_PRECISION)
            .div(quoteTokenPrecision)
            .div(quoteTokenPricePrecision);
        return (usdsPrice, USDS_PRICE_PRECISION);
    }
}
