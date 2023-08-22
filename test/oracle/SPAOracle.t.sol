pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {SPAOracle} from "../../contracts/oracle/SPAOracle.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {BaseTest} from "../utils/BaseTest.sol";

interface IChainlinkOracle {
    struct TokenData {
        address source;
        uint256 precision;
    }

    function setTokenData(address _token, TokenData memory _tokenData) external;

    function getTokenPrice(
        address _token
    ) external view returns (uint256, uint256);
}

interface IMasterOracle {
    function updateTokenPriceFeed(
        address token,
        address source,
        bytes calldata msgData
    ) external;

    function removeTokenPriceFeed(address _token) external;
}

abstract contract BaseUniOracleTest is BaseTest {
    address public constant UNISWAP_FACTORY =
        0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address masterOracle;
    address chainlinkOracle;

    event UniMAPriceDataChanged(
        address quoteToken,
        uint24 feeTier,
        uint32 maPeriod
    );
    event MasterOracleUpdated(address newOracle);

    function setUp() public virtual override {
        super.setUp();
        setArbitrumFork();
        vm.startPrank(USDS_OWNER);
        masterOracle = deployCode("MasterPriceOracle.sol");

        chainlinkOracle = deployCode(
            "ChainlinkOracle.sol",
            abi.encode(new IChainlinkOracle.TokenData[](0))
        );
        IChainlinkOracle.TokenData memory usdcData = IChainlinkOracle.TokenData(
            0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3,
            1e8
        );

        IChainlinkOracle(chainlinkOracle).setTokenData(USDCe, usdcData);

        IMasterOracle(masterOracle).updateTokenPriceFeed(
            USDCe,
            address(chainlinkOracle),
            abi.encodeWithSelector(
                IChainlinkOracle.getTokenPrice.selector,
                USDCe
            )
        );

        vm.stopPrank();
    }
}

contract SPAOracleTest is BaseUniOracleTest {
    address public constant DIA_ORACLE =
        0x7919D08e0f41398cBc1e0A8950Df831e4895c19b;
    uint128 public constant SPA_PRICE_PRECISION = 1e8;
    uint24 public constant FEE_TIER = 10000;
    uint32 public constant MA_PERIOD = 600;
    uint256 public constant WEIGHT_DIA = 70;

    SPAOracle public spaOracle;

    event DIAParamsUpdated(uint256 weightDIA, uint256 maxAge);

    function setUp() public override {
        super.setUp();
        vm.prank(USDS_OWNER);
        spaOracle = new SPAOracle(
            masterOracle,
            USDCe,
            FEE_TIER,
            MA_PERIOD,
            WEIGHT_DIA
        );
    }
}

contract Test_Init is SPAOracleTest {
    function test_initialization() public {
        assertEq(
            spaOracle.pool(),
            IUniswapV3Factory(UNISWAP_FACTORY).getPool(SPA, USDCe, FEE_TIER)
        );
        assertEq(uint256(spaOracle.maPeriod()), uint256(MA_PERIOD));
        assertEq(spaOracle.weightDIA(), WEIGHT_DIA);
    }
}

contract Test_FetchPrice is SPAOracleTest {
    function test_fetchPrice() public {
        (uint256 price, uint256 precision) = spaOracle.getPrice();
        assertEq(precision, SPA_PRICE_PRECISION);
        assertGt(price, 0);
    }
}

contract Test_setUniMAPriceData is SPAOracleTest {
    function test_revertsWhen_notOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        spaOracle.setUniMAPriceData(SPA, USDCe, 10000, 600);
    }

    function test_revertsWhen_invalidData() public useKnownActor(USDS_OWNER) {
        vm.expectRevert("Feed unavailable");
        spaOracle.setUniMAPriceData(SPA, FRAX, 3000, 600);
    }

    function test_setUniMAPriceData() public useKnownActor(USDS_OWNER) {
        vm.expectEmit(true, true, true, true);
        emit UniMAPriceDataChanged(USDCe, 10000, 700);
        spaOracle.setUniMAPriceData(SPA, USDCe, 10000, 700);
    }
}

contract Test_updateMasterOracle is SPAOracleTest {
    function test_revertsWhen_notOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        spaOracle.updateMasterOracle(masterOracle);
    }

    function test_revertsWhen_invalidAddress()
        public
        useKnownActor(USDS_OWNER)
    {
        vm.expectRevert("Invalid Address");
        spaOracle.updateMasterOracle(address(0));
    }

    function test_revertsWhen_quoteTokenPriceFeedUnavailable()
        public
        useKnownActor(USDS_OWNER)
    {
        IMasterOracle(masterOracle).removeTokenPriceFeed(USDCe);
        vm.expectRevert();
        spaOracle.updateMasterOracle(masterOracle);
    }

    function test_updateMasterOracle() public useKnownActor(USDS_OWNER) {
        vm.expectEmit(true, true, true, true);
        emit MasterOracleUpdated(masterOracle);
        spaOracle.updateMasterOracle(masterOracle);
    }
}

contract Test_UpdateDIAWeight is SPAOracleTest {
    function test_revertsWhen_notOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        spaOracle.updateDIAParams(60, 600);
    }

    function test_revertsWhen_invalidWeight() public useKnownActor(USDS_OWNER) {
        uint256 newWeight = spaOracle.MAX_WEIGHT() + 10;
        vm.expectRevert("Invalid weight");
        spaOracle.updateDIAParams(newWeight, 600);
    }

    function test_updateDIAParams() public useKnownActor(USDS_OWNER) {
        uint256 newWeight = 80;
        vm.expectEmit(true, true, true, true);
        emit DIAParamsUpdated(newWeight, 600);
        spaOracle.updateDIAParams(newWeight, 600);
    }
}
