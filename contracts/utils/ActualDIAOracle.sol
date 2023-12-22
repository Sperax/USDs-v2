// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract ActualDIAOracle is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private _oracleUpdaters;

    mapping(string => uint256) public values;

    event OracleUpdate(string key, uint128 value, uint128 timestamp);
    event UpdaterAddressChange(address newUpdater);

    constructor() {
        _oracleUpdaters.add(msg.sender);
    }

    function addUpdater(address oracleUpdaterAddress) external onlyOwner {
        _oracleUpdaters.add(oracleUpdaterAddress);
    }

    function removeUpdater(address oracleUpdaterAddress) external onlyOwner {
        _oracleUpdaters.remove(oracleUpdaterAddress);
    }

    function setValue(string memory key, uint128 value, uint128 timestamp) external {
        require(_oracleUpdaters.contains(msg.sender), "not a updater");
        uint256 cValue = (((uint256)(value)) << 128) + timestamp;
        values[key] = cValue;
        emit OracleUpdate(key, value, timestamp);
    }

    function getValue(string memory key) external view returns (uint128, uint128) {
        uint256 cValue = values[key];
        uint128 timestamp = (uint128)(cValue % 2 ** 128);
        uint128 value = (uint128)(cValue >> 128);
        return (value, timestamp);
    }
}
