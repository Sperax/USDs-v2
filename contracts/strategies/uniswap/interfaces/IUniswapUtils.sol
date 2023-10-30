// SPDX-License-Identifier: MIT
pragma solidity >=0.6.12 <=0.8.16;

interface IUniswapUtils {
    function getAmount0ForLiquidity(int24 tickLower, int24 tickUpper, uint128 liquidity)
        external
        pure
        returns (uint256 amount0);

    function getAmount1ForLiquidity(int24 tickLower, int24 tickUpper, uint128 liquidity)
        external
        pure
        returns (uint256 amount0);
}
