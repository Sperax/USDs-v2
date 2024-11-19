// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {InitializableAbstractStrategy} from "../InitializableAbstractStrategy.sol";
import {IfToken} from "./interfaces/IfToken.sol";

/// @title Fluid strategy for USDs protocol
/// @author Sperax Foundation
/// @notice A yield earning strategy for USDs protocol
/// @notice Important contract addresses:
///         https://github.com/Instadapp/fluid-contracts-public/blob/main/deployments/deployments.md#lendingfactory
contract FluidStrategy is InitializableAbstractStrategy {
    using SafeERC20 for IERC20;

    mapping(address => uint256) public allocatedAmount; // tracks the allocated amount for an asset.

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

    /// @inheritdoc InitializableAbstractStrategy
    function deposit(address _asset, uint256 _amount) external override {
        address lpToken = _getPTokenFor(_asset);

        allocatedAmount[_asset] += _amount;

        IERC20(_asset).safeTransferFrom(msg.sender, address(this), _amount);
        IERC20(_asset).forceApprove(lpToken, _amount);

        uint256 minAmountOut = IfToken(lpToken).convertToShares(_amount);
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
    function collectInterest(address _asset) external override {}

    /// @notice Collect accumulated reward token and send to Vault.
    function collectReward() external override {}

    /// @inheritdoc InitializableAbstractStrategy
    function checkBalance(address _asset) external view override returns (uint256) {}

    /// @inheritdoc InitializableAbstractStrategy
    function checkAvailableBalance(address _asset) external view override returns (uint256) {}

    /// @inheritdoc InitializableAbstractStrategy
    function checkInterestEarned(address _asset) external view override returns (uint256) {}

    /// @inheritdoc InitializableAbstractStrategy
    function checkRewardEarned() external view override returns (RewardData[] memory) {}

    /// @inheritdoc InitializableAbstractStrategy
    function checkLPTokenBalance(address _asset) external view override returns (uint256) {}

    /// @inheritdoc InitializableAbstractStrategy
    function supportsCollateral(address _asset) external view override returns (bool) {}

    function _withdraw(address _recipient, address _asset, uint256 _amount) internal returns (uint256) {
        address lpToken = _getPTokenFor(_asset);

        allocatedAmount[_asset] -= _amount;

        uint256 maxSharesBurn = IfToken(lpToken).convertToShares(_amount);
        IfToken(lpToken).withdraw(_amount, _recipient, address(this), maxSharesBurn);

        emit Deposit(_asset, _amount);

        return _amount;
    }

    /// @inheritdoc InitializableAbstractStrategy
    function _abstractSetPToken(address _asset, address _pToken) internal view override {
        if (IfToken(_pToken).asset() != _asset) {
            revert InvalidAssetLpPair(_asset, _pToken);
        }
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
