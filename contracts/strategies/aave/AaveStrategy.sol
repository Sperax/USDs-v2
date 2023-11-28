// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {InitializableAbstractStrategy, Helpers, IStrategyVault} from "../InitializableAbstractStrategy.sol";
import {IAaveLendingPool, IAToken, IPoolAddressesProvider} from "./interfaces/IAavePool.sol";

/// @title AAVE strategy for USDs protocol
/// @author Sperax Foundation
/// @notice A yield earning strategy for USDs protocol
contract AaveStrategy is InitializableAbstractStrategy {
    using SafeERC20 for IERC20;

    uint16 private constant REFERRAL_CODE = 0;
    IAaveLendingPool public aavePool;
    mapping(address => uint256) public allocatedAmount; // Tracks the allocated amount of an asset.

    error NoRewardIncentive();

    /// @notice Initializer for setting up strategy internal state. This overrides the
    /// InitializableAbstractStrategy initializer as AAVE needs several extra
    /// addresses for the rewards program.
    /// @param _platformAddress Address of the AAVE pool
    /// @param _vault Address of the vault
    function initialize(
        address _platformAddress, // AAVE PoolAddress provider 0xa97684ead0e402dC232d5A977953DF7ECBaB3CDb
        address _vault
    ) external initializer {
        Helpers._isNonZeroAddr(_platformAddress);
        aavePool = IAaveLendingPool(IPoolAddressesProvider(_platformAddress).getPool()); // aave Lending Pool 0x794a61358D6845594F94dc1DB02A252b5b4814aD

        InitializableAbstractStrategy._initialize({_vault: _vault, _depositSlippage: 0, _withdrawSlippage: 0});
    }

    /// @notice Provide support for asset by passing its lpToken address.
    ///      This method can only be called by the system owner
    /// @param _asset    Address for the asset
    /// @param _lpToken   Address for the corresponding platform token
    function setPTokenAddress(address _asset, address _lpToken) external onlyOwner {
        _setPTokenAddress(_asset, _lpToken);
    }

    /// @notice Remove a supported asset by passing its index.
    ///      This method can only be called by the system owner
    /// @param _assetIndex Index of the asset to be removed
    function removePToken(uint256 _assetIndex) external onlyOwner {
        address asset = _removePTokenAddress(_assetIndex);
        if (allocatedAmount[asset] != 0) {
            revert CollateralAllocated(asset);
        }
    }

    /// @inheritdoc InitializableAbstractStrategy
    function deposit(address _asset, uint256 _amount) external override onlyVault nonReentrant {
        if (!supportsCollateral(_asset)) revert CollateralNotSupported(_asset);
        Helpers._isNonZeroAmt(_amount);
        // Following line also doubles as a check that we are depositing
        // an asset that we support.
        allocatedAmount[_asset] += _amount;

        IERC20(_asset).safeTransferFrom(msg.sender, address(this), _amount);
        IERC20(_asset).safeIncreaseAllowance(address(aavePool), _amount);
        aavePool.supply(_asset, _amount, address(this), REFERRAL_CODE);

        emit Deposit(_asset, _amount);
    }

    /// @inheritdoc InitializableAbstractStrategy
    function withdraw(address _recipient, address _asset, uint256 _amount)
        external
        override
        onlyVault
        nonReentrant
        returns (uint256)
    {
        uint256 amountReceived = _withdraw(_recipient, _asset, _amount);
        return amountReceived;
    }

    /// @inheritdoc InitializableAbstractStrategy
    function withdrawToVault(address _asset, uint256 _amount)
        external
        override
        onlyOwner
        nonReentrant
        returns (uint256)
    {
        uint256 amountReceived = _withdraw(vault, _asset, _amount);
        return amountReceived;
    }

    /// @inheritdoc InitializableAbstractStrategy
    function collectInterest(address _asset) external override nonReentrant {
        address yieldReceiver = IStrategyVault(vault).yieldReceiver();
        uint256 assetInterest = checkInterestEarned(_asset);
        if (assetInterest != 0) {
            uint256 interestCollected = aavePool.withdraw(_asset, assetInterest, address(this));
            uint256 harvestAmt = _splitAndSendReward(_asset, yieldReceiver, msg.sender, interestCollected);
            emit InterestCollected(_asset, yieldReceiver, harvestAmt);
        }
    }

    /// @inheritdoc InitializableAbstractStrategy
    function collectReward() external pure override {
        // No reward token for Aave
        revert NoRewardIncentive();
    }

    /// @inheritdoc InitializableAbstractStrategy
    function checkInterestEarned(address _asset) public view override returns (uint256) {
        uint256 balance = checkLPTokenBalance(_asset);
        uint256 allocatedAmt = allocatedAmount[_asset];
        if (balance > allocatedAmt) {
            unchecked {
                return balance - allocatedAmt;
            }
        } else {
            return 0;
        }
    }

    /// @inheritdoc InitializableAbstractStrategy
    function checkBalance(address _asset) public view override returns (uint256 balance) {
        // Balance is always with token lpToken decimals
        balance = allocatedAmount[_asset];
    }

    /// @inheritdoc InitializableAbstractStrategy
    function checkAvailableBalance(address _asset) public view override returns (uint256) {
        uint256 availableLiquidity = IERC20(_asset).balanceOf(_getPTokenFor(_asset));
        uint256 allocatedValue = allocatedAmount[_asset];
        if (availableLiquidity <= allocatedValue) {
            return availableLiquidity;
        }
        return allocatedValue;
    }

    /// @inheritdoc InitializableAbstractStrategy
    function checkLPTokenBalance(address _asset) public view override returns (uint256 balance) {
        address lpToken = _getPTokenFor(_asset);
        balance = IERC20(lpToken).balanceOf(address(this));
    }

    /// @inheritdoc InitializableAbstractStrategy
    function supportsCollateral(address _asset) public view override returns (bool) {
        return assetToPToken[_asset] != address(0);
    }

    /// @inheritdoc InitializableAbstractStrategy
    function checkRewardEarned() public pure override returns (uint256) {
        return 0;
    }

    /// @notice Withdraw asset from Aave lending Pool
    /// @param _recipient Address to receive withdrawn asset
    /// @param _asset Address of asset to withdraw
    /// @param _amount Amount of asset to withdraw
    function _withdraw(address _recipient, address _asset, uint256 _amount) internal returns (uint256) {
        Helpers._isNonZeroAddr(_recipient);
        Helpers._isNonZeroAmt(_amount, "Must withdraw something");
        allocatedAmount[_asset] -= _amount;
        uint256 actual = aavePool.withdraw(_asset, _amount, _recipient);
        if (actual < _amount) revert Helpers.MinSlippageError(actual, _amount);
        emit Withdrawal(_asset, actual);
        return actual;
    }

    /// @dev Internal method to respond to the addition of new asset / lpTokens
    ///      We need to give the AAVE lending pool approval to transfer the
    ///      asset.
    /// @param _asset Address of the asset to approve
    /// @param _lpToken Address of the lpToken
    function _abstractSetPToken(address _asset, address _lpToken) internal view override {
        if (IAToken(_lpToken).UNDERLYING_ASSET_ADDRESS() != _asset) {
            revert InvalidAssetLpPair(_asset, _lpToken);
        }
    }

    /// @notice Get the lpToken wrapped in the IERC20 interface for this asset.
    ///      Fails if the lpToken doesn't exist in our mappings.
    /// @param _asset Address of the asset
    /// @return Corresponding lpToken to this asset
    function _getPTokenFor(address _asset) internal view returns (address) {
        address lpToken = assetToPToken[_asset];
        if (lpToken == address(0)) revert CollateralNotSupported(_asset);
        return lpToken;
    }
}
