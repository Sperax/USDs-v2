// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {BaseTest} from "../utils/BaseTest.sol";
import {SPABuyback} from "../../contracts/buyback/SPABuyback.sol";
import {UpgradeUtil} from "../utils/UpgradeUtil.sol";
import {MasterPriceOracle} from "../../contracts/oracle/MasterPriceOracle.sol";
import {IOracle} from "../../contracts/interfaces/IOracle.sol";

contract BuybackTestSetup is BaseTest {
    SPABuyback internal spaBuyback;
    SPABuyback internal spaBuybackImpl;
    UpgradeUtil internal upgradeUtil;
    IOracle.PriceData internal usdsData;
    IOracle.PriceData internal spaData;

    address internal constant VESPA_REWARDER =
        0x2CaB3abfC1670D1a452dF502e216a66883cDf079;
    uint256 internal constant MAX_PERCENTAGE = 10000;
    uint256 internal rewardPercentage;
    uint256 internal minUSDsOut;
    uint256 internal spaIn;

    modifier mockOracle() {
        vm.mockCall(
            address(ORACLE),
            abi.encodeWithSignature("getPrice(address)", USDS),
            abi.encode(995263234350000000, 1e18)
        );
        vm.mockCall(
            address(ORACLE),
            abi.encodeWithSignature("getPrice(address)", SPA),
            abi.encode(4729390000000000, 1e18)
        );
        _;
        vm.clearMockedCalls();
    }

    function setUp() public virtual override {
        super.setUp();
        address proxy;
        setArbitrumFork();
        rewardPercentage = 5000; // 50%
        vm.startPrank(USDS_OWNER);
        spaBuybackImpl = new SPABuyback();
        upgradeUtil = new UpgradeUtil();
        proxy = upgradeUtil.deployErc1967Proxy(address(spaBuybackImpl));
        spaBuyback = SPABuyback(proxy);

        spaBuyback.initialize(VESPA_REWARDER, rewardPercentage);
        vm.stopPrank();
    }

    function _calculateUSDsForSpaIn(uint256 _spaIn) internal returns (uint256) {
        usdsData = IOracle(ORACLE).getPrice(USDS);
        spaData = IOracle(ORACLE).getPrice(SPA);
        uint256 totalSpaValue = (_spaIn * spaData.price) / spaData.precision;
        return ((totalSpaValue * usdsData.precision) / usdsData.price);
    }

    function _calculateSpaReqdForUSDs(
        uint256 _usdsAmount
    ) internal returns (uint256) {
        usdsData = IOracle(ORACLE).getPrice(USDS);
        spaData = IOracle(ORACLE).getPrice(SPA);
        uint256 totalUSDsValue = (_usdsAmount * usdsData.price) /
            usdsData.precision;
        return (totalUSDsValue * spaData.precision) / spaData.price;
    }
}
