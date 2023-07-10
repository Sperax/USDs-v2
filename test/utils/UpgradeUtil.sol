//SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.16;

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract UpgradeUtil {
    TransparentUpgradeableProxy public proxy;
    ProxyAdmin public proxyAdmin;

    function deployErc1967Proxy(address impl) public returns (address) {
        proxyAdmin = new ProxyAdmin();
        proxy = new TransparentUpgradeableProxy(impl, address(proxyAdmin), "");
        return address(proxy);
    }
}
