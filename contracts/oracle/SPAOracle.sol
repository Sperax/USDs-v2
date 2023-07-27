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
    uint128 private constant SPA_PRICE_PRECISION = 1e18;
    uint256 private constant DIA_PRECISION = 1e8;

    address diaOracle;
    uint256 weightDIA;

    event DIAConfigUpdated(address diaOracle, uint256 weightDIA);

    constructor(
        address _masterOracle,
        address _diaOracle,
        address _quoteToken,
        uint24 _feeTier,
        uint32 _maPeriod,
        uint256 _weightDIA
    ) public {
        masterOracle = _masterOracle;
        setUniMAPriceData(SPA, _quoteToken, _feeTier, _maPeriod);
        updateDIAConfig(_diaOracle, _weightDIA);
    }

    /// @notice Get SPA price
    /// @dev SPA price is a weighted combination of DIA SPA price and Uni SPA
    ///      price
    /// @return uint256 SPA price with precision SPA_PRICE_PRECISION (10^18)
    function getPrice() external view override returns (uint256, uint256) {
        uint256 weightUNI = 100 - weightDIA;
        // calculate weighted UNI USDsPerSPA
        uint256 weightedSPAUniPrice = weightUNI.mul(_getSPAUniPrice());

        // calculate weighted DIA USDsPerSPA
        (uint128 spaDiaPrice, ) = IDiaOracle(diaOracle).getValue("SPA/USD");
        uint256 weightedSPADiaPrice = weightDIA.mul(spaDiaPrice);
        uint256 spaPrice = weightedSPAUniPrice.add(weightedSPADiaPrice).div(
            100
        );
        spaPrice = spaPrice.mul(SPA_PRICE_PRECISION).div(DIA_PRECISION);
        return (spaPrice, SPA_PRICE_PRECISION);
    }

    /// @notice Update the weights of DIA SPA price and Uni SPA price
    /// @dev SPA price is a weighted combination of DIA SPA price and Uni SPA
    ///     price
    /// @dev _weightDIA = 70 and _weightUNI = 30 would result in a 70% and 30%
    ///     weights on SPA's final price
    function updateDIAConfig(
        address _diaOracle,
        uint256 _weightDIA
    ) public onlyOwner {
        require(_weightDIA <= 100, "Invalid weights");
        diaOracle = _diaOracle;
        weightDIA = _weightDIA;
        emit DIAConfigUpdated(_diaOracle, _weightDIA);
    }

    /// @notice Query SPA price according to a UniV3 SPA pool
    /// @return uint256 SPA Uni price with precision DIA_PRECISION
    function _getSPAUniPrice() private view returns (uint256) {
        require(pool != address(0), "SPA price unavailable");
        uint256 quoteTokenAmtPerSPA = _getUniMAPrice(
            SPA,
            quoteToken,
            SPA_PRICE_PRECISION
        );
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
