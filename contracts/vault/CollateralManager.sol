// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ICollateralManager} from "./interfaces/ICollateralManager.sol";
import {IStrategy} from "./interfaces/IStrategy.sol";

contract CollateralManager is ICollateralManager, Ownable {
    using SafeERC20 for IERC20;

    struct CollateralStorageData {
        bool mintAllowed;
        bool redeemAllowed;
        bool allocationAllowed;
        bool exists;
        address defaultStrategy;
        uint16 baseFeeIn;
        uint16 baseFeeOut;
        uint16 upsidePeg;
        uint16 downsidePeg;
        uint256 collateralCapacityUsed;
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
        uint32 allocationCap;
        bool exists;
    }

    uint32 public numCollaterals;
    uint32 public numCollateralStrategy;
    address public vaultCore;
    address[] private collaterals;
    mapping(address => CollateralStorageData) public collateralInfo;
    mapping(address => mapping(address => StrategyData))
        private collateralStrategyInfo;

    mapping(address => address[]) private collateralStrategies;

    uint256 public constant PERC_PRECISION = 1000;
    uint256 public constant ALLC_PERC_PRECISION = 10 ** 5;

    event CollateralAdded(address collateral, CollateralData data);
    event CollateralRemoved(address collateral);
    event CollateralInfoUpdated(address collateral, CollateralData data);
    event CollateralStrategyAdded(address collateral, address strategy);
    event CollateralStrategyUpdated(address collateral, address strategy);
    event CollateralStrategyRemoved(address collateral, address strategy);

    /// @notice Register a collateral for mint & redeem in USDs
    /// @param _collateral Address of the collateral
    /// @param _data Collateral configuration data
    function addCollateral(
        address _collateral,
        CollateralData memory _data
    ) external onlyOwner {
        // Test if collateral is already added
        // Initialize collateral storage data
        require(
            !collateralInfo[_collateral].exists,
            "Collateral already exists"
        );

        require(
            _data.downsidePeg <= PERC_PRECISION &&
                _data.upsidePeg <= PERC_PRECISION,
            "Illegal Peg input"
        );

        require(
            _data.baseFeeIn <= PERC_PRECISION &&
                _data.baseFeeOut <= PERC_PRECISION,
            "Illegal BaseFee input"
        );

        collateralInfo[_collateral] = CollateralStorageData({
            mintAllowed: _data.mintAllowed,
            redeemAllowed: _data.redeemAllowed,
            allocationAllowed: _data.allocationAllowed,
            defaultStrategy: address(0),
            baseFeeIn: _data.baseFeeIn,
            baseFeeOut: _data.baseFeeOut,
            upsidePeg: _data.upsidePeg,
            downsidePeg: _data.downsidePeg,
            collateralCapacityUsed: 0,
            exists: true
        });

        collaterals.push(_collateral);

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
        require(collateralInfo[_collateral].exists, "Collateral doen't exist");
        require(
            _updateData.downsidePeg <= PERC_PRECISION &&
                _updateData.upsidePeg <= PERC_PRECISION,
            "Illegal Peg input"
        );

        require(
            _updateData.baseFeeIn <= PERC_PRECISION &&
                _updateData.baseFeeOut <= PERC_PRECISION,
            "Illegal BaseFee input"
        );

        CollateralStorageData storage data = collateralInfo[_collateral];
        data.mintAllowed = _updateData.mintAllowed;
        data.redeemAllowed = _updateData.redeemAllowed;
        data.allocationAllowed = _updateData.allocationAllowed;
        data.baseFeeIn = _updateData.baseFeeIn;
        data.baseFeeOut = _updateData.baseFeeOut;
        data.upsidePeg = _updateData.upsidePeg;
        data.downsidePeg = _updateData.downsidePeg;

        emit CollateralInfoUpdated(_collateral, _updateData);
    }

    /// @notice Unlist a collateral
    /// @param _collateral Address of the collateral
    function removeCollateral(address _collateral) external onlyOwner {
        require(collateralInfo[_collateral].exists, "Collateral doen't exist");
        require(
            collateralStrategies[_collateral].length == 0,
            "Strategy/ies exists"
        );

        uint256 numCollateral = collaterals.length;

        for (uint256 i = 0; i < numCollateral; ) {
            if (collaterals[i] == _collateral) {
                collaterals[i] = collaterals[numCollateral - 1];
                collaterals.pop();
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
    /// @param _allocationPer Allocation capacity
    function addCollateralStrategy(
        address _collateral,
        address _strategy,
        uint32 _allocationPer
    ) external onlyOwner {
        // Check if the collateral is valid
        // Check if collateral strategy not allready added.
        // Check if _allocation Per <= 100 - collateralCapcityUsed
        // Check if collateral is allocation is supported by the strategy.
        // add info to collateral mapping

        require(collateralInfo[_collateral].exists, "Collateral doen't exist");
        require(
            !collateralStrategyInfo[_collateral][_strategy].exists,
            "Strategy already mapped"
        );
        require(
            IStrategy(_strategy).supportsCollateral(_collateral),
            "Collateral not supported"
        );

        require(
            _allocationPer <=
                (ALLC_PERC_PRECISION -
                    collateralInfo[_collateral].collateralCapacityUsed),
            "AllocationPer  exceeded"
        );

        collateralStrategyInfo[_collateral][_strategy] = StrategyData(
            _allocationPer,
            true
        );
        collateralStrategies[_collateral].push(_strategy);
        collateralInfo[_collateral].collateralCapacityUsed += _allocationPer;

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
        require(
            collateralStrategyInfo[_collateral][_strategy].exists,
            "Strategy doen't exist"
        );

        CollateralStorageData storage collateralData = collateralInfo[
            _collateral
        ];
        StrategyData storage strategyData = collateralStrategyInfo[_collateral][
            _strategy
        ];

        uint256 newCapacityUsed = collateralData.collateralCapacityUsed -
            strategyData.allocationCap +
            _allocationPer;
        uint256 totalCollateral = getCollateralInVault(_collateral) +
            getCollateralInStrategies(_collateral);
        uint256 currentAllocatedPer = (getCollateralInAStrategy(
            _collateral,
            _strategy
        ) * ALLC_PERC_PRECISION) / totalCollateral;

        require(
            _allocationPer <= (ALLC_PERC_PRECISION - newCapacityUsed),
            "AllocationPer exceeded"
        );
        require(
            _allocationPer < currentAllocatedPer,
            "AllocationPer not valid"
        );

        collateralData.collateralCapacityUsed = newCapacityUsed;
        strategyData.allocationCap = _allocationPer;

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
        require(
            collateralStrategyInfo[_collateral][_strategy].exists,
            "Strategy doen't exist"
        );

        require(
            collateralInfo[_collateral].defaultStrategy != _strategy,
            "DS removal not allowed"
        );

        require(
            IStrategy(_strategy).checkBalance(_collateral) == 0,
            "Strategy in use"
        );

        uint256 numStrategy = collateralStrategies[_collateral].length;

        for (uint256 i = 0; i < numStrategy; ) {
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

    /// @notice Update the collateral's default strategy for redemption.
    /// @dev In case of redemption if there is not enough collateral in vault
    /// collateral is withdrawn from the defaultStrategy.
    /// @param _collateral Address of the collateral
    /// @param _strategy Address of the Strategy
    function updateCollateralDefaultStrategy(
        address _collateral,
        address _strategy
    ) external onlyOwner {
        require(collateralInfo[_collateral].exists, "Collateral doen't exist");
        collateralInfo[_collateral].defaultStrategy = _strategy;
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
        require(
            collateralInfo[_collateral].allocationAllowed,
            "Allocation not allowed"
        );

        uint256 maxCollateralUsage = (collateralStrategyInfo[_collateral][
            _strategy
        ].allocationCap *
            (getCollateralInVault(_collateral) +
                getCollateralInStrategies(_collateral))) / ALLC_PERC_PRECISION;

        return ((maxCollateralUsage -
            IStrategy(_strategy).checkBalance(_collateral)) >= _amount);
    }

    /// @notice Get the required data for mint
    /// @param _collateral Address of the collateral
    /// @return mintData
    function getMintParams(
        address _collateral
    ) external view returns (CollateralMintData memory mintData) {
        require(collateralInfo[_collateral].exists, "Collateral doen't exist");

        // Check if collateral exists
        // Compose and return collateral mint params

        CollateralStorageData memory collateralStorageData = collateralInfo[
            _collateral
        ];

        return
            CollateralMintData({
                mintAllowed: collateralStorageData.mintAllowed,
                baseFeeIn: collateralStorageData.baseFeeIn,
                upsidePeg: collateralStorageData.upsidePeg
            });
    }

    /// @notice Get the required data for USDs redemption
    /// @param _collateral Address of the collateral
    /// @return redeemData
    function getRedeemParams(
        address _collateral
    ) external view returns (CollateralRedeemData memory redeemData) {
        require(collateralInfo[_collateral].exists, "Collateral doen't exist");
        // Check if collateral exists
        // Compose and return collateral redeem params

        CollateralStorageData memory collateralStorageData = collateralInfo[
            _collateral
        ];

        return
            CollateralRedeemData({
                redeemAllowed: collateralStorageData.redeemAllowed,
                defaultStrategy: collateralStorageData.defaultStrategy,
                baseFeeOut: collateralStorageData.baseFeeOut,
                downsidePeg: collateralStorageData.downsidePeg
            });
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
    ) external view returns (address[] memory) {
        return collateralStrategies[_collateral];
    }

    /// @notice Get the amount of collateral in all Strategies
    /// @param _collateral Address of the collateral
    /// @return amountInStrategies
    function getCollateralInStrategies(
        address _collateral
    ) public view returns (uint256 amountInStrategies) {
        amountInStrategies = 0;

        uint256 numStrategy = collateralStrategies[_collateral].length;

        for (uint256 i = 0; i < numStrategy; ) {
            amountInStrategies =
                amountInStrategies +
                IStrategy(collateralStrategies[_collateral][i]).checkBalance(
                    _collateral
                );
            unchecked {
                ++i;
            }
        }

        return amountInStrategies;
    }

    /// @notice Get the amount of collateral in vault
    /// @param _collateral Address of the collateral
    /// @return amountInVault
    function getCollateralInVault(
        address _collateral
    ) public view returns (uint256 amountInVault) {
        return IERC20(_collateral).balanceOf(vaultCore);
    }

    /// @notice Get the amount of collateral allocated in a strategy
    /// @param _collateral Address of the collateral
    /// @param _strategy Address of the strategy
    /// @return allocatedAmt
    function getCollateralInAStrategy(
        address _collateral,
        address _strategy
    ) public view returns (uint256 allocatedAmt) {
        return IStrategy(_strategy).checkBalance(_collateral);
    }
}
