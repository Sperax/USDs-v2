// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {InitializableAbstractStrategy} from "../InitializableAbstractStrategy.sol";
import {IfToken} from "./interfaces/IfToken.sol";

/// @title Fluid strategy for USDs protocol
/// @author Sperax Foundation
/// @notice A yield earning strategy for USDs protocol
/// @notice Important contract addresses:
///         https://github.com/Instadapp/fluid-contracts-public/blob/main/deployments/deployments.md#lendingfactory
contract FluidStrategy is InitializableAbstractStrategy {
    function initialize(
        address[] memory assets,
        address[] memory pTokens,
        address _vault,
        uint16 _depositSlippage, // 200 = 2%
        uint16 _withdrawSlippage // 200 = 2%
    ) external initializer {
        // Not using a loop here because of increased gas usage in array.length calculation, loop variable declaration, condition and increment.
        _setPTokenAddress(assets[0], pTokens[0]); // USDT
        _setPTokenAddress(assets[1], pTokens[1]); // USDC

        InitializableAbstractStrategy._initialize(_vault, _depositSlippage, _withdrawSlippage);
    }

    /// @inheritdoc InitializableAbstractStrategy
    function deposit(address _asset, uint256 _amount) external override {}

    /// @inheritdoc InitializableAbstractStrategy
    function withdraw(address _recipient, address _asset, uint256 _amount)
        external
        override
        returns (uint256 amountReceived)
    {}

    /// @inheritdoc InitializableAbstractStrategy
    function withdrawToVault(address _asset, uint256 _amount) external override returns (uint256 amount) {}

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

    /// @inheritdoc InitializableAbstractStrategy
    function _abstractSetPToken(address _asset, address _pToken) internal view override {
        if (IfToken(_pToken).asset() == _asset) {
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
