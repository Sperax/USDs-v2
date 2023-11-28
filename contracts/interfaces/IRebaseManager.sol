//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IRebaseManager {
    function fetchRebaseAmt() external returns (uint256);

    function getMinAndMaxRebaseAmt() external view returns (uint256, uint256);
}
