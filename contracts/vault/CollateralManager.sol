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

/// @title Collateral Manager for the USDs Protocol
/// @notice This contract manages the addition and removal of collateral, configuration of collateral strategies, and allocation percentages.
/// @dev Collateral Manager interacts with the Vault and various strategies for collateral management.
/// @author Sperax Foundation
contract CollateralManager is ICollateralManager, Ownable {
    // Struct for storing collateral data
    struct CollateralData {
        bool mintAllowed;
        bool redeemAllowed;
        bool allocationAllowed;
        bool exists;
        address defaultStrategy;
        uint16 baseFeeIn;
        uint16 baseFeeOut;
        uint16 downsidePeg;
        uint16 desiredCollateralComposition;
        uint16 collateralCapacityUsed;
        uint256 conversionFactor;
    }

    // Struct for storing strategy data
    struct StrategyData {
        uint16 allocationCap;
        bool exists;
    }

    uint16 public collateralCompositionUsed;
    address public immutable VAULT;
    address[] private collaterals;
    mapping(address => CollateralData) public collateralInfo;
    mapping(address => mapping(address => StrategyData)) private collateralStrategyInfo;
    mapping(address => address[]) private collateralStrategies;

    event CollateralAdded(address collateral, CollateralBaseData data);
    event CollateralRemoved(address collateral);
    event CollateralInfoUpdated(address collateral, CollateralBaseData data);
    event CollateralStrategyAdded(address collateral, address strategy);
    event CollateralStrategyUpdated(address collateral, address strategy);
    event CollateralStrategyRemoved(address collateral, address strategy);

    // Error messages
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

    /// @dev Constructor to initialize the Collateral Manager
    /// @param _vault Address of the Vault contract
    constructor(address _vault) {
        VAULT = _vault;
    }

    /// @notice Register a collateral for mint & redeem in USDs
    /// @param _collateral Address of the collateral
    /// @param _data Collateral configuration data
    function addCollateral(address _collateral, CollateralBaseData memory _data) external onlyOwner {
        // Check if collateral is already added
        // Initialize collateral storage data
        if (collateralInfo[_collateral].exists) revert CollateralExists();

        // Check that configuration values do not exceed maximum percentage
        Helpers._isLTEMaxPercentage(_data.downsidePeg);
        Helpers._isLTEMaxPercentage(_data.baseFeeIn);
        Helpers._isLTEMaxPercentage(_data.baseFeeOut);

        // Check the desired collateral composition does not exceed the maximum
        Helpers._isLTEMaxPercentage(
            _data.desiredCollateralComposition + collateralCompositionUsed, "Collateral composition exceeded"
        );

        collateralInfo[_collateral] = CollateralData({
            mintAllowed: _data.mintAllowed,
            redeemAllowed: _data.redeemAllowed,
            allocationAllowed: _data.allocationAllowed,
            defaultStrategy: address(0),
            baseFeeIn: _data.baseFeeIn,
            baseFeeOut: _data.baseFeeOut,
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
    function updateCollateralData(address _collateral, CollateralBaseData memory _updateData) external onlyOwner {
        // Check if collateral is added
        // Update the collateral storage data
        if (!collateralInfo[_collateral].exists) {
            revert CollateralDoesNotExist();
        }

        // Check that updated configuration values do not exceed maximum percentage
        Helpers._isLTEMaxPercentage(_updateData.downsidePeg);
        Helpers._isLTEMaxPercentage(_updateData.baseFeeIn);
        Helpers._isLTEMaxPercentage(_updateData.baseFeeOut);

        CollateralData storage data = collateralInfo[_collateral];

        // Calculate the new capacity used to ensure it does not exceed the maximum collateral composition
        uint16 newCapacityUsed =
            (collateralCompositionUsed - data.desiredCollateralComposition + _updateData.desiredCollateralComposition);

        Helpers._isLTEMaxPercentage(newCapacityUsed, "Collateral composition exceeded");

        // Update the collateral data
        data.mintAllowed = _updateData.mintAllowed;
        data.redeemAllowed = _updateData.redeemAllowed;
        data.allocationAllowed = _updateData.allocationAllowed;
        data.baseFeeIn = _updateData.baseFeeIn;
        data.baseFeeOut = _updateData.baseFeeOut;
        data.downsidePeg = _updateData.downsidePeg;
        data.desiredCollateralComposition = _updateData.desiredCollateralComposition;

        // Update the collateral composition used
        collateralCompositionUsed = newCapacityUsed;

        emit CollateralInfoUpdated(_collateral, _updateData);
    }

    /// @notice Un-list a collateral
    /// @param _collateral Address of the collateral
    function removeCollateral(address _collateral) external onlyOwner {
        // Check if the collateral exists
        if (!collateralInfo[_collateral].exists) {
            revert CollateralDoesNotExist();
        }
        // Check if collateral strategies are empty
        if (collateralStrategies[_collateral].length != 0) {
            revert CollateralStrategyExists();
        }

        uint256 numCollateral = collaterals.length;

        for (uint256 i; i < numCollateral;) {
            if (collaterals[i] == _collateral) {
                // Remove the collateral from the list
                collaterals[i] = collaterals[numCollateral - 1];
                collaterals.pop();
                // Update the collateral composition used
                collateralCompositionUsed -= collateralInfo[_collateral].desiredCollateralComposition;
                // Delete the collateral data
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
    function addCollateralStrategy(address _collateral, address _strategy, uint16 _allocationCap) external onlyOwner {
        CollateralData storage collateralData = collateralInfo[_collateral];

        // Check if the collateral is valid
        if (!collateralData.exists) revert CollateralDoesNotExist();
        // Check if the collateral strategy is not already added.
        if (collateralStrategyInfo[_collateral][_strategy].exists) {
            revert CollateralStrategyMapped();
        }
        // Check if collateral allocation is supported by the strategy.
        if (!IStrategy(_strategy).supportsCollateral(_collateral)) {
            revert CollateralNotSupportedByStrategy();
        }

        // Check if the allocation percentage is within bounds
        Helpers._isLTEMaxPercentage(
            _allocationCap + collateralData.collateralCapacityUsed, "Allocation percentage exceeded"
        );

        // Add information to collateral mapping
        collateralStrategyInfo[_collateral][_strategy] = StrategyData(_allocationCap, true);
        collateralStrategies[_collateral].push(_strategy);
        collateralData.collateralCapacityUsed += _allocationCap;

        emit CollateralStrategyAdded(_collateral, _strategy);
    }

    /// @notice Update existing strategy for collateral
    /// @param _collateral Address of the collateral
    /// @param _strategy Address of the strategy
    /// @param _allocationCap Allocation capacity
    function updateCollateralStrategy(address _collateral, address _strategy, uint16 _allocationCap)
        external
        onlyOwner
    {
        // Check if the collateral and strategy are mapped
        // Check if the new allocation percentage is within bounds
        // _allocationCap <= 100 - collateralCapacityUsed  + oldAllocationPer
        if (!collateralStrategyInfo[_collateral][_strategy].exists) {
            revert CollateralStrategyNotMapped();
        }

        CollateralData storage collateralData = collateralInfo[_collateral];
        StrategyData storage strategyData = collateralStrategyInfo[_collateral][_strategy];

        // Calculate the new capacity used to ensure it's within bounds
        uint16 newCapacityUsed = collateralData.collateralCapacityUsed - strategyData.allocationCap + _allocationCap;
        Helpers._isLTEMaxPercentage(newCapacityUsed, "Allocation percentage exceeded");

        // Calculate the current allocated percentage
        uint256 totalCollateral = getCollateralInVault(_collateral) + getCollateralInStrategies(_collateral);
        uint256 currentAllocatedPer =
            (getCollateralInAStrategy(_collateral, _strategy) * Helpers.MAX_PERCENTAGE) / totalCollateral;

        // Ensure the new allocation percentage is greater than or equal to the currently allocated percentage
        if (_allocationCap < currentAllocatedPer) {
            revert AllocationPercentageLowerThanAllocatedAmt();
        }

        // Update the collateral data and strategy data
        collateralData.collateralCapacityUsed = newCapacityUsed;
        strategyData.allocationCap = _allocationCap;

        emit CollateralStrategyUpdated(_collateral, _strategy);
    }

    /// @notice Remove an existing strategy from collateral
    /// @param _collateral Address of the collateral
    /// @param _strategy Address of the strategy
    /// @dev Ensure all the collateral is removed from the strategy before calling this
    ///      Otherwise, it will create errors in collateral accounting
    function removeCollateralStrategy(address _collateral, address _strategy) external onlyOwner {
        // Check if the collateral and strategy are mapped
        // Ensure none of the collateral is deposited into the strategy
        // Remove collateral capacity and the strategy from the list
        if (!collateralStrategyInfo[_collateral][_strategy].exists) {
            revert CollateralStrategyNotMapped();
        }
        if (collateralInfo[_collateral].defaultStrategy == _strategy) {
            revert IsDefaultStrategy();
        }
        if (getCollateralInAStrategy(_collateral, _strategy) != 0) {
            revert CollateralStrategyInUse();
        }

        uint256 numStrategy = collateralStrategies[_collateral].length;

        for (uint256 i; i < numStrategy;) {
            if (collateralStrategies[_collateral][i] == _strategy) {
                collateralStrategies[_collateral][i] = collateralStrategies[_collateral][numStrategy - 1];
                collateralStrategies[_collateral].pop();
                collateralInfo[_collateral].collateralCapacityUsed -=
                    collateralStrategyInfo[_collateral][_strategy].allocationCap;
                delete collateralStrategyInfo[_collateral][_strategy];
                break;
            }

            unchecked {
                ++i;
            }
        }

        emit CollateralStrategyRemoved(_collateral, _strategy);
    }

    /// @notice Update the collateral's default strategy for redemption.
    /// @dev In case of redemption if there is not enough collateral in the vault,
    /// collateral is withdrawn from the defaultStrategy.
    /// @param _collateral Address of the collateral
    /// @param _strategy Address of the Strategy
    function updateCollateralDefaultStrategy(address _collateral, address _strategy) external onlyOwner {
        if (!collateralStrategyInfo[_collateral][_strategy].exists && _strategy != address(0)) {
            revert CollateralStrategyNotMapped();
        }
        collateralInfo[_collateral].defaultStrategy = _strategy;
    }

    /// @notice Validate allocation for a collateral
    /// @param _collateral Address of the collateral
    /// @param _strategy Address of the desired strategy
    /// @param _amount Amount to be allocated.
    /// @return True if the allocation request is valid, otherwise False.
    function validateAllocation(address _collateral, address _strategy, uint256 _amount) external view returns (bool) {
        // Check if collateral allocation is allowed
        if (!collateralInfo[_collateral].allocationAllowed) {
            revert CollateralAllocationPaused();
        }

        // Calculate the maximum collateral usage based on the allocation cap
        uint256 maxCollateralUsage = (
            collateralStrategyInfo[_collateral][_strategy].allocationCap
                * (getCollateralInVault(_collateral) + getCollateralInStrategies(_collateral))
        ) / Helpers.MAX_PERCENTAGE;

        // Get the collateral balance in the specified strategy
        uint256 collateralBalance = getCollateralInAStrategy(_collateral, _strategy);

        // Check if the allocation request is within the allowed limits
        if (maxCollateralUsage >= collateralBalance) {
            return ((maxCollateralUsage - collateralBalance) >= _amount);
        }

        return false;
    }

    /// @notice Get the required data for minting USDs with a collateral
    /// @param _collateral Address of the collateral
    /// @return mintData Mint configuration for the collateral
    function getMintParams(address _collateral) external view returns (CollateralMintData memory mintData) {
        // Retrieve collateral storage data
        CollateralData memory collateralStorageData = collateralInfo[_collateral];

        // Check if the collateral exists
        if (!collateralInfo[_collateral].exists) {
            revert CollateralDoesNotExist();
        }

        return CollateralMintData({
            mintAllowed: collateralStorageData.mintAllowed,
            baseFeeIn: collateralStorageData.baseFeeIn,
            downsidePeg: collateralStorageData.downsidePeg,
            desiredCollateralComposition: collateralStorageData.desiredCollateralComposition,
            conversionFactor: collateralStorageData.conversionFactor
        });
    }

    /// @notice Get the required data for redeeming USDs for collateral
    /// @param _collateral Address of the collateral
    /// @return redeemData Redeem configuration for the collateral
    function getRedeemParams(address _collateral) external view returns (CollateralRedeemData memory redeemData) {
        // Check if the collateral exists
        if (!collateralInfo[_collateral].exists) {
            revert CollateralDoesNotExist();
        }

        // Retrieve collateral storage data
        CollateralData memory collateralStorageData = collateralInfo[_collateral];

        return CollateralRedeemData({
            redeemAllowed: collateralStorageData.redeemAllowed,
            defaultStrategy: collateralStorageData.defaultStrategy,
            baseFeeOut: collateralStorageData.baseFeeOut,
            desiredCollateralComposition: collateralStorageData.desiredCollateralComposition,
            conversionFactor: collateralStorageData.conversionFactor
        });
    }

    /// @notice Gets a list of all listed collaterals
    /// @return List of addresses representing all listed collaterals
    function getAllCollaterals() external view returns (address[] memory) {
        return collaterals;
    }

    /// @notice Gets a list of all strategies linked to a collateral
    /// @param _collateral Address of the collateral
    /// @return List of addresses representing available strategies for the collateral
    function getCollateralStrategies(address _collateral) external view returns (address[] memory) {
        return collateralStrategies[_collateral];
    }

    /// @notice Verifies if a strategy is linked to a collateral
    /// @param _collateral Address of the collateral
    /// @param _strategy Address of the strategy
    /// @return True if the strategy is linked to the collateral, otherwise False
    function isValidStrategy(address _collateral, address _strategy) external view returns (bool) {
        return collateralStrategyInfo[_collateral][_strategy].exists;
    }

    /// @notice Get the amount of collateral in all Strategies
    /// @param _collateral Address of the collateral
    /// @return amountInStrategies Amount in strategies
    function getCollateralInStrategies(address _collateral) public view returns (uint256 amountInStrategies) {
        uint256 numStrategy = collateralStrategies[_collateral].length;

        for (uint256 i; i < numStrategy;) {
            amountInStrategies += IStrategy(collateralStrategies[_collateral][i]).checkBalance(_collateral);
            unchecked {
                ++i;
            }
        }

        return amountInStrategies;
    }

    /// @notice Get the amount of collateral in the vault
    /// @param _collateral Address of the collateral
    /// @return amountInVault Amount in Vault
    function getCollateralInVault(address _collateral) public view returns (uint256 amountInVault) {
        return IERC20(_collateral).balanceOf(VAULT);
    }

    /// @notice Get the amount of collateral allocated in a strategy
    /// @param _collateral Address of the collateral
    /// @param _strategy Address of the strategy
    /// @return allocatedAmt Allocated amount
    function getCollateralInAStrategy(address _collateral, address _strategy)
        public
        view
        returns (uint256 allocatedAmt)
    {
        return IStrategy(_strategy).checkBalance(_collateral);
    }
}
