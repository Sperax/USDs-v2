// SPDX-License-Identifier: MIT
pragma solidity >=0.6.12 <=0.8.16;

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

interface IUniswapUtils {
    function getAmountsForLiquidity(uint160 sqrtRatioX96, int24 _tickLower, int24 _tickUpper, uint128 _liquidity)
        external
        view
        returns (uint256 amount0, uint256 amount1);
}
