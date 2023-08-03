// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {BaseUniOracle} from "./BaseUniOracle.sol";

interface IDiaOracle {
    function getValue(
        string memory key
    ) external view returns (uint128, uint128);
}

/// @title Oracle contract of USDs protocol
/// @dev providing SPA prices (from Uniswap V3 pools and DIA oracle)
/// @author Sperax Inc
contract SPAOracle is BaseUniOracle {
    address public constant SPA = 0x5575552988A3A80504bBaeB1311674fCFd40aD4B;
    address public constant DIA_ORACLE =
        0x7919D08e0f41398cBc1e0A8950Df831e4895c19b;
    uint128 private constant SPA_PRICE_PRECISION = 1e18;
    uint256 private constant DIA_PRECISION = 1e8;
    uint256 public constant MAX_WEIGHT = 100;

    uint256 public weightDIA;

    event DIAWeightUpdated(uint256 weightDIA);

    constructor(
        address _masterOracle,
        address _quoteToken,
        uint24 _feeTier,
        uint32 _maPeriod,
        uint256 _weightDIA
    ) public {
        _isNonZeroAddr(_masterOracle);
        masterOracle = _masterOracle;
        setUniMAPriceData(SPA, _quoteToken, _feeTier, _maPeriod);
        updateDIAWeight(_weightDIA);
    }

    /// @notice Get SPA price
    /// @dev SPA price is a weighted combination of DIA SPA price and Uni SPA
    ///      price
    /// @return uint256 SPA price with precision SPA_PRICE_PRECISION (10^18)
    function getPrice() external view override returns (uint256, uint256) {
        uint256 weightUNI = MAX_WEIGHT - weightDIA;
        // calculate weighted UNI USDsPerSPA
        uint256 weightedSPAUniPrice = weightUNI.mul(_getSPAUniPrice());

        // calculate weighted DIA USDsPerSPA
        (uint128 spaDiaPrice, ) = IDiaOracle(DIA_ORACLE).getValue("SPA/USD");
        uint256 weightedSPADiaPrice = weightDIA.mul(spaDiaPrice);
        uint256 spaPrice = weightedSPAUniPrice.add(weightedSPADiaPrice).div(
            MAX_WEIGHT
        );
        spaPrice = spaPrice.mul(SPA_PRICE_PRECISION).div(DIA_PRECISION);
        return (spaPrice, SPA_PRICE_PRECISION);
    }

    /// @notice Update the weights of DIA SPA price and Uni SPA price
    /// @dev SPA price is a weighted combination of DIA SPA price and Uni SPA
    ///     price
    /// @dev _weightDIA = 70 and _weightUNI = 30 would result in a 70% and 30%
    ///     weights on SPA's final price
    function updateDIAWeight(uint256 _weightDIA) public onlyOwner {
        require(_weightDIA <= MAX_WEIGHT, "Invalid weight");
        weightDIA = _weightDIA;
        emit DIAWeightUpdated(_weightDIA);
    }

    /// @notice Query SPA price according to a UniV3 SPA pool
    /// @return uint256 SPA Uni price with precision DIA_PRECISION
    function _getSPAUniPrice() private view returns (uint256) {
        uint256 quoteTokenAmtPerSPA = _getUniMAPrice(SPA, SPA_PRICE_PRECISION);
        (
            uint256 quoteTokenPrice,
            uint256 quoteTokenPricePrecision
        ) = _getQuoteTokenPrice();
        return
            quoteTokenPrice
                .mul(quoteTokenAmtPerSPA)
                .mul(DIA_PRECISION)
                .div(quoteTokenPrecision)
                .div(quoteTokenPricePrecision);
    }
}
