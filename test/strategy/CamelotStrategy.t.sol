// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {console} from "forge-std/console.sol";
import {PreMigrationSetup} from "../utils/DeploymentSetup.sol";
import {CamelotStrategy} from "../../contracts/strategies/camelot/CamelotStrategy.sol";
import {InitializableAbstractStrategy, Helpers} from "../../contracts/strategies/InitializableAbstractStrategy.sol";
import {IERC20, ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

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

contract DepositTest is TestInitialization {
    function test_Deposit_Assets_To_Strategy() public {
        address assetA = USDT;
        address assetB = USDCe;
        uint256 depositAmountAssetA = 1 * 1000 ** ERC20(assetA).decimals();
        uint256 depositAmountAssetB = 1 * 1000 ** ERC20(assetB).decimals();

        uint256 currentAmountAssetA = IERC20(assetA).balanceOf(address(camelotStrategy));
        uint256 currentAmountAssetB = IERC20(assetB).balanceOf(address(camelotStrategy));

        vm.startPrank(VAULT);

        deal(address(USDT), VAULT, depositAmountAssetA);
        deal(address(USDCe), VAULT, depositAmountAssetB);

        IERC20(USDT).approve(address(camelotStrategy), depositAmountAssetA);
        IERC20(USDCe).approve(address(camelotStrategy), depositAmountAssetB);

        camelotStrategy.deposit(assetA, depositAmountAssetA);
        camelotStrategy.deposit(assetB, depositAmountAssetB);

        vm.stopPrank();

        assert(IERC20(assetA).balanceOf(address(camelotStrategy)) == currentAmountAssetA + depositAmountAssetA);
        assert(IERC20(assetB).balanceOf(address(camelotStrategy)) == currentAmountAssetB + depositAmountAssetB);
    }
}

contract AllocateTest is TestInitialization {
    error InvalidAmount();
    error CollateralNotSupported(address asset);

    function _depositAssetsToStrategy() internal {
        address assetA = USDT;
        address assetB = USDCe;
        uint256 depositAmountAssetA = 1000 * 10 ** ERC20(assetA).decimals();
        uint256 depositAmountAssetB = 1000 * 10 ** ERC20(assetB).decimals();

        vm.startPrank(VAULT);

        deal(address(USDT), VAULT, depositAmountAssetA);
        deal(address(USDCe), VAULT, depositAmountAssetB);

        IERC20(USDT).approve(address(camelotStrategy), depositAmountAssetA);
        IERC20(USDCe).approve(address(camelotStrategy), depositAmountAssetB);

        camelotStrategy.deposit(assetA, depositAmountAssetA);
        camelotStrategy.deposit(assetB, depositAmountAssetB);

        vm.stopPrank();
    }

    function test_Revert_When_Caller_Not_Owner() public {
        address randomCaller = address(0x1);

        vm.startPrank(randomCaller);

        vm.expectRevert("Ownable: caller is not the owner");
        camelotStrategy.allocate([USDT, USDCe], [uint256(1000), uint256(1000)]);

        vm.stopPrank();
    }

    function test_Revert_When_Unsupported_Collateral() public {
        address randomTokenAddress = address(0x2);

        vm.startPrank(USDS_OWNER);

        vm.expectRevert(abi.encodeWithSelector(CollateralNotSupported.selector, randomTokenAddress));
        camelotStrategy.allocate([randomTokenAddress, randomTokenAddress], [uint256(1000), uint256(1000)]);

        vm.expectRevert(abi.encodeWithSelector(CollateralNotSupported.selector, randomTokenAddress));
        camelotStrategy.allocate([randomTokenAddress, USDCe], [uint256(1000), uint256(1000)]);

        vm.expectRevert(abi.encodeWithSelector(CollateralNotSupported.selector, randomTokenAddress));
        camelotStrategy.allocate([USDT, randomTokenAddress], [uint256(1000), uint256(1000)]);

        vm.stopPrank();
    }

    function test_Revert_When_Amount_Zero() public {
        vm.startPrank(USDS_OWNER);

        vm.expectRevert(InvalidAmount.selector);
        camelotStrategy.allocate([USDT, USDCe], [uint256(0), uint256(0)]);

        vm.expectRevert(InvalidAmount.selector);
        camelotStrategy.allocate([USDT, USDCe], [uint256(1000), uint256(0)]);

        vm.expectRevert(InvalidAmount.selector);
        camelotStrategy.allocate([USDT, USDCe], [uint256(0), uint256(1000)]);

        vm.stopPrank();
    }

    // This function fails. Couldnot allocate funds.
    function test_Allocation() public {
        _depositAssetsToStrategy();

        uint256 amountAssetA = 1000 * 10 ** ERC20(USDT).decimals();
        uint256 amountAssetB = 1000 * 10 ** ERC20(USDCe).decimals();

        (amountAssetA, amountAssetB) = camelotStrategy.getDepositAmounts(amountAssetA, amountAssetB);

        emit log_named_uint("amountAActual", amountAssetA);
        emit log_named_uint("amountBActual", amountAssetB);

        // uint256 minAmountAssetA = amountAssetA - (amountAssetA * camelotStrategy.depositSlippage() / Helpers.MAX_PERCENTAGE);
        // uint256 minAmountAssetB = amountAssetB - (amountAssetB * camelotStrategy.depositSlippage() / Helpers.MAX_PERCENTAGE);

        vm.prank(USDS_OWNER);
        camelotStrategy.allocate([USDT, USDCe], [uint256(amountAssetA), uint256(amountAssetB)]);
        vm.stopPrank();
    }

    // function test_Calculate_Deposit_Amounts_Before_Allocation() public {
    //     uint amountADesired = 100 * 10 ** ERC20(USDT).decimals();
    //     uint amountBDesired = 100 * 10 ** ERC20(USDCe).decimals();
    //     (uint amountA, uint amountB) = camelotStrategy.getDepositAmounts( amountADesired, amountBDesired);
    // }
}

contract RedeemTest is TestInitialization {}

contract updateStrategyDataTest is TestInitialization {
    function test_Update_Strategy_Data() public {
        CamelotStrategy.StrategyData memory _newStrategyData = CamelotStrategy.StrategyData({
            tokenA: USDT,
            tokenB: USDCe,
            router: 0xc873fEcbd354f5A56E00E710B90EF4201db2448d,
            positionHelper: 0xe458018Ad4283C90fB7F5460e24C4016F81b8175,
            factory: 0x6EcCab422D763aC031210895C81787E87B43A652,
            nftPool: 0xcC9f28dAD9b85117AB5237df63A5EE6fC50B02B7
        });

        vm.startPrank(USDS_OWNER);
        camelotStrategy.updateStrategyData(_newStrategyData);
        vm.stopPrank();

        (address _tokenA, address _tokenB, address _router, address _positionHelper, address _factory, address _nftPool)
        = camelotStrategy.strategyData();

        CamelotStrategy.StrategyData memory _updatedStrategyData = CamelotStrategy.StrategyData({
            tokenA: _tokenA,
            tokenB: _tokenB,
            router: _router,
            positionHelper: _positionHelper,
            factory: _factory,
            nftPool: _nftPool
        });

        bytes memory actualData = abi.encode(_updatedStrategyData);
        bytes memory expectedData = abi.encode(_newStrategyData);

        assertEq(keccak256(actualData), keccak256(expectedData));
    }
}

contract MiscellaneousTests is TestInitialization {
    function test_Supports_Collateral() public {
        bool result1 = camelotStrategy.supportsCollateral(USDT);
        assertEq(result1, true);

        bool result2 = camelotStrategy.supportsCollateral(USDCe);
        assertEq(result2, true);

        address randomToken = address(0x1);

        bool result3 = camelotStrategy.supportsCollateral(randomToken);
        assertEq(result3, false);
    }

    function test_Collect_Interest() public {
        address addressToCollectInterest = address(0x1);
        vm.expectRevert(abi.encodeWithSelector(Helpers.CustomError.selector, "Operation not permitted"));
        camelotStrategy.collectInterest(addressToCollectInterest);
    }

    function test_Interest_Earned() public {
        address addressToCollectInterest = address(0x1);
        uint256 interestEarned = camelotStrategy.checkInterestEarned(addressToCollectInterest);
        assertEq(interestEarned, 0);
    }
}
