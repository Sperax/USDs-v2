//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IDripper {
    function collect() external returns (uint256);

    function getCollectableAmt() external view returns (uint256);
}
