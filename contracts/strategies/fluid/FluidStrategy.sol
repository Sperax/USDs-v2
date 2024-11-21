// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {InitializableAbstractStrategy, Helpers, IStrategyVault} from "../InitializableAbstractStrategy.sol";
import {IfToken} from "./interfaces/IfToken.sol";

/// @title Fluid strategy for USDs protocol
/// @author Sperax Foundation
/// @notice A yield earning strategy for USDs protocol
/// @notice Important contract addresses:
///         https://github.com/Instadapp/fluid-contracts-public/blob/main/deployments/deployments.md#lendingfactory
contract FluidStrategy is InitializableAbstractStrategy {
    using SafeERC20 for IERC20;

    mapping(address => uint256) public allocatedAmount; // tracks the allocated amount for an asset.

    error NoRewardIncentive();

    /// @notice Initializer function of the strategy to initialize the state variables of InitializableAbstractStrategy
    function initialize(
        address _vault,
        uint16 _depositSlippage, // 200 = 2%
        uint16 _withdrawSlippage // 200 = 2%
    ) external initializer {
        InitializableAbstractStrategy._initialize(_vault, _depositSlippage, _withdrawSlippage);
    }

    /// @notice Provide support for asset by passing its lpToken address.
    ///      This method can only be called by the contract owner
    /// @param _asset    Address of the asset
    /// @param _lpToken   Address of the corresponding platform token
    function setPTokenAddress(address _asset, address _lpToken) external onlyOwner {
        _setPTokenAddress(_asset, _lpToken);
    }

    /// @dev Remove a supported asset by passing its index.
    ///       This method can only be called by the system owner
    ///  @param _assetIndex Index of the asset to be removed
    function removePToken(uint256 _assetIndex) external onlyOwner {
        address asset = _removePTokenAddress(_assetIndex);
        if (allocatedAmount[asset] != 0) {
            revert CollateralAllocated(asset);
        }
    }

    /// @inheritdoc InitializableAbstractStrategy
    function deposit(address _asset, uint256 _amount) external override nonReentrant {
        Helpers._isNonZeroAmt(_amount, "Must deposit something");
        address lpToken = _getPTokenFor(_asset);

        allocatedAmount[_asset] += _amount;

        IERC20(_asset).safeTransferFrom(msg.sender, address(this), _amount);
        IERC20(_asset).forceApprove(lpToken, _amount);

        uint256 minAmountOut = IfToken(lpToken).previewDeposit(_amount);
        IfToken(lpToken).deposit(_amount, address(this), minAmountOut);

        emit Deposit(_asset, _amount);
    }

    /// @inheritdoc InitializableAbstractStrategy
    function withdraw(address _recipient, address _asset, uint256 _amount)
        external
        override
        onlyVault
        nonReentrant
        returns (uint256 amountReceived)
    {
        amountReceived = _withdraw(_recipient, _asset, _amount);
    }

    /// @inheritdoc InitializableAbstractStrategy
    function withdrawToVault(address _asset, uint256 _amount)
        external
        override
        onlyOwner
        nonReentrant
        returns (uint256 amountReceived)
    {
        amountReceived = _withdraw(vault, _asset, _amount);
    }

    /// @inheritdoc InitializableAbstractStrategy
    function collectInterest(address _asset) external override nonReentrant {
        uint256 assetInterest = checkInterestEarned(_asset);
        if (assetInterest != 0) {
            address yieldReceiver = IStrategyVault(vault).yieldReceiver();
            IfToken(_getPTokenFor(_asset)).withdraw(assetInterest, address(this), address(this));
            uint256 harvestAmt = _splitAndSendReward(_asset, yieldReceiver, msg.sender, assetInterest);
            emit InterestCollected(_asset, yieldReceiver, harvestAmt);
        }
    }

    /// @inheritdoc InitializableAbstractStrategy
    function supportsCollateral(address _asset) external view override returns (bool) {
        return assetToPToken[_asset] != address(0);
    }

    /// @inheritdoc InitializableAbstractStrategy
    function checkBalance(address _asset) external view override returns (uint256 balance) {
        balance = allocatedAmount[_asset];
    }

    /// @inheritdoc InitializableAbstractStrategy
    function checkAvailableBalance(address _asset) external view override returns (uint256) {
        uint256 availableLiquidity = _getAvailableLiquidity(_asset);
        uint256 allocatedValue = allocatedAmount[_asset];
        if (availableLiquidity <= allocatedValue) {
            return availableLiquidity;
        }
        return allocatedValue;
    }

    /// @notice Collect accumulated reward token and send to Vault.
    /// @dev There are no separate rewards by Fluid.
    function collectReward() external pure override {
        revert NoRewardIncentive();
    }

    /// @inheritdoc InitializableAbstractStrategy
    function checkRewardEarned() external pure override returns (RewardData[] memory) {
        return (new RewardData[](0));
    }

    /// @inheritdoc InitializableAbstractStrategy
    function checkInterestEarned(address _asset) public view override returns (uint256 interest) {
        uint256 availableLiquidity = _getAvailableLiquidity(_asset);
        uint256 allocatedValue = allocatedAmount[_asset];
        if (availableLiquidity > allocatedValue) {
            interest = availableLiquidity - allocatedValue;
        }
    }

    /// @inheritdoc InitializableAbstractStrategy
    function checkLPTokenBalance(address _asset) public view override returns (uint256 balance) {
        balance = IERC20(_getPTokenFor(_asset)).balanceOf(address(this));
    }

    /// @notice Internal withdraw function used for withdrawing from the strategy.
    /// @param _recipient Receiver of the funds.
    /// @param _asset Asset to be withdrawn.
    /// @param _amount Amount to be withdrawn.
    /// @return _amount Amount withdrawn/
    function _withdraw(address _recipient, address _asset, uint256 _amount) internal returns (uint256) {
        Helpers._isNonZeroAddr(_recipient);
        Helpers._isNonZeroAmt(_amount, "Must withdraw something");

        address lpToken = _getPTokenFor(_asset);

        allocatedAmount[_asset] -= _amount;

        uint256 shares = IfToken(lpToken).previewWithdraw(_amount);
        uint256 received = IfToken(lpToken).redeem(shares, _recipient, address(this));
        if (received < _amount) {
            revert Helpers.MinSlippageError(received, _amount);
        }

        emit Withdrawal(_asset, _amount);

        return _amount;
    }

    /// @inheritdoc InitializableAbstractStrategy
    function _abstractSetPToken(address _asset, address _pToken) internal view override {
        if (IfToken(_pToken).asset() != _asset) {
            revert InvalidAssetLpPair(_asset, _pToken);
        }
    }

    /// @notice A function to fetch the available liquidity deployed in the strategy.
    /// @param _asset Asset to be checked for available liquidity.
    /// @return liquidity Available liquidity.
    function _getAvailableLiquidity(address _asset) internal view returns (uint256 liquidity) {
        address lpToken = _getPTokenFor(_asset);
        uint256 lpBalance = checkLPTokenBalance(_asset);
        liquidity = IfToken(lpToken).convertToAssets(lpBalance);
    }

    /// @notice Get the lpToken for the asset.
    ///      Fails if the lpToken doesn't exist in the mapping.
    /// @param _asset Address of the asset
    /// @return lpToken to this asset
    function _getPTokenFor(address _asset) internal view returns (address lpToken) {
        lpToken = assetToPToken[_asset];
        if (lpToken == address(0)) revert CollateralNotSupported(_asset);
        return lpToken;
    }
}
