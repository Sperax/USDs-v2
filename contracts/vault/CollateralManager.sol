// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ICollateralManager} from "./interfaces/ICollateralManager.sol";
import {IStrategy} from "./interfaces/IStrategy.sol";
import {Helpers} from "../libraries/Helpers.sol";

interface IERC20Custom is IERC20 {
    function decimals() external view returns (uint8);
}

/// @title Collateral Manager contract for USDs protocol
/// @author Sperax Foundation
/// @notice Manages addition and removal of collateral, configures
///     collateral strategies and percentage of allocation
contract CollateralManager is ICollateralManager, Ownable {
    struct CollateralData {
        bool mintAllowed;
        bool redeemAllowed;
        bool allocationAllowed;
        bool exists;
        address defaultStrategy;
        uint16 baseMintFee;
        uint16 baseRedeemFee;
        uint16 downsidePeg;
        uint16 desiredCollateralComposition;
        uint16 collateralCapacityUsed;
        uint256 conversionFactor;
    }

    struct StrategyData {
        uint16 allocationCap;
        bool exists;
    }

    uint16 public collateralCompositionUsed;
    address public immutable VAULT;
    address[] private collaterals;
    mapping(address => CollateralData) public collateralInfo;
    mapping(address => mapping(address => StrategyData))
        private collateralStrategyInfo;
    mapping(address => address[]) private collateralStrategies;

    event CollateralAdded(address collateral, CollateralBaseData data);
    event CollateralRemoved(address collateral);
    event CollateralInfoUpdated(address collateral, CollateralBaseData data);
    event CollateralStrategyAdded(address collateral, address strategy);
    event CollateralStrategyUpdated(address collateral, address strategy);
    event CollateralStrategyRemoved(address collateral, address strategy);

    error CollateralExists();
    error CollateralDoesNotExist();
    error CollateralStrategyExists();
    error CollateralStrategyMapped();
    error CollateralStrategyNotMapped();
    error CollateralNotSupportedByStrategy();
    error CollateralAllocationPaused();
    error CollateralStrategyInUse();
    error AllocationPercentageLowerThanAllocatedAmt();
    error IsDefaultStrategy();

    constructor(address _vault) {
        VAULT = _vault;
    }

    /// @notice Register a collateral for mint & redeem in USDs
    /// @param _collateral Address of the collateral
    /// @param _data Collateral configuration data
    function addCollateral(
        address _collateral,
        CollateralBaseData memory _data
    ) external onlyOwner {
        // Test if collateral is already added
        // Initialize collateral storage data
        if (collateralInfo[_collateral].exists) revert CollateralExists();

        Helpers._isLTEMaxPercentage(_data.downsidePeg);
        Helpers._isLTEMaxPercentage(_data.baseMintFee);
        Helpers._isLTEMaxPercentage(_data.baseRedeemFee);

        Helpers._isLTEMaxPercentage(
            _data.desiredCollateralComposition + collateralCompositionUsed,
            "Collateral composition exceeded"
        );

        collateralInfo[_collateral] = CollateralData({
            mintAllowed: _data.mintAllowed,
            redeemAllowed: _data.redeemAllowed,
            allocationAllowed: _data.allocationAllowed,
            defaultStrategy: address(0),
            baseMintFee: _data.baseMintFee,
            baseRedeemFee: _data.baseRedeemFee,
            downsidePeg: _data.downsidePeg,
            collateralCapacityUsed: 0,
            desiredCollateralComposition: _data.desiredCollateralComposition,
            exists: true,
            conversionFactor: 10 ** (18 - IERC20Custom(_collateral).decimals())
        });

        collaterals.push(_collateral);
        collateralCompositionUsed += _data.desiredCollateralComposition;

        emit CollateralAdded(_collateral, _data);
    }

    /// @notice Update existing collateral configuration
    /// @param _collateral Address of the collateral
    /// @param _updateData Updated configuration for the collateral
    function updateCollateralData(
        address _collateral,
        CollateralBaseData memory _updateData
    ) external onlyOwner {
        // Check if collateral added;
        // Update the collateral storage data
        if (!collateralInfo[_collateral].exists)
            revert CollateralDoesNotExist();

        Helpers._isLTEMaxPercentage(_updateData.downsidePeg);
        Helpers._isLTEMaxPercentage(_updateData.baseMintFee);
        Helpers._isLTEMaxPercentage(_updateData.baseRedeemFee);

        CollateralData storage data = collateralInfo[_collateral];

        uint16 newCapacityUsed = (collateralCompositionUsed -
            data.desiredCollateralComposition +
            _updateData.desiredCollateralComposition);

        Helpers._isLTEMaxPercentage(
            newCapacityUsed,
            "Collateral composition exceeded"
        );

        data.mintAllowed = _updateData.mintAllowed;
        data.redeemAllowed = _updateData.redeemAllowed;
        data.allocationAllowed = _updateData.allocationAllowed;
        data.baseMintFee = _updateData.baseMintFee;
        data.baseRedeemFee = _updateData.baseRedeemFee;
        data.downsidePeg = _updateData.downsidePeg;
        data.desiredCollateralComposition = _updateData
            .desiredCollateralComposition;

        collateralCompositionUsed = newCapacityUsed;

        emit CollateralInfoUpdated(_collateral, _updateData);
    }

    /// @notice Un-list a collateral
    /// @param _collateral Address of the collateral
    function removeCollateral(address _collateral) external onlyOwner {
        if (!collateralInfo[_collateral].exists)
            revert CollateralDoesNotExist();
        if (collateralStrategies[_collateral].length != 0)
            revert CollateralStrategyExists();

        uint256 numCollateral = collaterals.length;

        for (uint256 i; i < numCollateral; ) {
            if (collaterals[i] == _collateral) {
                collaterals[i] = collaterals[numCollateral - 1];
                collaterals.pop();
                collateralCompositionUsed -= collateralInfo[_collateral]
                    .desiredCollateralComposition;
                delete (collateralInfo[_collateral]);
                break;
            }

            unchecked {
                ++i;
            }
        }

        emit CollateralRemoved(_collateral);
    }

    /// @notice Add a new strategy to collateral
    /// @param _collateral Address of the collateral
    /// @param _strategy Address of the strategy
    /// @param _allocationCap Allocation capacity
    function addCollateralStrategy(
        address _collateral,
        address _strategy,
        uint16 _allocationCap
    ) external onlyOwner {
        CollateralData storage collateralData = collateralInfo[_collateral];

        // Check if the collateral is valid
        if (!collateralData.exists) revert CollateralDoesNotExist();
        // Check if collateral strategy not already added.
        if (collateralStrategyInfo[_collateral][_strategy].exists)
            revert CollateralStrategyMapped();
        // Check if collateral is allocation is supported by the strategy.
        if (!IStrategy(_strategy).supportsCollateral(_collateral))
            revert CollateralNotSupportedByStrategy();

        // Check if _allocation Per <= 100 - collateralCapacityUsed
        Helpers._isLTEMaxPercentage(
            _allocationCap + collateralData.collateralCapacityUsed,
            "Allocation percentage exceeded"
        );

        // add info to collateral mapping
        collateralStrategyInfo[_collateral][_strategy] = StrategyData(
            _allocationCap,
            true
        );
        collateralStrategies[_collateral].push(_strategy);
        collateralData.collateralCapacityUsed += _allocationCap;

        emit CollateralStrategyAdded(_collateral, _strategy);
    }

    /// @notice Update existing strategy for collateral
    /// @param _collateral Address of the collateral
    /// @param _strategy Address of the strategy
    /// @param _allocationCap Allocation capacity
    function updateCollateralStrategy(
        address _collateral,
        address _strategy,
        uint16 _allocationCap
    ) external onlyOwner {
        // Check if collateral and strategy are mapped
        // Check if _allocationCap <= 100 - collateralCapacityUsed  + oldAllocationPer
        // Update the info
        if (!collateralStrategyInfo[_collateral][_strategy].exists)
            revert CollateralStrategyNotMapped();

        CollateralData storage collateralData = collateralInfo[_collateral];
        StrategyData storage strategyData = collateralStrategyInfo[_collateral][
            _strategy
        ];

        uint16 newCapacityUsed = collateralData.collateralCapacityUsed -
            strategyData.allocationCap +
            _allocationCap;
        Helpers._isLTEMaxPercentage(
            newCapacityUsed,
            "Allocation percentage exceeded"
        );

        uint256 totalCollateral = getCollateralInVault(_collateral) +
            getCollateralInStrategies(_collateral);
        uint256 currentAllocatedPer = (getCollateralInAStrategy(
            _collateral,
            _strategy
        ) * Helpers.MAX_PERCENTAGE) / totalCollateral;

        if (_allocationCap < currentAllocatedPer)
            revert AllocationPercentageLowerThanAllocatedAmt();
        collateralData.collateralCapacityUsed = newCapacityUsed;
        strategyData.allocationCap = _allocationCap;

        emit CollateralStrategyUpdated(_collateral, _strategy);
    }

    /// @notice Remove an existing strategy from collateral
    /// @param _collateral Address of the collateral
    /// @param _strategy Address of the strategy
    /// @dev Ensure all the collateral is removed from the strategy before calling this
    ///      Otherwise it will create error in collateral accounting
    function removeCollateralStrategy(
        address _collateral,
        address _strategy
    ) external onlyOwner {
        // Check if the collateral and strategy are mapped.
        // ensure none of the collateral is deposited to strategy
        // remove collateralCapacity.
        // remove item from list.
        if (!collateralStrategyInfo[_collateral][_strategy].exists)
            revert CollateralStrategyNotMapped();

        if (collateralInfo[_collateral].defaultStrategy == _strategy)
            revert IsDefaultStrategy();
        if (IStrategy(_strategy).checkBalance(_collateral) != 0)
            revert CollateralStrategyInUse();

        uint256 numStrategy = collateralStrategies[_collateral].length;

        for (uint256 i; i < numStrategy; ) {
            if (collateralStrategies[_collateral][i] == _strategy) {
                collateralStrategies[_collateral][i] = collateralStrategies[
                    _collateral
                ][numStrategy - 1];
                collateralStrategies[_collateral].pop();
                collateralInfo[_collateral]
                    .collateralCapacityUsed -= collateralStrategyInfo[
                    _collateral
                ][_strategy].allocationCap;
                delete collateralStrategyInfo[_collateral][_strategy];
                break;
            }

            unchecked {
                ++i;
            }
        }

        emit CollateralStrategyRemoved(_collateral, _strategy);
    }

    /// @inheritdoc ICollateralManager
    function updateCollateralDefaultStrategy(
        address _collateral,
        address _strategy
    ) external onlyOwner {
        if (
            !collateralStrategyInfo[_collateral][_strategy].exists &&
            _strategy != address(0)
        ) revert CollateralStrategyNotMapped();
        collateralInfo[_collateral].defaultStrategy = _strategy;
    }

    /// @inheritdoc ICollateralManager
    function validateAllocation(
        address _collateral,
        address _strategy,
        uint256 _amount
    ) external view returns (bool) {
        if (!collateralInfo[_collateral].allocationAllowed)
            revert CollateralAllocationPaused();

        uint256 maxCollateralUsage = (collateralStrategyInfo[_collateral][
            _strategy
        ].allocationCap *
            (getCollateralInVault(_collateral) +
                getCollateralInStrategies(_collateral))) /
            Helpers.MAX_PERCENTAGE;

        uint256 collateralBalance = IStrategy(_strategy).checkBalance(
            _collateral
        );

        if (maxCollateralUsage >= collateralBalance) {
            return ((maxCollateralUsage - collateralBalance) >= _amount);
        }

        return false;
    }

    /// @inheritdoc ICollateralManager
    function getFeeCalibrationData(
        address _collateral
    ) external view returns (uint16, uint16, uint16, uint256) {
        // Compose and return collateral mint params
        CollateralData memory collateralStorageData = collateralInfo[
            _collateral
        ];

        // Check if collateral exists
        if (!collateralStorageData.exists) revert CollateralDoesNotExist();

        uint256 totalCollateral = getCollateralInStrategies(_collateral) +
            getCollateralInVault(_collateral);

        return (
            collateralStorageData.baseMintFee,
            collateralStorageData.baseRedeemFee,
            collateralStorageData.desiredCollateralComposition,
            totalCollateral * collateralStorageData.conversionFactor
        );
    }

    /// @inheritdoc ICollateralManager
    function getMintParams(
        address _collateral
    ) external view returns (CollateralMintData memory mintData) {
        // Compose and return collateral mint params
        CollateralData memory collateralStorageData = collateralInfo[
            _collateral
        ];

        // Check if collateral exists
        if (!collateralInfo[_collateral].exists)
            revert CollateralDoesNotExist();

        return
            CollateralMintData({
                mintAllowed: collateralStorageData.mintAllowed,
                baseMintFee: collateralStorageData.baseMintFee,
                downsidePeg: collateralStorageData.downsidePeg,
                desiredCollateralComposition: collateralStorageData
                    .desiredCollateralComposition,
                conversionFactor: collateralStorageData.conversionFactor
            });
    }

    /// @inheritdoc ICollateralManager
    function getRedeemParams(
        address _collateral
    ) external view returns (CollateralRedeemData memory redeemData) {
        if (!collateralInfo[_collateral].exists)
            revert CollateralDoesNotExist();
        // Check if collateral exists
        // Compose and return collateral redeem params

        CollateralData memory collateralStorageData = collateralInfo[
            _collateral
        ];

        return
            CollateralRedeemData({
                redeemAllowed: collateralStorageData.redeemAllowed,
                defaultStrategy: collateralStorageData.defaultStrategy,
                baseRedeemFee: collateralStorageData.baseRedeemFee,
                desiredCollateralComposition: collateralStorageData
                    .desiredCollateralComposition,
                conversionFactor: collateralStorageData.conversionFactor
            });
    }

    /// @notice Gets list of all the listed collateral
    /// @return address[] of listed collaterals
    function getAllCollaterals() external view returns (address[] memory) {
        return collaterals;
    }

    /// @notice Gets list of all the collateral linked strategies
    /// @param _collateral Address of the collateral
    /// @return address[] list of available strategies for a collateral
    function getCollateralStrategies(
        address _collateral
    ) external view returns (address[] memory) {
        return collateralStrategies[_collateral];
    }

    /// @notice Verify if a strategy is linked to a collateral
    /// @param _collateral Address of the collateral
    /// @param _strategy Address of the strategy
    /// @return boolean true if the strategy is linked to the collateral
    function isValidStrategy(
        address _collateral,
        address _strategy
    ) external view returns (bool) {
        return collateralStrategyInfo[_collateral][_strategy].exists;
    }

    /// @inheritdoc ICollateralManager
    function getCollateralInStrategies(
        address _collateral
    ) public view returns (uint256 amountInStrategies) {
        uint256 numStrategy = collateralStrategies[_collateral].length;

        for (uint256 i; i < numStrategy; ) {
            amountInStrategies += IStrategy(
                collateralStrategies[_collateral][i]
            ).checkBalance(_collateral);
            unchecked {
                ++i;
            }
        }

        return amountInStrategies;
    }

    /// @inheritdoc ICollateralManager
    function getCollateralInVault(
        address _collateral
    ) public view returns (uint256 amountInVault) {
        return IERC20(_collateral).balanceOf(VAULT);
    }

    /// @notice Get the amount of collateral allocated in a strategy
    /// @param _collateral Address of the collateral
    /// @param _strategy Address of the strategy
    /// @return allocatedAmt Allocated amount
    function getCollateralInAStrategy(
        address _collateral,
        address _strategy
    ) public view returns (uint256 allocatedAmt) {
        return IStrategy(_strategy).checkBalance(_collateral);
    }
}
