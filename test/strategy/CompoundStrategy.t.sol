// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {BaseStrategy} from "./BaseStrategy.t.sol";
import {BaseTest} from "../utils/BaseTest.sol";
import {UpgradeUtil} from "../utils/UpgradeUtil.sol";
import {CompoundStrategy} from "../../contracts/strategies/compound/CompoundStrategy.sol";
import {IERC20, ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract CompoundStrategyTest is BaseStrategy, BaseTest {

    struct AssetData {
        string name;
        address asset;
        address pToken;
        uint256 intLiqThreshold;
    }

    AssetData[] public data;

    CompoundStrategy internal strategy;
    CompoundStrategy internal impl;
    UpgradeUtil internal upgradeUtil;
    uint256 internal depositAmount;
    address internal proxyAddress;
    address internal ASSET;
    address internal P_TOKEN;
    address internal constant REWARD_POOL = 0x88730d254A2f7e6AC8388c3198aFd694bA9f7fae;


    function setUp() public virtual override {
        super.setUp();
        setArbitrumFork();
        vm.startPrank(USDS_OWNER);
        impl = new CompoundStrategy();
        upgradeUtil = new UpgradeUtil();
        proxyAddress = upgradeUtil.deployErc1967Proxy(address(impl));

        strategy = CompoundStrategy(proxyAddress);
        _configAsset();
        ASSET = data[0].asset;
        P_TOKEN = data[0].pToken;
        depositAmount = 1 * 10 ** ERC20(ASSET).decimals();
        vm.stopPrank();
    }

    function _initializeStrategy() internal {
        strategy.initialize(REWARD_POOL, VAULT);
    }

    function _deposit() internal {
        changePrank(VAULT);
        deal(address(ASSET), VAULT, depositAmount);
        IERC20(ASSET).approve(address(strategy), depositAmount);
        strategy.deposit(ASSET, 1);
        changePrank(USDS_OWNER);
    }

    function _setAssetData() internal {
        for (uint8 i = 0; i < data.length; ++i) {
            strategy.setPTokenAddress(
                data[i].asset,
                data[i].pToken,
                data[i].intLiqThreshold
            );
        }
    }

    function _configAsset() internal {
        data.push(
            AssetData({
                name: "USDC.e",
                asset: 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8,
                pToken: 0xA5EDBDD9646f8dFF606d7448e414884C7d905dCA,
                intLiqThreshold: 0
            })
        );
    }

    function _mockInsufficientAsset() internal {
        vm.startPrank(strategy.assetToPToken(ASSET));
        IERC20(ASSET).transfer(
            actors[0],
            IERC20(ASSET).balanceOf(strategy.assetToPToken(ASSET))
        );
        vm.stopPrank();
    }
}

contract InitializeTests is CompoundStrategyTest {
    function setUp() public override {
        super.setUp();
        vm.startPrank(USDS_OWNER);
        _initializeStrategy();
        _setAssetData();
        _deposit();
        _mockInsufficientAsset();
    }

    function testInit() public {
        assertTrue(strategy.vault() != address(0));
    }
}
 