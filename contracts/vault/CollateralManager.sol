// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ICollateralManager} from "./interfaces/ICollateralManager.sol";

contract CollateralManager is ICollateralManager, Ownable {
    struct CollateralStorageData {
        bool mintAllowed;
        bool redeemAllowed;
        bool allocationAllowed;
        address defaultStrategy;
        uint8 id;
        uint8 baseFeeIn;
        uint8 baseFeeOut;
        uint16 upsidePeg;
        uint16 downsidePeg;
        uint16 collateralCapacityUsed;
    }

    struct CollateralData {
        bool mintAllowed;
        bool redeemAllowed;
        bool allocationAllowed;
        uint16 baseFeeIn;
        uint16 baseFeeOut;
        uint16 upsidePeg;
        uint16 downsidePeg;
    }

    struct StrategyData {
        uint8 id;
        uint16 allocationCap;
    }

    uint32 public numCollaterals;
    uint32 public numCollateralStrategy;
    address public vaultCore;
    address[] private collaterals;
    mapping(address => CollateralStorageData) public collateralInfo;
    mapping(address => mapping(address => StrategyData))
        private collateralStrategyInfo;
    mapping(address => address[]) private collateralStrategies;

    event CollateralAdded(address collateral, CollateralData data);
    event CollateralRemoved(address collateral);
    event CollateralInfoUpdated(address collateral, CollateralData data);

    /// @notice Register a collateral for mint & redeem in USDs
    /// @param _collateral Address of the collateral
    /// @param _data Collateral configuration data
    function addCollateral(
        address _collateral,
        CollateralData memory _data
    ) external onlyOwner {
        // Test if collateral is already added
        // Initialize collateral storage data
        emit CollateralAdded(_collateral, _data);
    }

    /// @notice Update existing collateral configuration
    /// @param _collateral Address of the collateral
    /// @param _updateData Updated configuration for the collateral
    function updateCollateralData(
        address _collateral,
        CollateralData memory _updateData
    ) external onlyOwner {
        // Check if collateral added;
        // Update the collateral storage data
        emit CollateralInfoUpdated(_collateral, _updateData);
    }

    /// @notice Unlist a collateral
    /// @param _collateral Address of the collateral
    function removeCollateral(address _collateral) external onlyOwner {
        // Check if collateral is added
        // Check if collateral is safe to remove, i.e it is not there in the vault/strategies.
        emit CollateralRemoved(_collateral);
    }

    /// @notice Add a new strategy to collateral
    /// @param _collateral Address of the collateral
    /// @param _strategy Address of the strategy
    /// @param _allocationPer Allocation capacity
    function addCollateralStrategy(
        address _collateral,
        address _strategy,
        uint16 _allocationPer
    ) external onlyOwner {
        // Check if the collateral is valid
        // Check if collateral strategy not allready added.
        // Check if _allocation Per <= 100 - collateralCapcityUsed
        // Check if collateral is allocation is supported by the strategy.
        // add info to collateral mapping
        // use id = index + 1.
    }

    /// @notice Update existing strategy for collateral
    /// @param _collateral Address of the collateral
    /// @param _strategy Address of the strategy
    /// @param _allocationPer Allocation capacity
    function updateCollateralStrategy(
        address _collateral,
        address _strategy,
        uint16 _allocationPer
    ) external onlyOwner {
        // Check if collateral and strategy are mapped
        // Check if _allocationPer <= 100 - collateralCapacityUsed  + oldAllocationPer
        // Update the info
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
    }

    /// @notice Update the collateral's default strategy for redemption.
    /// @dev In case of redemption if there is not enough collateral in vault
    ///      collateral is withdrawn from the defaultStrategy.
    /// @param _collateral Address of the collateral
    /// @param _strategy Address of the Strategy
    function updateCollateralDefaultStrategy(
        address _collateral,
        address _strategy
    ) external onlyOwner {
        // Check
    }

    /// @notice Validate allocation for a collateral
    /// @param _collateral Address of the collateral
    /// @param _strategy Address of the desired strategy
    /// @param _amount Amount to be allocated.
    /// @return True for valid allocation request.
    function validateAllocation(
        address _collateral,
        address _strategy,
        uint256 _amount
    ) external view returns (bool) {}

    /// @notice Get the required data for mint
    /// @param _collateral Address of the collateral
    /// @return mintData
    function getMintParams(
        address _collateral
    ) external view returns (CollateralMintData memory mintData) {
        // Check if collateral exists
        // Compose and return collateral mint params
    }

    /// @notice Get the required data for USDs redemption
    /// @param _collateral Address of the collateral
    /// @return redeemData
    function getRedeemParams(
        address _collateral
    ) external view returns (CollateralRedeemData memory redeemData) {
        // Check if collateral exists
        // Compose and return collateral redeem params
    }

    /// @notice Gets list of all the listed collateral
    /// @return address[] of listed collaterals
    function getAllCollaterals() external view returns (address[] memory) {
        return collaterals;
    }

    /// @notice Gets list of all the collateral linked strategies
    /// @return address[] list of available strategies for a collateral
    function getCollateralStrategies(
        address _collateral
    ) public view returns (address[] memory) {
        return collateralStrategies[_collateral];
    }

    /// @notice Get the amount of collateral in all Strategies
    /// @param _collateral Address of the collateral
    /// @return amountInStrategies
    function getCollateralInStrategies(
        address _collateral
    ) public view returns (uint256 amountInStrategies) {}

    /// @notice Get the amount of collateral in vault
    /// @param _collateral Address of the collateral
    /// @return amountInVault
    function getCollateralInVault(
        address _collateral
    ) public view returns (uint256 amountInVault) {}

    /// @notice Get the amount of collateral allocated in a strategy
    /// @param _collateral Address of the collateral
    /// @param _strategy Address of the strategy
    /// @return allocatedAmt
    function getCollateralInAStrategy(
        address _collateral,
        address _strategy
    ) public view returns (uint256 allocatedAmt) {}

    function isValidStrategy(
        address _collateral,
        address _strategy
    ) public view returns (bool) {
        address[] memory _validStrategies = getCollateralStrategies(
            _collateral
        );
        for (uint8 i = 0; i < _validStrategies.length; ++i) {
            if (_validStrategies[i] == _strategy) {
                return true;
            }
        }
        return false;
    }
}
