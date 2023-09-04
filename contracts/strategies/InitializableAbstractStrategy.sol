//SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Helpers} from "../libraries/Helpers.sol";

interface IStrategyVault {
    function yieldReceiver() external view returns (address);
}

abstract contract InitializableAbstractStrategy is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    address public vault;
    uint16 public withdrawSlippage;
    uint16 public depositSlippage;
    uint16 public harvestIncentiveRate;
    address[] internal assetsMapped;
    address[] public rewardTokenAddress;
    mapping(address => address) public assetToPToken;

    /* solhint-disable-next-line var-name-mixedcase*/
    uint256[40] private __gap__;

    event VaultUpdated(address newVaultAddr);
    event YieldReceiverUpdated(address newYieldReceiver);
    event PTokenAdded(address indexed asset, address pToken);
    event PTokenRemoved(address indexed asset, address pToken);
    event Deposit(address indexed asset, address pToken, uint256 amount);
    event Withdrawal(address indexed asset, address pToken, uint256 amount);
    event SlippageUpdated(uint16 depositSlippage, uint16 withdrawSlippage);
    event HarvestIncentiveCollected(
        address indexed token,
        address indexed harvestor,
        uint256 amount
    );
    event HarvestIncentiveRateUpdated(uint16 newRate);
    event InterestCollected(
        address indexed asset,
        address indexed recipient,
        uint256 amount
    );
    event RewardTokenCollected(
        address indexed rwdToken,
        address indexed recipient,
        uint256 amount
    );

    error CallerNotVault(address caller);
    error CallerNotVaultOrOwner(address caller);
    error PTokenAlreadySet(address collateral, address pToken);
    error InvalidIndex();
    error CollateralNotSupported(address asset);
    error InvalidAssetLpPair(address asset, address lpToken);
    error CollateralAllocated(address asset);

    modifier onlyVault() {
        if (msg.sender != vault) revert CallerNotVault(msg.sender);
        _;
    }

    modifier onlyVaultOrOwner() {
        if (!(msg.sender == vault || msg.sender == owner()))
            revert CallerNotVaultOrOwner(msg.sender);
        _;
    }

    // Disabling initializer for the implementation contract.
    constructor() {
        _disableInitializers();
    }

    /// @notice Update the linked vault contract
    /// @param _newVault Address of the new Vault
    function updateVault(address _newVault) external onlyOwner {
        Helpers._isNonZeroAddr(_newVault);
        vault = _newVault;
        emit VaultUpdated(_newVault);
    }

    /// @notice Updates the HarvestIncentive rate for the user
    /// @param _newRate new Desired rate
    function updateHarvestIncentiveRate(uint16 _newRate) external onlyOwner {
        Helpers._isLTEMaxPercentage(_newRate);
        harvestIncentiveRate = _newRate;
        emit HarvestIncentiveRateUpdated(_newRate);
    }

    /// @dev Deposit an amount of asset into the platform
    /// @param _asset Address for the asset
    /// @param _amount Units of asset to deposit
    function deposit(address _asset, uint256 _amount) external virtual;

    /// @dev Withdraw an amount of asset from the platform.
    /// @param _recipient Address to which the asset should be sent
    /// @param _asset Address of the asset
    /// @param _amount Units of asset to withdraw
    /// @return amountReceived The actual amount received
    function withdraw(
        address _recipient,
        address _asset,
        uint256 _amount
    ) external virtual returns (uint256 amountReceived);

    /// @dev Withdraw an amount of asset from the platform to vault
    /// @param _asset  Address of the asset
    /// @param _amount  Units of asset to withdraw
    function withdrawToVault(
        address _asset,
        uint256 _amount
    ) external virtual returns (uint256 amount);

    /// @notice Withdraw the interest earned of asset from the platform.
    /// @param _asset Address of the asset
    function collectInterest(address _asset) external virtual;

    /// @notice Collect accumulated reward token and send to Vault
    function collectReward() external virtual;

    /// @notice Get the amount of a specific asset held in the strategy,
    ///           excluding the interest
    /// @dev Curve: assuming balanced withdrawal
    /// @param _asset Address of the asset
    function checkBalance(
        address _asset
    ) external view virtual returns (uint256);

    /// @notice Get the amount of a specific asset held in the strategy,
    ///         excluding the interest and any locked liquidity that is not
    ///         available for instant withdrawal
    /// @dev Curve: assuming balanced withdrawal
    /// @param _asset Address of the asset
    function checkAvailableBalance(
        address _asset
    ) external view virtual returns (uint256);

    /// @notice AAVE: Get the interest earned on a specific asset
    /// Curve: Get the total interest earned
    /// @dev Curve: to avoid double-counting, _asset has to be of index
    ///           'entryTokenIndex'
    /// @param _asset Address of the asset
    function checkInterestEarned(
        address _asset
    ) external view virtual returns (uint256);

    /// @notice Get the amount of claimable reward
    function checkRewardEarned() external view virtual returns (uint256);

    /// @notice Get the total LP token balance for a asset.
    /// @param _asset Address of the asset.
    function checkLPTokenBalance(
        address _asset
    ) external view virtual returns (uint256);

    /// @notice Check if an asset/collateral is supported.
    /// @param _asset Address of the asset
    /// @return bool Whether asset is supported
    function supportsCollateral(
        address _asset
    ) external view virtual returns (bool);

    /// @notice Change to a new depositSlippage & withdrawSlippage
    /// @param _depositSlippage Slippage tolerance for allocation
    /// @param _withdrawSlippage Slippage tolerance for withdrawal
    function updateSlippage(
        uint16 _depositSlippage,
        uint16 _withdrawSlippage
    ) public onlyOwner {
        Helpers._isLTEMaxPercentage(_depositSlippage);
        Helpers._isLTEMaxPercentage(_withdrawSlippage);
        depositSlippage = _depositSlippage;
        withdrawSlippage = _withdrawSlippage;
        emit SlippageUpdated(_depositSlippage, _withdrawSlippage);
    }

    /// @notice Initialize the base properties of the strategy
    /// @param _vault Address of the USDs Vault
    /// @param _depositSlippage Allowed max slippage for Deposit
    /// @param _withdrawSlippage Allowed max slippage for withdraw
    function _initialize(
        address _vault,
        uint16 _depositSlippage,
        uint16 _withdrawSlippage
    ) internal {
        OwnableUpgradeable.__Ownable_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
        Helpers._isNonZeroAddr(_vault);
        updateSlippage(_depositSlippage, _withdrawSlippage);
        vault = _vault;
        harvestIncentiveRate = 10;
    }

    ///  @notice Provide support for asset by passing its pToken address.
    ///       Add to internal mappings and execute the platform specific,
    ///  abstract method `_abstractSetPToken`
    ///  @param _asset Address for the asset
    ///  @param _pToken Address for the corresponding platform token
    function _setPTokenAddress(address _asset, address _pToken) internal {
        address currentPToken = assetToPToken[_asset];
        if (currentPToken != address(0))
            revert PTokenAlreadySet(_asset, currentPToken);
        Helpers._isNonZeroAddr(_asset);
        Helpers._isNonZeroAddr(_pToken);

        assetToPToken[_asset] = _pToken;
        assetsMapped.push(_asset);

        emit PTokenAdded(_asset, _pToken);
        // Perform any strategy specific logic.
        _abstractSetPToken(_asset, _pToken);
    }

    /// @notice Remove a supported asset by passing its index.
    ///      This method can only be called by the system owner
    /// @param _assetIndex Index of the asset to be removed
    function _removePTokenAddress(
        uint256 _assetIndex
    ) internal returns (address asset) {
        uint256 numAssets = assetsMapped.length;
        if (_assetIndex >= numAssets) revert InvalidIndex();
        asset = assetsMapped[_assetIndex];
        address pToken = assetToPToken[asset];

        assetsMapped[_assetIndex] = assetsMapped[numAssets - 1];
        assetsMapped.pop();
        delete assetToPToken[asset];

        emit PTokenRemoved(asset, pToken);
    }

    /// @notice Splits and sends the accumulated rewards to harvestor and yield receiver
    /// @param _token Address of the reward token
    /// @param _yieldReceiver Address of the yield receiver
    /// @param _harvestor Address of the harvestor
    /// @param _amount to be split and sent
    /// @dev Sends the amount to harvestor as per `harvestIncentiveRate` and sends the rest to yield receiver
    function _splitAndSendReward(
        address _token,
        address _yieldReceiver,
        address _harvestor,
        uint256 _amount
    ) internal returns (uint256) {
        if (harvestIncentiveRate > 0) {
            uint256 incentiveAmt = (_amount * harvestIncentiveRate) /
                Helpers.MAX_PERCENTAGE;
            uint256 harvestedAmt = _amount - incentiveAmt;
            IERC20(_token).safeTransfer(_harvestor, incentiveAmt);
            IERC20(_token).safeTransfer(_yieldReceiver, _amount - incentiveAmt);
            emit HarvestIncentiveCollected(_token, _harvestor, incentiveAmt);
            return harvestedAmt;
        }
        IERC20(_token).safeTransfer(_yieldReceiver, _amount);
        return _amount;
    }

    /// @notice Call the necessary approvals for the underlying strategy
    /// @param _asset Address of the asset
    /// @param _pToken Address of the corresponding receipt token.
    function _abstractSetPToken(
        address _asset,
        address _pToken
    ) internal virtual;
}
