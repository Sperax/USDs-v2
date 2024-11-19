// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {IERC20, ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {BaseStrategy} from "./BaseStrategy.t.sol";
import {BaseTest} from "../utils/BaseTest.sol";
import {UpgradeUtil} from "../utils/UpgradeUtil.sol";
import {FluidStrategy} from "../../contracts/strategies/fluid/FluidStrategy.sol";
import {IfToken} from "../../contracts/strategies/fluid/interfaces/IfToken.sol";
import {console} from "forge-std/console.sol";

contract FluidStrategyTest is BaseStrategy, BaseTest {
    FluidStrategy internal strategy;
    FluidStrategy internal impl;
    UpgradeUtil internal upgradeUtil;
    address internal proxyAddress;
    uint256 internal depositAmount;
    uint256 internal interestAmount;
    address internal ASSET;
    address internal P_TOKEN;

    struct AssetData {
        string name;
        address asset;
        address pToken;
    }

    AssetData[] public data;

    function setUp() public virtual override {
        super.setUp();
        setArbitrumFork();

        vm.startPrank(USDS_OWNER);
        impl = new FluidStrategy();
        upgradeUtil = new UpgradeUtil();
        proxyAddress = upgradeUtil.deployErc1967Proxy(address(impl));
        strategy = FluidStrategy(proxyAddress);
        vm.stopPrank();
        _configAsset();
        ASSET = data[0].asset;
        P_TOKEN = data[0].pToken;
        depositAmount = 100 * 10 ** ERC20(ASSET).decimals();
        interestAmount = 10 * 10 ** ERC20(ASSET).decimals();
    }

    function _initializeStrategy() internal {
        strategy.initialize({_vault: VAULT, _depositSlippage: uint16(0), _withdrawSlippage: uint16(0)});
    }

    function _configAsset() internal {
        data.push(
            AssetData({
                name: "USDT",
                asset: 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9,
                pToken: 0x4A03F37e7d3fC243e3f99341d36f4b829BEe5E03
            })
        );
        data.push(
            AssetData({
                name: "USDC",
                asset: 0xaf88d065e77c8cC2239327C5EDb3A432268e5831,
                pToken: 0x1A996cb54bb95462040408C06122D45D6Cdb6096
            })
        );
    }

    function _setAssetData() internal {
        for (uint8 i = 0; i < data.length; ++i) {
            strategy.setPTokenAddress(data[i].asset, data[i].pToken);
        }
    }

    function testUnit() public {
        _initializeStrategy();
        _setAssetData();
    }
}
