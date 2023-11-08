// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.16;

import {Setup} from "./BaseTest.sol";
import {UpgradeUtil} from "./UpgradeUtil.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

// import Contracts
import {USDs} from "../../contracts/token/USDs.sol";
import {VaultCore} from "../../contracts/vault/VaultCore.sol";
import {FeeCalculator} from "../../contracts/vault/FeeCalculator.sol";
import {ICollateralManager, CollateralManager} from "../../contracts/vault/CollateralManager.sol";
import {MasterPriceOracle} from "../../contracts/oracle/MasterPriceOracle.sol";
import {SPABuyback} from "../../contracts/buyback/SPABuyback.sol";
import {YieldReserve} from "../../contracts/buyback/YieldReserve.sol";
import {Dripper} from "../../contracts/rebase/Dripper.sol";
import {RebaseManager} from "../../contracts/rebase/RebaseManager.sol";
import {MasterPriceOracle} from "../../contracts/oracle/MasterPriceOracle.sol";
import {ChainlinkOracle} from "../../contracts/oracle/ChainlinkOracle.sol";
import {StargateStrategy} from "../../contracts/strategies/stargate/StargateStrategy.sol";
import {AaveStrategy} from "../../contracts/strategies/aave/AaveStrategy.sol";
import {CompoundStrategy} from "../../contracts/strategies/compound/CompoundStrategy.sol";
import {VSTOracle} from "../../contracts/oracle/VSTOracle.sol";

interface ICustomOracle {
    function updateDIAParams(uint256 _weightDIA, uint128 _maxTime) external;

    function getPrice() external view returns (uint256, uint256);
}

