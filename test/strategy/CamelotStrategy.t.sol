// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {PreMigrationSetup} from "../utils/DeploymentSetup.sol";
import {CamelotStrategy} from "../../contracts/strategies/camelot/CamelotStrategy.sol";

contract CamelotStrategyTestSetup is PreMigrationSetup {
    CamelotStrategy internal camelotStrategy;

    function setUp() public virtual override {
        super.setUp();
        CamelotStrategy.StrategyData memory _sData = CamelotStrategy.StrategyData({
            tokenA: USDT,
            tokenB: USDCe,
            router: 0xc873fEcbd354f5A56E00E710B90EF4201db2448d,
            positionHelper: 0xe458018Ad4283C90fB7F5460e24C4016F81b8175,
            factory: 0x6EcCab422D763aC031210895C81787E87B43A652,
            nftPool: 0xcC9f28dAD9b85117AB5237df63A5EE6fC50B02B7
        });
        vm.startPrank(USDS_OWNER);
        CamelotStrategy camelotStrategyImpl = new CamelotStrategy();
        address camelotStrategyProxy = upgradeUtil.deployErc1967Proxy(address(camelotStrategyImpl));
        camelotStrategy = CamelotStrategy(camelotStrategyProxy);
        camelotStrategy.initialize(_sData, VAULT, 100, 100);
        vm.stopPrank();
    }
}

contract TestInitialization is CamelotStrategyTestSetup {
    CamelotStrategy private camelotStrategy2;
    CamelotStrategy private camelotStrategyImpl2;

    function setUp() public override {
        super.setUp();
        vm.startPrank(USDS_OWNER);
        camelotStrategyImpl2 = new CamelotStrategy();
        address camelotStrategyProxy2 = upgradeUtil.deployErc1967Proxy(address(camelotStrategyImpl2));
        camelotStrategy2 = CamelotStrategy(camelotStrategyProxy2);
        vm.stopPrank();
    }

    function initializeStrategy() private useKnownActor(USDS_OWNER) {
        CamelotStrategy.StrategyData memory _sData = CamelotStrategy.StrategyData({
            tokenA: USDT,
            tokenB: USDCe,
            router: 0xc873fEcbd354f5A56E00E710B90EF4201db2448d,
            positionHelper: 0xe458018Ad4283C90fB7F5460e24C4016F81b8175,
            factory: 0x6EcCab422D763aC031210895C81787E87B43A652,
            nftPool: 0xcC9f28dAD9b85117AB5237df63A5EE6fC50B02B7
        });
        camelotStrategy2.initialize(_sData, VAULT, 100, 100);
    }

    function testImplementationInitialization() public {
        initializeStrategy();
        assertTrue(camelotStrategyImpl2.vault() == address(0));
        assertTrue(camelotStrategyImpl2.withdrawSlippage() == 0);
        assertTrue(camelotStrategyImpl2.depositSlippage() == 0);
        assertTrue(camelotStrategyImpl2.owner() == address(0));
    }

    function testInitialization() public {
        initializeStrategy();
        assertTrue(camelotStrategy2.vault() == VAULT);
        assertTrue(camelotStrategy2.withdrawSlippage() == 100);
        assertTrue(camelotStrategy2.depositSlippage() == 100);
        assertTrue(camelotStrategy2.owner() == USDS_OWNER);
        assertTrue(camelotStrategy2.supportsCollateral(USDCe));
        assertTrue(camelotStrategy2.supportsCollateral(USDT));
    }

    function testInitializationTwice() public {
        initializeStrategy();
        CamelotStrategy.StrategyData memory _sData = CamelotStrategy.StrategyData({
            tokenA: USDT,
            tokenB: USDCe,
            router: 0xc873fEcbd354f5A56E00E710B90EF4201db2448d,
            positionHelper: 0xe458018Ad4283C90fB7F5460e24C4016F81b8175,
            factory: 0x6EcCab422D763aC031210895C81787E87B43A652,
            nftPool: 0xcC9f28dAD9b85117AB5237df63A5EE6fC50B02B7
        });
        vm.expectRevert("Initializable: contract is already initialized");
        vm.prank(USDS_OWNER);
        camelotStrategy2.initialize(_sData, VAULT, 100, 100);
    }
}

contract AllocateTest is CamelotStrategyTestSetup {}
