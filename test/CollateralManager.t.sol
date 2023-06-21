// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {BaseTest} from "./BaseTest.sol";
import {CollateralManager} from "../contracts/vault/collateralManager.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract CollateralManagerTest is BaseTest {
    CollateralManager public manager;
}
