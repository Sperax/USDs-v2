// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import {LiquidityAmounts} from "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {IUniswapUtils} from "./interfaces/IUniswapUtils.sol";

contract UniswapUtils is IUniswapUtils {
    function getAmount0ForLiquidity(int24 tickLower, int24 tickUpper, uint128 liquidity)
        external
        pure
        override
        returns (uint256 amount0)
    {
        return LiquidityAmounts.getAmount0ForLiquidity(
            TickMath.getSqrtRatioAtTick(tickLower), TickMath.getSqrtRatioAtTick(tickUpper), liquidity
        );
    }

    function getAmount1ForLiquidity(int24 tickLower, int24 tickUpper, uint128 liquidity)
        external
        pure
        override
        returns (uint256 amount1)
    {
        return LiquidityAmounts.getAmount1ForLiquidity(
            TickMath.getSqrtRatioAtTick(tickLower), TickMath.getSqrtRatioAtTick(tickUpper), liquidity
        );
    }
}
