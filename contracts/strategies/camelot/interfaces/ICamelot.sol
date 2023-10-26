// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

interface IRouter {
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);

    function getPair(address tokenA, address tokenB) external view returns (address pair);

    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) external pure returns (uint256 amountB);
}

interface IPositionHelper {
    function addLiquidityAndCreatePosition(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        uint256 deadline,
        address to,
        address nftPool,
        uint256 lockDuration
    ) external;
}

interface IPair {
    function getReserves()
        external
        view
        returns (uint112 _reserve0, uint112 _reserve1, uint16 _token0FeePercent, uint16 _token1FeePercent);

    function totalSupply() external view returns (uint256);
}

interface INFTPool {
    function addToPosition(uint256 tokenId, uint256 amountToAdd) external;

    function withdrawFromPosition(uint256 tokenId, uint256 amountToWithdraw) external;

    function harvestPositionTo(uint256 tokenId, address to) external;

    function pendingRewards(uint256 tokenId) external view returns (uint256);

    function getStakingPosition(uint256 tokenId)
        external
        view
        returns (
            uint256 amount,
            uint256 amountWithMultiplier,
            uint256 startLockTime,
            uint256 lockDuration,
            uint256 lockMultiplier,
            uint256 rewardDebt,
            uint256 boostPoints,
            uint256 totalMultiplier
        );

    function getPoolInfo()
        external
        view
        returns (
            address lpToken,
            address grailToken,
            address xGrailToken,
            uint256 lastRewardTime,
            uint256 accRewardsPerShare,
            uint256 lpSupply,
            uint256 lpSupplyWithMultiplier,
            uint256 allocPoint
        );
}

interface INFTHandler is IERC721Receiver {
    function onNFTHarvest(address operator, address to, uint256 tokenId, uint256 grailAmount, uint256 xGrailAmount)
        external
        returns (bool);
    function onNFTAddToPosition(address operator, uint256 tokenId, uint256 lpAmount) external returns (bool);
    function onNFTWithdraw(address operator, uint256 tokenId, uint256 lpAmount) external returns (bool);
}
