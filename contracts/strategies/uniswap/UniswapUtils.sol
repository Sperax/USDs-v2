// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import {IUniswapUtils, IUniswapV3Pool} from "./interfaces/IUniswapUtils.sol";
import {LiquidityAmounts} from "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";

contract UniswapUtils is IUniswapUtils {
    function getAmountsForLiquidity(uint160 sqrtRatioX96, int24 _tickLower, int24 _tickUpper, uint128 _liquidity)
        external
        view
        override
        returns (uint256 amount0, uint256 amount1)
    {
        return LiquidityAmounts.getAmountsForLiquidity(
            sqrtRatioX96, TickMath.getSqrtRatioAtTick(_tickLower), TickMath.getSqrtRatioAtTick(_tickUpper), _liquidity
        );
    }
}
