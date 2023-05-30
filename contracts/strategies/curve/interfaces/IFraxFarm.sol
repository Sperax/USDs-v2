// SPDX-License-Identifier: GPL-2.0-or-later
// https://github.com/FraxFinance/frax-solidity/blob/master/src/hardhat/contracts/Staking/Variants/FraxCCFarmV2_ArbiCurveVSTFRAX.sol
// https://github.com/FraxFinance/frax-solidity/blob/master/src/hardhat/contracts/Staking/FraxCrossChainFarmV2.sol
// https://arbiscan.io/address/0x127963a74c07f72d862f2bdc225226c3251bd117
pragma solidity 0.8.18;

interface IFraxFarm {
    /* ========== STRUCTS ========== */

    struct LockedStake {
        bytes32 kek_id;
        uint256 start_timestamp;
        uint256 liquidity;
        uint256 ending_timestamp;
        uint256 lock_multiplier; // 6 decimals of precision. 1x = 1000000
    }

    function lockAdditional(bytes32 kek_id, uint256 addl_liq) external;

    function stakeLocked(uint256 liquidity, uint256 secs) external;

    function withdrawLocked(bytes32 kek_id) external;

    function getReward() external returns (uint256, uint256);

    function rewardsToken0() external view returns (address);

    function rewardsToken1() external view returns (address);

    function lock_time_min() external view returns (uint256);

    function lockedLiquidityOf(address account) external view returns (uint256);

    function lockedStakes(
        address account,
        uint256 index
    ) external view returns (LockedStake memory);

    function lockedStakesOf(
        address account
    ) external view returns (LockedStake[] memory);

    function earned(address account) external view returns (uint256, uint256);
}
