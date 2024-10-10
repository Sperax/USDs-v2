// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {USDsDIAOracle, IDiaOracle} from "../../contracts/oracle/USDsDIAOracle.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {BaseTest} from "../utils/BaseTest.sol";

contract USDsDIAOracleTest is BaseTest {
    address public constant DIA_ORACLE = 0x7919D08e0f41398cBc1e0A8950Df831e4895c19b;
    uint128 public constant DIA_PRECISION = 1e8;

    USDsDIAOracle public usdsDIAOracle;

    event DIAParamsUpdated(uint128 maxTime);

    error InvalidWeight();
    error InvalidTime();
    error PriceTooOld();

    function setUp() public override {
        super.setUp();
        setArbitrumFork();
        vm.startPrank(USDS_OWNER);
        usdsDIAOracle = new USDsDIAOracle();
        usdsDIAOracle.updateDIAParams(type(uint128).max);
        vm.stopPrank();
    }
}

contract Test_Init is USDsDIAOracleTest {
    function test_initialization() public {
        (uint128 price, uint128 precision) = IDiaOracle(DIA_ORACLE).getValue("USDS/USD");
        assertNotEq(price, 0);
        assertNotEq(precision, 0);
        assertEq(USDS_OWNER, usdsDIAOracle.owner());
    }
}

contract Test_GetPrice is USDsDIAOracleTest {
    function test_RevertWhen_PriceTooOld() public {
        vm.startPrank(USDS_OWNER);
        usdsDIAOracle.updateDIAParams(121);
        vm.stopPrank();
        vm.expectRevert(abi.encodeWithSelector(PriceTooOld.selector));
        usdsDIAOracle.getPrice();
    }

    function test_GetPrice() public {
        vm.startPrank(USDS_OWNER);
        usdsDIAOracle.updateDIAParams(86400);
        (uint256 price, uint256 precision) = usdsDIAOracle.getPrice();
        assertEq(precision, DIA_PRECISION);
        assertGt(price, 0);
    }
}

contract Test_UpdateDIAParams is USDsDIAOracleTest {
    function test_RevertWhen_notOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        usdsDIAOracle.updateDIAParams(600);
    }

    function test_RevertWhen_invalidTime() public useKnownActor(USDS_OWNER) {
        vm.expectRevert(abi.encodeWithSelector(InvalidTime.selector));
        usdsDIAOracle.updateDIAParams(80);
    }

    function test_updateDIAParams() public useKnownActor(USDS_OWNER) {
        uint128 maxTime = 600;
        vm.expectEmit(true, true, true, true);
        emit DIAParamsUpdated(maxTime);
        usdsDIAOracle.updateDIAParams(maxTime);
        assertEq(usdsDIAOracle.diaMaxTimeThreshold(), maxTime);
    }
}
