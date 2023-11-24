// SPDX-License-Identifier: UNLICENSED
/* solhint-disable */
pragma solidity 0.8.19;

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

// @note This file is only for facilitating contract imports for brownie script

contract PA is ProxyAdmin {}

contract TUP is TransparentUpgradeableProxy {
    constructor(address _logic, address admin_, bytes memory _data)
        payable
        TransparentUpgradeableProxy(_logic, admin_, _data)
    {}
}
