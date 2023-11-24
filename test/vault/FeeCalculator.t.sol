// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {PreMigrationSetup} from "../utils/DeploymentSetup.sol";
import {Helpers, FeeCalculator} from "../../contracts/vault/FeeCalculator.sol";
import {ICollateralManager} from "../../contracts/vault/interfaces/ICollateralManager.sol";
import {IOracle} from "../../contracts/interfaces/IOracle.sol";
import {IUSDs} from "../../contracts/interfaces/IUSDs.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract FeeCalculatorTestSetup is PreMigrationSetup {
    FeeCalculator internal feeCalculator;
    ICollateralManager internal collateralManager;
    address internal _collateral;
    uint16 internal constant DISCOUNT_FACTOR = 2;
    uint16 internal constant PENALTY_MULTIPLIER = 2;

    function setUp() public virtual override {
        super.setUp();
        feeCalculator = FeeCalculator(FEE_CALCULATOR);
        collateralManager = ICollateralManager(COLLATERAL_MANAGER);
        _collateral = USDCe;
    }
}

contract TestFeeCalculatorInit is FeeCalculatorTestSetup {
    FeeCalculator _feeCalculator;

    function testInitialization() public {
        _feeCalculator = new FeeCalculator(address(collateralManager));
        vm.warp(block.timestamp + 1 days);
        _feeCalculator.calibrateFeeForAll();
        vm.warp(block.timestamp + 1 days);
        _feeCalculator.calibrateFee(USDCe);
        _feeCalculator.calibrateFeeForAll();
        address[] memory collaterals = collateralManager.getAllCollaterals();
        uint256 colLength = collaterals.length;
        for (uint256 i; i < colLength;) {
            (uint32 nextUpdate,,) = feeCalculator.collateralFee(collaterals[i]);
            assertTrue(nextUpdate != 0);
            unchecked {
                ++i;
            }
        }
    }
}

contract TestCalibrateFee is FeeCalculatorTestSetup {
    uint256 availableCollateral;

    function setUp() public override {
        super.setUp();
        availableCollateral = 1 * 10 ** ERC20(_collateral).decimals();
    }

    function test_revertsIf_InvalidCalibration() public {
        vm.expectRevert(abi.encodeWithSelector(FeeCalculator.InvalidCalibration.selector));
        feeCalculator.calibrateFee(_collateral);
    }

    function test_CalibrateFee_TotalCollateralLTLowerLimit() public {
        setCollateralData(_collateral);
        vm.warp(block.timestamp + 1 days);
        // Desired collateral composition is set as 1000 in setCollateralData()
        // But in Fee calculator the desired composition would be 500 to 1500 hence
        // below mocking would return the collateral as 1200 means 12% of TVL
        // equally divided in vault and strategies
        mockCollateralCalls((IUSDs(USDS).totalSupply() * 1200) / 10000);
        feeCalculator.calibrateFee(_collateral);
        uint256 oldMintFee = feeCalculator.getMintFee(_collateral);
        uint256 oldRedeemFee = feeCalculator.getRedeemFee(_collateral);
        assertEq(oldMintFee, 500);
        assertEq(oldRedeemFee, 500);
        vm.clearMockedCalls();
        vm.warp(block.timestamp + 1 days);
        // Collateral composition calls are mocked to return lesser than lower limit
        mockCollateralCalls(availableCollateral / 2);
        feeCalculator.calibrateFee(_collateral);
        vm.clearMockedCalls();
        uint256 newMintFee = feeCalculator.getMintFee(_collateral);
        uint256 newRedeemFee = feeCalculator.getRedeemFee(_collateral);

        assertEq(oldMintFee / 2, newMintFee);
        assertEq(oldRedeemFee * 2, newRedeemFee);
    }

    function test_CalibrateFee_TotalCollateralIsInDesiredRange() public {
        setCollateralData(_collateral);
        vm.warp(block.timestamp + 1 days);
        // Desired collateral composition is set as 1000 in setCollateralData()
        // But in Fee calculator the desired composition would be 500 to 1500 hence
        // below mocking would return the collateral as 1200 means 12% of TVL
        // equally divided in vault and strategies
        mockCollateralCalls((IUSDs(USDS).totalSupply() * 1200) / 10000);
        feeCalculator.calibrateFee(_collateral);
        uint256 oldMintFee = feeCalculator.getMintFee(_collateral);
        uint256 oldRedeemFee = feeCalculator.getRedeemFee(_collateral);
        assertEq(oldMintFee, 500);
        assertEq(oldRedeemFee, 500);
        vm.warp(block.timestamp + 1 days);
        // Ratio is changed but still in desired range
        mockCollateralCalls((IUSDs(USDS).totalSupply() * 600) / 10000);
        feeCalculator.calibrateFee(_collateral);
        vm.clearMockedCalls();
        uint256 newMintFee = feeCalculator.getMintFee(_collateral);
        uint256 newRedeemFee = feeCalculator.getRedeemFee(_collateral);

        assertEq(oldMintFee, newMintFee);
        assertEq(oldRedeemFee, newRedeemFee);
    }

    function test_CalibrateFee_TotalCollateralGTUpperLimit() public {
        setCollateralData(_collateral);
        vm.warp(block.timestamp + 1 days);
        // Desired collateral composition is set as 1000 in setCollateralData()
        // But in Fee calculator the desired composition would be 500 to 1500 hence
        // below mocking would return the collateral as 200 means 2% of TVL LT lower limit
        // equally divided in vault and strategies
        mockCollateralCalls((IUSDs(USDS).totalSupply() * 200) / 10000);
        feeCalculator.calibrateFee(_collateral);
        uint256 oldMintFee = feeCalculator.getMintFee(_collateral);
        uint256 oldRedeemFee = feeCalculator.getRedeemFee(_collateral);
        assertEq(oldMintFee, 500 / 2);
        assertEq(oldRedeemFee, 500 * 2);
        vm.warp(block.timestamp + 1 days);
        // Collateral composition calls are mocked to return higher than upper limit
        mockCollateralCalls((IUSDs(USDS).totalSupply() * 1600) / 10000);
        feeCalculator.calibrateFee(_collateral);
        vm.clearMockedCalls();
        uint256 newMintFee = feeCalculator.getMintFee(_collateral);
        uint256 newRedeemFee = feeCalculator.getRedeemFee(_collateral);

        // Basis taken as 4 because the old fee would be LT lower limit
        // and new fee would be GT higher limit
        assertEq(oldMintFee * 4, newMintFee);
        assertEq(oldRedeemFee / 4, newRedeemFee);
    }

    function setCollateralData(address _collateral) internal {
        ICollateralManager.CollateralBaseData memory _data = ICollateralManager.CollateralBaseData({
            mintAllowed: true,
            redeemAllowed: true,
            allocationAllowed: true,
            baseMintFee: 500,
            baseRedeemFee: 500,
            downsidePeg: 9800,
            desiredCollateralComposition: 1000
        });
        vm.prank(USDS_OWNER);
        ICollateralManager(COLLATERAL_MANAGER).updateCollateralData(_collateral, _data);
    }

    function mockCollateralCalls(uint256 _totalCollateral) internal {
        vm.mockCall(
            COLLATERAL_MANAGER,
            abi.encodeWithSignature("getFeeCalibrationData(address)", _collateral),
            abi.encode(500, 500, 1000, _totalCollateral)
        );
    }
}

