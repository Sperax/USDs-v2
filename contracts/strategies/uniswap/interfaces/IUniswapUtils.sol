// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6;

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

interface IUniswapUtils {
    function fees(address positionManager, uint256 tokenId) external view returns (uint256 amount0, uint256 amount1);

    function getOldestObservationSecondsAgo(address pool) external view returns (uint32 secondsAgo);

    function consult(address pool, uint32 secondsAgo)
        external
        view
        returns (int24 arithmeticMeanTick, uint128 harmonicMeanLiquidity);

    function getQuoteAtTick(int24 tick, uint128 baseAmount, address baseToken, address quoteToken)
        external
        pure
        returns (uint256 quoteAmount);

    function getAmountsForLiquidity(uint160 sqrtRatioX96, int24 _tickLower, int24 _tickUpper, uint128 _liquidity)
        external
        pure
        returns (uint256 amount0, uint256 amount1);
}
