// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {PreMigrationSetup} from "../utils/DeploymentSetup.sol";
import {IAccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/IAccessControlUpgradeable.sol";

contract VaultCoreTest is PreMigrationSetup {
    function setUp() public virtual override {
        super.setUp();
    }
}

contract TestInit is VaultCoreTest {
    function testInitialization() public {
        assertTrue(address(VAULT) != address(0), "Vault not deployed");
        assertTrue(IAccessControlUpgradeable(VAULT).hasRole(0x00, USDS_OWNER));
    }
}
