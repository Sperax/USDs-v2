//SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

interface IFeeCalculator {
    function getFeeIn(
        address _collateralAddr
    ) external view returns (uint256, uint256);

    function getFeeOut(
        address _collateralAddr
    ) external view returns (uint256, uint256);
}
