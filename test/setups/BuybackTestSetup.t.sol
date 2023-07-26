// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {BaseTest} from "../utils/BaseTest.sol";
import {SPABuyback} from "../../contracts/buyback/SPABuyback.sol";
import {UpgradeUtil} from "../utils/UpgradeUtil.sol";

contract BuybackTestSetup is BaseTest {
    SPABuyback internal spaBuyback;
    SPABuyback internal spaBuybackImpl;
    UpgradeUtil internal upgradeUtil;

    address internal constant VESPA_REWARDER =
        0x2CaB3abfC1670D1a452dF502e216a66883cDf079;
    uint256 internal constant MAX_PERCENTAGE = 10000;
    uint256 internal rewardPercentage;

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
}