contract TestFeeCalculator is FeeCalculatorTestSetup {
    IOracle.PriceData private priceData;
    uint16 private baseMintFee;
    uint16 private baseRedeemFee;
    uint16 private composition;
    uint16 private constant LOWER_THRESHOLD = 5000;
    uint16 private constant UPPER_THRESHOLD = 15000;

    function testGetMintFee() public {
        baseMintFee = getMintFee();
        uint256 mintFee = feeCalculator.getMintFee(USDCe);
        assertEq(mintFee, baseMintFee, "Fee in mismatch");
    }

    function testGetRedeemFee() public {
        baseRedeemFee = getRedeemFee();
        uint256 redeemFee = feeCalculator.getRedeemFee(USDT);
        assertEq(redeemFee, baseRedeemFee, "Fee out mismatch");
    }

    function getMintFee() private returns (uint16) {
        uint256 totalCollateral;
        (baseMintFee,, composition, totalCollateral) =
            ICollateralManager(COLLATERAL_MANAGER).getFeeCalibrationData(USDCe);
        uint256 tvl = IUSDs(Helpers.USDS).totalSupply();
        uint256 desiredCollateralAmt = (tvl * composition) / (Helpers.MAX_PERCENTAGE);
        uint256 lowerLimit = (desiredCollateralAmt * LOWER_THRESHOLD) / (Helpers.MAX_PERCENTAGE);
        uint256 upperLimit = (desiredCollateralAmt * UPPER_THRESHOLD) / (Helpers.MAX_PERCENTAGE);
        if (totalCollateral < lowerLimit) {
            return baseMintFee / DISCOUNT_FACTOR;
        } else if (totalCollateral < upperLimit) {
            return baseMintFee;
        } else {
            return baseMintFee * PENALTY_MULTIPLIER;
        }
    }

    function getRedeemFee() private returns (uint16) {
        uint256 totalCollateral;
        (, baseRedeemFee, composition, totalCollateral) =
            ICollateralManager(COLLATERAL_MANAGER).getFeeCalibrationData(USDCe);
        uint256 tvl = IUSDs(Helpers.USDS).totalSupply();
        uint256 desiredCollateralAmt = (tvl * composition) / (Helpers.MAX_PERCENTAGE);
        uint256 lowerLimit = (desiredCollateralAmt * LOWER_THRESHOLD) / (Helpers.MAX_PERCENTAGE);
        uint256 upperLimit = (desiredCollateralAmt * UPPER_THRESHOLD) / (Helpers.MAX_PERCENTAGE);
        if (totalCollateral < lowerLimit) {
            return baseRedeemFee * PENALTY_MULTIPLIER;
        } else if (totalCollateral < upperLimit) {
            return baseRedeemFee;
        } else {
            return baseRedeemFee / DISCOUNT_FACTOR;
        }
    }

    function getTotalCollateral(address _collateral) private view returns (uint256) {
        return ICollateralManager(COLLATERAL_MANAGER).getCollateralInVault(_collateral)
            + ICollateralManager(COLLATERAL_MANAGER).getCollateralInStrategies(_collateral);
    }
}
