// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ICollateralManager} from "./interfaces/ICollateralManager.sol";

contract CollateralManager is ICollateralManager, Ownable {
    struct CollateralStorageData {
        bool mintAllowed;
        bool redeemAllowed;
        bool allocationAllowed;
        address defaultStrategy;
        uint8 baseFeeIn;
        uint8 baseFeeOut;
        uint16 upsidePeg;
        uint16 downsidePeg;
        uint16 collateralCapacityUsed;
        bool exists;
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
        uint16 allocationCap;
        bool exits;
    }

    struct CollateralMintData{
        bool mintAllowed;
        uint16 baseFeeIn;
        uint16 upsidePeg;
    }

    struct CollateralRedeemData{
        bool redeemAllowed;
        uint16 baseFeeOut;
        uint16 downsidePeg;
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
    event CollateralStrategyAdded(address collateral, address strategy);
    event CollateralStrategyUpdate(address collateral, address strategy);

    /// @notice Register a collateral for mint & redeem in USDs
    /// @param _collateral Address of the collateral
    /// @param _data Collateral configuration data
    function addCollateral(
        address _collateral,
        CollateralData memory _data
    ) external onlyOwner {
        // Test if collateral is already added
        // Initialize collateral storage data
        require(_collateral != address(0), "Illegal input");
        require(
            collateralInfo[_collateral].exist != true,
            "Collateral already exists"
        );

        collateralInfo[_collateral] =  CollateralStorageData(
            _data.mintAllowed, 
            _data.redeemAllowed, 
            _data.allocationAllowed, 
            address(0)
            _data.baseFeeIn, 
            _data.baseFeeOut, 
            _data.upsidePeg, 
            _data.downsidePeg
            0,
            true
        )

        collaterals.push(_collateral)

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

        require(_collateral != address(0), "Illegal input");
        require(
            collateralInfo[_collateral].exist == true,
            "Collateral doen't exist"
        );
        emit CollateralInfoUpdated(_collateral, _updateData);
    }

    /// @notice Unlist a collateral
    /// @param _collateral Address of the collateral
    function removeCollateral(address _collateral) external onlyOwner {
        require(_collateral != address(0), "Illegal input");
        require(
            collateralInfo[_collateral].exist == true,
            "Collateral doen't exist"
        );
        // Check if collateral is added
        // Check if collateral is safe to remove, i.e it is not there in the vault/strategies.

        for (uint256 i = 0; i < collaterals.length; ++i) {
            if (collaterals[i] == _collateral) {
                collaterals[i] = collaterals[collaterals.length - 1];
                collaterals.pop();
                delete (collateralInfo[_collateral]);
                break;
            }
        }

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

        require(_collateral != address(0), "Illegal input");
        require(collateralInfo[_collateral].exist == true, "Collateral doen't exist");
        require(collateralStrategyInfo[_collateral][_strategy].exist != true, "Strategy already exists");
        require(collateralInfo[_collateral].allocationAllowed == true, "Allocation not allowed");
        require(_allocationPer > (100 - collateralInfo[_collateral].collateralCapacityUsed), "AllocationPer  exceeded");
      

        collateralStrategyInfo[_collateral][_strategy] = StrategyData(_allocationPer, true)
        collateralStrategies[_collateral].push(_strategy);
        
        emit CollateralStrategyAdded(_collateral, _strategy);
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
        require(collateralInfo[_collateral].exist == true, "Collateral doen't exist");
        require(collateralStrategyInfo[_collateral][_strategy].exist == true, "Strategy doen't exist");
        require(_allocationPer > (100 - collateralInfo[_collateral].collateralCapacityUsed), "AllocationPer  exceeded");

        collateralStrategyInfo[_collateral][_strategy] = StrategyData(_allocationPer, true)

        CollateralStrategyUpdate(_collateral, _strategy);
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
        require(collateralStrategyInfo[_collateral][_strategy].exist == true, "Strategy doen't exist");

    }

    /// @notice Update the collateral's default strategy for redemption.
    /// @dev In case of redemption if there is not enough collateral in vault
    /// collateral is withdrawn from the defaultStrategy.
    /// @param _collateral Address of the collateral
    /// @param _strategy Address of the Strategy
    function updateCollateralDefaultStrategy(
        address _collateral,
        address _strategy
    ) external onlyOwner {
        require(_collateral != address(0) || _strategy != address(0), "Illegal input");
        require(collateralInfo[_collateral].exist == true, "Collateral doen't exist");
        collateralInfo[_collateral].defaultStrategy = _strategy

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
    ) external view returns (bool) {

    }

    /// @notice Get the required data for mint
    /// @param _collateral Address of the collateral
    /// @return mintData
    function getMintParams(
        address _collateral
    ) external view returns (CollateralMintData memory mintData) {
        require(_collateral != address(0), "Illegal input");
        require(collateralInfo[_collateral].exist == true, "Collateral doen't exist");

        // Check if collateral exists
        // Compose and return collateral mint params
        return CollateralMintData(
            collateralInfo[_collateral].mintAllowed, 
            collateralInfo[_collateral].baseFeeIn,  
            collateralInfo[_collateral].upsidePeg);
    }

    /// @notice Get the required data for USDs redemption
    /// @param _collateral Address of the collateral
    /// @return redeemData
    function getRedeemParams(
        address _collateral
    ) external view returns (CollateralRedeemData memory redeemData) {
        require(_collateral != address(0), "Illegal input");
        require(collateralInfo[_collateral].exist == true, "Collateral doen't exist");
        // Check if collateral exists
        // Compose and return collateral redeem params

        return CollateralRedeemData{
            collateralInfo[_collateral].redeemAllowed,
            collateralInfo[_collateral].baseFeeOut,
            collateralInfo[_collateral].downsidePeg
        );
    }

    /// @notice Gets list of all the listed collateral
    /// @return address[] of listed collaterals
    function getAllCollaterals() external view returns (address[] memory) {
        address[] collaterals;
        return collaterals;
    }

    /// @notice Gets list of all the collateral linked strategies
    /// @return address[] list of available strategies for a collateral
    function getCollateralStrategies(
        address _collateral
    ) external view returns (address[] memory) {
        return collateralStrategies[_collateral];
    }

    /// @notice Get the amount of collateral in all Strategies
    /// @param _collateral Address of the collateral
    /// @return amountInStrategies
    function getCollateralInStrategies(
        address _collateral
    ) public view returns (uint256 amountInStrategies) {

    }

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
    ) public view returns (uint256 allocatedAmt) {

    }
}
