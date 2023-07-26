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

abstract contract PreMigrationSetup is Setup {
    UpgradeUtil internal upgradeUtil;

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
        ProxyAdmin(PROXY_ADMIN).upgrade(
            ITransparentUpgradeableProxy(USDS),
            address(usdsImpl)
        );
        vm.startPrank(USDS_OWNER);
        // Deploy
        VaultCore vaultImpl = new VaultCore();
        VAULT = upgradeUtil.deployErc1967Proxy(address(vaultImpl));
        USDs(USDS).changeVault(VAULT);

        VaultCore vault = VaultCore(VAULT);
        vault.initialize();
        CollateralManager collateralManager = new CollateralManager(VAULT);

        ORACLE = address(new MasterPriceOracle());
        FEE_CALCULATOR = address(new FeeCalculator());
        COLLATERAL_MANAGER = address(collateralManager);
        DRIPPER = address(new Dripper(VAULT, 7 days));
        REBASE_MANAGER = address(
            new RebaseManager(VAULT, DRIPPER, 1 days, 1000, 800)
        );

        vault.updateCollateralManager(COLLATERAL_MANAGER);
        vault.updateFeeCalculator(FEE_CALCULATOR);
        vault.updateOracle(ORACLE);
        vault.updateRebaseManager(REBASE_MANAGER);

        ICollateralManager.CollateralBaseData memory _data = ICollateralManager
            .CollateralBaseData({
                mintAllowed: true,
                redeemAllowed: true,
                allocationAllowed: true,
                baseFeeIn: 0,
                baseFeeOut: 500,
                downsidePeg: 10000,
                desiredCollateralCompostion: 5000
            });

        collateralManager.addCollateral(USDCe, _data);
        vm.stopPrank();
    }
}