abstract contract PreMigrationSetup is Setup {
    struct PriceFeedData {
        address token;
        address source;
        bytes msgData;
    }

    UpgradeUtil internal upgradeUtil;
    MasterPriceOracle internal masterOracle;
    ChainlinkOracle chainlinkOracle;
    VSTOracle vstOracle;
    address internal spaOracle;
    address internal usdsOracle;
    StargateStrategy internal stargateStrategy;
    AaveStrategy internal aaveStrategy;
    CompoundStrategy internal compoundStrategy;

    function setUp() public virtual override {
        super.setUp();

        setArbitrumFork();

        USDS = 0xD74f5255D557944cf7Dd0E45FF521520002D5748;
        SPA = 0x5575552988A3A80504bBaeB1311674fCFd40aD4B;
        USDS_OWNER = 0x5b12d9846F8612E439730d18E1C12634753B1bF1;
        PROXY_ADMIN = 0x3E49925A79CbFb68BAa5bc9DFb4f7D955D1ddF25;
        SPA_BUYBACK = 0xFbc0d3cA777722d234FE01dba94DeDeDb277AFe3;
        BUYBACK = 0xf3f98086f7B61a32be4EdF8d8A4b964eC886BBcd;

        upgradeUtil = new UpgradeUtil();

        // Upgrade USDs contract
        USDs usdsImpl = new USDs();
        vm.prank(ProxyAdmin(PROXY_ADMIN).owner());
        ProxyAdmin(PROXY_ADMIN).upgrade(ITransparentUpgradeableProxy(USDS), address(usdsImpl));
        vm.startPrank(USDS_OWNER);
        // Deploy
        VaultCore vaultImpl = new VaultCore();
        VAULT = upgradeUtil.deployErc1967Proxy(address(vaultImpl));
        USDs(USDS).updateVault(VAULT);

        VaultCore vault = VaultCore(VAULT);
        vault.initialize();
        CollateralManager collateralManager = new CollateralManager(VAULT);

        ORACLE = address(new MasterPriceOracle());
        FeeCalculator feeCalculator = new FeeCalculator(
            address(collateralManager)
        );
        FEE_CALCULATOR = address(feeCalculator);

        COLLATERAL_MANAGER = address(collateralManager);
        FEE_VAULT = 0xFbc0d3cA777722d234FE01dba94DeDeDb277AFe3;
        DRIPPER = address(new Dripper(VAULT, 7 days));
        REBASE_MANAGER = address(new RebaseManager(VAULT, DRIPPER, 1 days, 1000, 800));
        YIELD_RESERVE = address(new YieldReserve(BUYBACK, VAULT, ORACLE, DRIPPER));

        vault.updateCollateralManager(COLLATERAL_MANAGER);
        vault.updateFeeCalculator(FEE_CALCULATOR);
        vault.updateOracle(ORACLE);
        vault.updateRebaseManager(REBASE_MANAGER);
        vault.updateFeeVault(FEE_VAULT);
        vault.updateYieldReceiver(YIELD_RESERVE);

        vstOracle = new VSTOracle();
        masterOracle = MasterPriceOracle(ORACLE);
        // A pre-requisite for initializing SPA and USDs oracles
        deployAndConfigureChainlink();
        masterOracle.updateTokenPriceFeed(
            USDCe, address(chainlinkOracle), abi.encodeWithSelector(ChainlinkOracle.getTokenPrice.selector, USDCe)
        );
        spaOracle = deployCode("SPAOracle.sol:SPAOracle", abi.encode(address(masterOracle), USDCe, 10000, 600, 70));
        ICustomOracle(address(spaOracle)).updateDIAParams(70, type(uint128).max);
        usdsOracle = deployCode("USDsOracle.sol", abi.encode(address(masterOracle), USDCe, 500, 600));

        updatePriceFeeds();

        ICollateralManager.CollateralBaseData memory _data = ICollateralManager.CollateralBaseData({
            mintAllowed: true,
            redeemAllowed: true,
            allocationAllowed: true,
            baseMintFee: 0,
            baseRedeemFee: 0,
            downsidePeg: 9800,
            desiredCollateralComposition: 1000
        });

        address stargateRouter = 0x53Bf833A5d6c4ddA888F69c22C88C9f356a41614;
        address stg = 0x6694340fc020c5E6B96567843da2df01b2CE1eb6;
        address stargateFarm = 0xeA8DfEE1898a7e0a59f7527F076106d7e44c2176;
        StargateStrategy stargateStrategyImpl = new StargateStrategy();
        address stargateStrategyProxy = upgradeUtil.deployErc1967Proxy(address(stargateStrategyImpl));
        vm.makePersistent(stargateStrategyProxy);
        stargateStrategy = StargateStrategy(stargateStrategyProxy);
        stargateStrategy.initialize(stargateRouter, VAULT, stg, stargateFarm, 20, 20);
        stargateStrategy.setPTokenAddress(USDCe, 0x892785f33CdeE22A30AEF750F285E18c18040c3e, 1, 0, 0);

        address aavePoolProvider = 0xa97684ead0e402dC232d5A977953DF7ECBaB3CDb;
        AaveStrategy aaveStrategyImpl = new AaveStrategy();
        address aaveStrategyProxy = upgradeUtil.deployErc1967Proxy(address(aaveStrategyImpl));
        vm.makePersistent(aaveStrategyProxy);
        aaveStrategy = AaveStrategy(aaveStrategyProxy);
        aaveStrategy.initialize(aavePoolProvider, VAULT);
        aaveStrategy.setPTokenAddress(USDCe, 0x625E7708f30cA75bfd92586e17077590C60eb4cD, 0);

        collateralManager.addCollateral(USDCe, _data);
        collateralManager.addCollateral(USDT, _data);
        collateralManager.addCollateral(FRAX, _data);
        collateralManager.addCollateral(VST, _data);
        collateralManager.addCollateral(USDC, _data);
        collateralManager.addCollateralStrategy(USDCe, address(stargateStrategy), 3000);
        collateralManager.addCollateralStrategy(USDCe, address(aaveStrategy), 4000);
        collateralManager.updateCollateralDefaultStrategy(USDCe, address(stargateStrategy));
        AAVE_STRATEGY = address(aaveStrategy);
        STARGATE_STRATEGY = address(stargateStrategy);
        feeCalculator.calibrateFeeForAll();

        // Deploying Compound strategy
        address compoundRewardPool = 0x88730d254A2f7e6AC8388c3198aFd694bA9f7fae;
        CompoundStrategy compoundStrategyImpl = new CompoundStrategy();
        address compoundStrategyProxy = upgradeUtil.deployErc1967Proxy(address(compoundStrategyImpl));
        // vm.makePersistent(aaveStrategyProxy);
        compoundStrategy = CompoundStrategy(compoundStrategyProxy);
        compoundStrategy.initialize(VAULT, compoundRewardPool);
        compoundStrategy.setPTokenAddress(USDC, 0x9c4ec768c28520B50860ea7a15bd7213a9fF58bf, 0);
        collateralManager.addCollateralStrategy(USDC, address(compoundStrategy), 4000);
        vm.stopPrank();
    }

    function deployAndConfigureChainlink() private {
        ChainlinkOracle.SetupTokenData[] memory chainlinkFeeds = new ChainlinkOracle.SetupTokenData[](3);
        chainlinkFeeds[0] = ChainlinkOracle.SetupTokenData(
            USDCe, ChainlinkOracle.TokenData(0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3, 1e8)
        );
        chainlinkFeeds[1] = ChainlinkOracle.SetupTokenData(
            FRAX, ChainlinkOracle.TokenData(0x0809E3d38d1B4214958faf06D8b1B1a2b73f2ab8, 1e8)
        );
        chainlinkFeeds[2] = ChainlinkOracle.SetupTokenData(
            DAI, ChainlinkOracle.TokenData(0xc5C8E77B397E531B8EC06BFb0048328B30E9eCfB, 1e8)
        );
        chainlinkOracle = new ChainlinkOracle(chainlinkFeeds);
    }

    function updatePriceFeeds() private {
        PriceFeedData[] memory feedData = new PriceFeedData[](5);
        feedData[0] = PriceFeedData(
            FRAX, address(chainlinkOracle), abi.encodeWithSelector(ChainlinkOracle.getTokenPrice.selector, FRAX)
        );
        feedData[1] = PriceFeedData(
            DAI, address(chainlinkOracle), abi.encodeWithSelector(ChainlinkOracle.getTokenPrice.selector, DAI)
        );
        feedData[2] = PriceFeedData(VST, address(vstOracle), abi.encodeWithSelector(VSTOracle.getPrice.selector));
        feedData[3] = PriceFeedData(SPA, spaOracle, abi.encodeWithSelector(ICustomOracle.getPrice.selector));
        feedData[4] = PriceFeedData(USDS, usdsOracle, abi.encodeWithSelector(ICustomOracle.getPrice.selector));
        // feedData[0] = PriceFeedData(USDCe, address(chainlinkOracle), abi.encodeWithSelector(ChainlinkOracle.getTokenPrice.selector, USDCe));
        for (uint8 i = 0; i < feedData.length; ++i) {
            masterOracle.updateTokenPriceFeed(feedData[i].token, feedData[i].source, feedData[i].msgData);
        }
    }
}
