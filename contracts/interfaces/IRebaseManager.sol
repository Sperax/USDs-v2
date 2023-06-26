//SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

interface IRebaseManager {
    function updateLastRebaseTS() external;

    function fetchRebaseAmt() external returns (uint256);
}
