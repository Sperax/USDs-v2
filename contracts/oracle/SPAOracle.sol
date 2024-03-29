// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;
pragma experimental ABIEncoderV2;

import {BaseUniOracle} from "./BaseUniOracle.sol";

interface IDiaOracle {
    function getValue(string memory key) external view returns (uint128 price, uint128 lastUpdateTime);
}

/// @title Oracle contract for USDs protocol for SPA token
/// @author Sperax Foundation
/// @dev providing SPA prices (from Uniswap V3 pools and DIA oracle)
contract SPAOracle is BaseUniOracle {
    address public constant SPA = 0x5575552988A3A80504bBaeB1311674fCFd40aD4B;
    address public constant DIA_ORACLE = 0x7919D08e0f41398cBc1e0A8950Df831e4895c19b;
    uint128 private constant SPA_PRECISION = 1e18;
    uint128 private constant SPA_PRICE_PRECISION = 1e8;
    uint256 private constant DIA_PRECISION = 1e8;
    uint256 public constant MAX_WEIGHT = 100;

    uint256 public weightDIA;
    uint256 public diaMaxTimeThreshold;

    // Events
    event DIAParamsUpdated(uint256 weightDIA, uint128 diaMaxTimeThreshold);

    // Custom error messages
    error PriceTooOld();
    error InvalidWeight();
    error InvalidTime();

    /// @notice Constructor of SPAOracle contract.
    /// @param _masterOracle Address of master oracle.
    /// @param _quoteToken Quote token's address.
    /// @param _feeTier Fee tier.
    /// @param _maPeriod Moving average period.
    /// @param _weightDIA DIA oracle's weight.
    constructor(address _masterOracle, address _quoteToken, uint24 _feeTier, uint32 _maPeriod, uint256 _weightDIA) {
        _isNonZeroAddr(_masterOracle);
        masterOracle = _masterOracle;
        setUniMAPriceData(SPA, _quoteToken, _feeTier, _maPeriod);
        updateDIAParams(_weightDIA, 86400);
    }

    /// @notice Get SPA price.
    /// @dev SPA price is a weighted combination of DIA SPA price and Uni SPA
    ///      price.
    /// @return uint256 (uint256, uint256) SPA price with precision SPA_PRICE_PRECISION.
    function getPrice() external view override returns (uint256, uint256) {
        uint256 weightUNI = MAX_WEIGHT - weightDIA;
        // calculate weighted UNI USDsPerSPA
        uint256 weightedSPAUniPrice = weightUNI * _getSPAUniPrice();

        // calculate weighted DIA USDsPerSPA
        (uint128 spaDiaPrice, uint128 lastUpdated) = IDiaOracle(DIA_ORACLE).getValue("SPA/USD");

        if (block.timestamp - lastUpdated > diaMaxTimeThreshold) {
            revert PriceTooOld();
        }

        uint256 weightedSPADiaPrice = weightDIA * spaDiaPrice;
        uint256 spaPrice = (weightedSPAUniPrice + weightedSPADiaPrice) / MAX_WEIGHT;
        return (spaPrice, SPA_PRICE_PRECISION);
    }

    /// @notice Update the weights of DIA SPA price and Uni SPA price.
    /// @dev SPA price is a weighted combination of DIA SPA price and Uni SPA
    ///     price.
    /// @dev `_weightDIA` = 70 and `_weightUNI` = 30 would result in a 70% and 30%
    ///     weights on SPA's final price.
    /// @param _weightDIA weight for DIA price feed.
    /// @param _maxTime max age of price feed from DIA.
    function updateDIAParams(uint256 _weightDIA, uint128 _maxTime) public onlyOwner {
        if (_weightDIA > MAX_WEIGHT) {
            revert InvalidWeight();
        }
        // 120 is the update frequency
        if (_maxTime <= 120) {
            revert InvalidTime();
        }

        weightDIA = _weightDIA;
        diaMaxTimeThreshold = _maxTime;
        emit DIAParamsUpdated(_weightDIA, _maxTime);
    }

    /// @notice Query SPA price according to a UniV3 SPA pool.
    /// @return uint256 SPA Uni price with precision DIA_PRECISION.
    function _getSPAUniPrice() private view returns (uint256) {
        uint256 quoteTokenAmtPerSPA = _getUniMAPrice(SPA, SPA_PRECISION);
        (uint256 quoteTokenPrice, uint256 quoteTokenPricePrecision) = _getQuoteTokenPrice();
        return ((quoteTokenPrice * quoteTokenAmtPerSPA * SPA_PRICE_PRECISION) / quoteTokenPrecision)
            / quoteTokenPricePrecision;
    }
}
