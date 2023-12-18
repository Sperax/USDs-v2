// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

struct Position {
    uint96 nonce;
    address operator;
    address token0;
    address token1;
    uint24 fee;
    int24 tickLower;
    int24 tickUpper;
    uint128 liquidity;
    uint256 feeGrowthInside0LastX128;
    uint256 feeGrowthInside1LastX128;
    uint128 tokensOwed0;
    uint128 tokensOwed1;
}

interface INonfungiblePositionManagerUtils {
    function positions(address positionManager, uint256 tokenId) external view returns (Position memory position);
}
