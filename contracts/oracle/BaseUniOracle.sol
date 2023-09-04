// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {ERC20} from "@openzeppelin/contracts_v3.4.2/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts_v3.4.2/access/Ownable.sol";
import {SafeMath} from "@openzeppelin/contracts_v3.4.2/math/SafeMath.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {OracleLibrary} from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";

interface IMasterPriceOracle {
    /// @notice Validates if price feed exists for a `_token`
    /// @param _token address of the desired token.
    /// @return Returns bool
    function priceFeedExists(address _token) external view returns (bool);

    /// @notice Gets the price feed for `_token`.
    /// @param _token address of the desired token.
    /// @dev Function reverts if the price feed does not exists.
    /// @return (uint256 price, uint256 precision).
    function getPrice(address _token) external view returns (uint256, uint256);
}

/// @title Base Uni Oracle contract of USDs protocol
/// @author Sperax Foundation
/// @notice Has all the base functionalities, variables etc to be implemented by child contracts
abstract contract BaseUniOracle is Ownable {
    using SafeMath for uint256;

    address public constant UNISWAP_FACTORY =
        0x1F98431c8aD98523631AE4a59f267346ea31F984;

    address public masterOracle; // Address of the master price oracle
    address public pool; // Address of the uniswap pool for the token and quoteToken
    address public quoteToken; // Address of the quoteToken
    uint32 public maPeriod; // Moving average period
    uint128 public quoteTokenPrecision; // QuoteToken price precision

    event MasterOracleUpdated(address newOracle);

    event UniMAPriceDataChanged(
        address quoteToken,
        uint24 feeTier,
        uint32 maPeriod
    );

    /// @notice A function to get price
    /// @return (uint256, uint256) Returns price and price precision
    function getPrice() external view virtual returns (uint256, uint256);

    /// @notice Updates the master price oracle
    /// @param _newOracle Address of the desired oracle
    function updateMasterOracle(address _newOracle) public onlyOwner {
        _isNonZeroAddr(_newOracle);
        masterOracle = _newOracle;
        require(
            IMasterPriceOracle(_newOracle).priceFeedExists(quoteToken),
            "Quote token feed missing"
        );
        emit MasterOracleUpdated(_newOracle);
    }

    /// @notice Configures the uniswap price feed for the `_token`
    /// @param _token Desired base token
    /// @param _quoteToken Token pair to get price Feed from
    /// @param _feeTier feeTier for the token pair
    /// @param _maPeriod moving average period
    function setUniMAPriceData(
        address _token,
        address _quoteToken,
        uint24 _feeTier,
        uint32 _maPeriod
    ) public onlyOwner {
        address uniOraclePool = IUniswapV3Factory(UNISWAP_FACTORY).getPool(
            _token,
            _quoteToken,
            _feeTier
        );
        require(uniOraclePool != address(0), "Feed unavailable");

        // Validate if the oracle has a price feed for the _quoteToken
        require(
            IMasterPriceOracle(masterOracle).priceFeedExists(_quoteToken),
            "Quote token feed missing"
        );

        pool = uniOraclePool;
        quoteToken = _quoteToken;
        quoteTokenPrecision = uint128(10) ** ERC20(quoteToken).decimals();
        maPeriod = _maPeriod;

        emit UniMAPriceDataChanged(_quoteToken, _feeTier, _maPeriod);
    }

    /// @notice Gets the quoteToken's price and pricePrecision
    /// @dev For a valid quote should have a configured price feed in the Master Oracle
    function _getQuoteTokenPrice() internal view returns (uint256, uint256) {
        return IMasterPriceOracle(masterOracle).getPrice(quoteToken);
    }

    /// @notice get the Uniswap V3 Moving Average (MA) of tokenBPerTokenA
    /// @param _tokenA is baseToken
    /// @dev e.g. for USDsPerSPA, _tokenA = SPA and tokenB = USDs
    /// @param _tokenAPrecision Token a decimal precision (18 decimals -> 1e18, 6 decimals -> 1e6 ... etc)
    /// @dev tokenBPerTokenA has the same precision as tokenB
    function _getUniMAPrice(
        address _tokenA,
        uint128 _tokenAPrecision
    ) internal view returns (uint256) {
        // get MA tick
        uint32 oldestObservationSecondsAgo = OracleLibrary
            .getOldestObservationSecondsAgo(pool);
        uint32 period = maPeriod < oldestObservationSecondsAgo
            ? maPeriod
            : oldestObservationSecondsAgo;
        (int24 timeWeightedAverageTick, ) = OracleLibrary.consult(pool, period);
        // get MA price from MA tick
        uint256 tokenBPerTokenA = OracleLibrary.getQuoteAtTick(
            timeWeightedAverageTick,
            _tokenAPrecision,
            _tokenA,
            quoteToken
        );
        return tokenBPerTokenA;
    }

    function _isNonZeroAddr(address _addr) internal pure {
        require(_addr != address(0), "Invalid Address");
    }
}
