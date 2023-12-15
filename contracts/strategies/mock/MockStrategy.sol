// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {InitializableAbstractStrategy, Helpers, IStrategyVault} from "../InitializableAbstractStrategy.sol";

contract MockStrategy is InitializableAbstractStrategy {
    using SafeERC20 for IERC20;

    address public asset;
    uint256 public interest;
    address public rewardToken;
    uint256 public reward;

    function initialize(address _vault, address _asset, uint256 _interest, address _rewardToken, uint256 _reward)
        external
        initializer
    {
        asset = _asset;
        interest = _interest;
        rewardToken = _rewardToken;
        reward = _reward;

        InitializableAbstractStrategy._initialize(_vault, 0, 0);
    }

    /// @notice Function to change interest and reward values for testing purposes.
    function changeInterestAndReward(uint256 _interest, uint256 _reward) external onlyOwner {
        interest = _interest;
        reward = _reward;
    }

    /// @inheritdoc InitializableAbstractStrategy
    function deposit(address _asset, uint256 _amount) external override onlyVault nonReentrant {
        if (!supportsCollateral(_asset)) revert CollateralNotSupported(_asset);

        IERC20(_asset).safeTransferFrom(msg.sender, address(this), _amount);

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
        return _withdraw(_recipient, _asset, _amount);
    }

    /// @inheritdoc InitializableAbstractStrategy
    function withdrawToVault(address _asset, uint256 _amount)
        external
        override
        onlyOwner
        nonReentrant
        returns (uint256)
    {
        return _withdraw(vault, _asset, _amount);
    }

    /// @inheritdoc InitializableAbstractStrategy
    function collectInterest(address _asset) external override nonReentrant {
        if (!supportsCollateral(_asset)) revert CollateralNotSupported(_asset);
        address yieldReceiver = IStrategyVault(vault).yieldReceiver();

        uint256 harvestAmt = _splitAndSendReward(_asset, yieldReceiver, msg.sender, interest);
        emit InterestCollected(_asset, yieldReceiver, harvestAmt);
    }

    /// @inheritdoc InitializableAbstractStrategy
    function collectReward() external override nonReentrant {
        address yieldReceiver = IStrategyVault(vault).yieldReceiver();

        uint256 harvestAmt = _splitAndSendReward(rewardToken, yieldReceiver, msg.sender, reward);
        emit RewardTokenCollected(rewardToken, yieldReceiver, harvestAmt);
    }

    /// @inheritdoc InitializableAbstractStrategy
    function supportsCollateral(address _asset) public view override returns (bool) {
        return _asset == asset;
    }

    /// @inheritdoc InitializableAbstractStrategy
    function checkRewardEarned() public view override returns (uint256) {
        return reward;
    }

    /// @inheritdoc InitializableAbstractStrategy
    function checkInterestEarned(address _asset) public view override returns (uint256) {
        if (!supportsCollateral(_asset)) revert CollateralNotSupported(_asset);

        return interest;
    }

    /// @inheritdoc InitializableAbstractStrategy
    function checkBalance(address _asset) public view override returns (uint256) {
        if (!supportsCollateral(_asset)) revert CollateralNotSupported(_asset);
        return IERC20(_asset).balanceOf(address(this));
    }

    /// @inheritdoc InitializableAbstractStrategy
    function checkAvailableBalance(address _asset) public view override returns (uint256) {
        return checkBalance(_asset);
    }

    /// @inheritdoc InitializableAbstractStrategy
    function checkLPTokenBalance(address _asset) public view override returns (uint256) {
        return checkBalance(_asset);
    }

    /// @inheritdoc InitializableAbstractStrategy
    /* solhint-disable-next-line no-empty-blocks */
    function _abstractSetPToken(address _asset, address _pToken) internal override {}

    /// @dev Internal function to withdraw a specified amount of an asset.
    /// @param _recipient The address to which the assets will be sent.
    /// @param _asset The address of the asset to be withdrawn.
    /// @param _amount The amount of the asset to be withdrawn.
    function _withdraw(address _recipient, address _asset, uint256 _amount) internal returns (uint256) {
        Helpers._isNonZeroAmt(_amount, "Must withdraw something");
        if (!supportsCollateral(_asset)) revert CollateralNotSupported(_asset);

        IERC20(_asset).safeTransfer(_recipient, _amount);

        emit Withdrawal(_asset, _amount);

        return _amount;
    }
}
