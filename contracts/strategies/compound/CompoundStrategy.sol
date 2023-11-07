// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {InitializableAbstractStrategy, Helpers, IStrategyVault} from "../InitializableAbstractStrategy.sol";
import {IComet, IReward} from "./interfaces/ICompoundHelper.sol";

/// @title Compound strategy for USDs protocol
/// @notice A yield earning strategy for USDs protocol
/// @notice Important contract addresses:
///         Addresses https://docs.compound.finance/#networks
contract CompoundStrategy is InitializableAbstractStrategy {
    using SafeERC20 for IERC20;

    uint256 internal constant FACTOR_SCALE = 1e18;
    IReward public rewardPool;
    mapping(address => uint256) public allocatedAmount; // tracks the allocated amount for an asset.

    /// Initializer for setting up strategy internal state. This overrides the
    /// InitializableAbstractStrategy initializer as Compound needs several extra
    /// addresses for the rewards program.
    /// @param _rewardPool Address of the Compound's reward pool
    /// @param _vault Address of the vault
    function initialize(address _vault, address _rewardPool) external initializer {
        Helpers._isNonZeroAddr(_rewardPool);
        Helpers._isNonZeroAddr(_vault);
        rewardPool = IReward(_rewardPool);

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
    function deposit(address _asset, uint256 _amount) external override nonReentrant {
        Helpers._isNonZeroAmt(_amount);
        address lpToken = _getPTokenFor(_asset);

        // Following line also doubles as a check that we are depositing
        // an asset that we support.
        allocatedAmount[_asset] += _amount;

        IERC20(_asset).safeTransferFrom(msg.sender, address(this), _amount);
        IERC20(_asset).safeApprove(lpToken, _amount);

        // Supply Compound Strategy.
        IComet(lpToken).supply(_asset, _amount);

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
        _withdraw(_recipient, _asset, _amount);
        return _amount;
    }

    /// @inheritdoc InitializableAbstractStrategy
    function withdrawToVault(address _asset, uint256 _amount)
        external
        override
        onlyOwner
        nonReentrant
        returns (uint256)
    {
        _withdraw(vault, _asset, _amount);
        return _amount;
    }

    /// @inheritdoc InitializableAbstractStrategy
    function collectInterest(address _asset) external override nonReentrant {
        address yieldReceiver = IStrategyVault(vault).yieldReceiver();
        uint256 assetInterest = checkInterestEarned(_asset);
        if (assetInterest != 0) {
            IComet(assetToPToken[_asset]).withdraw(_asset, assetInterest);
            uint256 harvestAmt = _splitAndSendReward(_asset, yieldReceiver, msg.sender, assetInterest);
            emit InterestCollected(_asset, yieldReceiver, harvestAmt);
        }
    }

    /// @inheritdoc InitializableAbstractStrategy
    function collectReward() external override {
        address yieldReceiver = IStrategyVault(vault).yieldReceiver();
        uint256 numAssets = assetsMapped.length;
        for (uint256 i; i < numAssets;) {
            address lpToken = assetToPToken[assetsMapped[i]];
            IReward.RewardOwed memory rewardData = rewardPool.getRewardOwed(lpToken, address(this));
            rewardPool.claim(lpToken, address(this), false);
            uint256 harvestAmt = _splitAndSendReward(rewardData.token, yieldReceiver, msg.sender, rewardData.owed);
            emit RewardTokenCollected(rewardData.token, yieldReceiver, harvestAmt);
            unchecked {
                ++i;
            }
        }
    }

    /// @inheritdoc InitializableAbstractStrategy
    function checkRewardEarned() external view override returns (uint256 total) {
        uint256 numAssets = assetsMapped.length;
        for (uint256 i; i < numAssets;) {
            address lpToken = assetToPToken[assetsMapped[i]];
            uint256 accrued = uint256(IComet(lpToken).baseTrackingAccrued(address(this)));
            IReward.RewardConfig memory config = rewardPool.rewardConfig(lpToken);
            if (config.shouldUpscale) {
                accrued *= config.rescaleFactor;
            } else {
                accrued /= config.rescaleFactor;
            }
            accrued = ((accrued * config.multiplier) / FACTOR_SCALE);

            // assuming homogeneous reward tokens
            total += accrued - rewardPool.rewardsClaimed(lpToken, address(this));
            unchecked {
                ++i;
            }
        }
    }

    /// @inheritdoc InitializableAbstractStrategy
    function checkBalance(address _asset) external view override returns (uint256 balance) {
        // Balance is always with token lpToken decimals
        balance = allocatedAmount[_asset];
    }

    /// @inheritdoc InitializableAbstractStrategy
    function checkAvailableBalance(address _asset) external view override returns (uint256) {
        uint256 availableLiquidity = IERC20(_asset).balanceOf(_getPTokenFor(_asset));
        uint256 allocatedValue = allocatedAmount[_asset];
        if (availableLiquidity <= allocatedValue) {
            return availableLiquidity;
        }
        return allocatedValue;
    }

    /// @inheritdoc InitializableAbstractStrategy
    function supportsCollateral(address _asset) external view override returns (bool) {
        return assetToPToken[_asset] != address(0);
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
    function checkLPTokenBalance(address _asset) public view override returns (uint256 balance) {
        address lpToken = _getPTokenFor(_asset);
        balance = IComet(lpToken).balanceOf(address(this));
    }

    /// @notice Withdraw asset from Compound v3
    /// @param _recipient Address to receive withdrawn asset
    /// @param _asset Address of asset to withdraw
    /// @param _amount Amount of asset to withdraw
    function _withdraw(address _recipient, address _asset, uint256 _amount) internal {
        Helpers._isNonZeroAddr(_recipient);
        Helpers._isNonZeroAmt(_amount, "Must withdraw something");
        address lpToken = _getPTokenFor(_asset);
        allocatedAmount[_asset] -= _amount;
        IComet(lpToken).withdrawTo(_recipient, _asset, _amount);
        emit Withdrawal(_asset, _amount);
    }

    /// @dev Internal method to respond to the addition of new asset / cTokens
    ///      cToken and give it permission to spend the asset
    /// @param _asset Address of the asset to approve
    /// @param _lpToken Address of the lpToken
    function _abstractSetPToken(address _asset, address _lpToken) internal view override {
        if (IComet(_lpToken).baseToken() != _asset) {
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
