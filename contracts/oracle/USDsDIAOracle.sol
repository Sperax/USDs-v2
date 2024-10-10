// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface IDiaOracle {
    function getValue(string memory key) external view returns (uint128 price, uint128 lastUpdateTime);
}

/// @title Oracle contract for USDs protocol for USDs token
/// @author Sperax Foundation
/// @dev providing USDs prices DIA oracle
contract USDsDIAOracle is Ownable {
    address public constant DIA_ORACLE = 0x7919D08e0f41398cBc1e0A8950Df831e4895c19b;
    uint256 private constant DIA_PRECISION = 1e8;

    uint256 public diaMaxTimeThreshold;

    // Events
    event DIAParamsUpdated(uint128 diaMaxTimeThreshold);

    // Custom error messages
    error PriceTooOld();
    error InvalidTime();

    /// @notice Constructor of USDsDIAOracle contract.
    constructor() {
        diaMaxTimeThreshold = 86400; // 1 day
    }

    /// @notice Get USDs price.
    /// @return uint256 (uint256, uint256) USDS price with precision.
    function getPrice() external view returns (uint256, uint256) {
        (uint128 usdsPrice, uint128 lastUpdated) = IDiaOracle(DIA_ORACLE).getValue("USDS/USD");
        if (block.timestamp - lastUpdated > diaMaxTimeThreshold) {
            revert PriceTooOld();
        }

        return (usdsPrice, DIA_PRECISION);
    }

    /// @notice Update the weights of DIA USDs price and Uni USDs price.
    /// @param _maxTime max age of price feed from DIA.
    function updateDIAParams(uint128 _maxTime) public onlyOwner {
        // 120 is the update frequency
        if (_maxTime <= 120) {
            revert InvalidTime();
        }
        diaMaxTimeThreshold = _maxTime;
        emit DIAParamsUpdated(_maxTime);
    }
}
