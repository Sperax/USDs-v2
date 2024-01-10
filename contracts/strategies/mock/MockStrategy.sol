// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {InitializableAbstractStrategy, Helpers, IStrategyVault} from "../InitializableAbstractStrategy.sol";

contract MockStrategy is InitializableAbstractStrategy {
    using SafeERC20 for IERC20;

    struct AssetInfo {
        uint256 lastInterestUpdateTimestamp;
        uint256 interestPerSecond;
        uint256 allocatedAmt;
    }

    mapping(address => bool) public asset;
    address public rewardToken;
    uint256 public rewardPerSecond;
    uint256 public lastRewardTime;
    mapping(address => AssetInfo) public assetInfo;

    error InvalidRequest();

    function initialize(
        address _vault,
        address[] calldata _asset,
        uint256[] calldata _interestPerSecond,
        address _rewardToken,
        uint256 _rewardPerSecond
    ) external initializer {
        rewardToken = _rewardToken;
        rewardPerSecond = _rewardPerSecond;
        lastRewardTime = block.timestamp;
        uint256 length = _asset.length;
        for (uint256 i; i < length;) {
            asset[_asset[i]] = true;
            assetInfo[_asset[i]].interestPerSecond = _interestPerSecond[i];
            _setPTokenAddress(_asset[i], _asset[i]);
            unchecked {
                ++i;
            }
        }

        InitializableAbstractStrategy._initialize(_vault, 0, 0);
    }

    /// @notice Function to change interest and reward values for testing purposes.
    function changeInterestAndReward(uint256[] calldata _interestPerSecond, uint256 _rewardPerSecond)
        external
        onlyOwner
    {
        if (_interestPerSecond.length == assetsMapped.length) revert InvalidRequest();
        for (uint256 i; i < _interestPerSecond.length; ++i) {
            assetInfo[assetsMapped[i]].interestPerSecond = _interestPerSecond[i];
        }
        rewardPerSecond = _rewardPerSecond;
    }

    /// @notice Provide support for asset by passing its lpToken address.
    ///      This method can only be called by the system owner
    /// @param _asset    Address for the asset
    /// @param _lpToken   Address for the corresponding platform token
    function setPTokenAddress(address _asset, address _lpToken) external onlyOwner {
        _setPTokenAddress(_asset, _lpToken);
    }

    /// @inheritdoc InitializableAbstractStrategy
    function deposit(address _asset, uint256 _amount) external override onlyVault nonReentrant {
        if (!supportsCollateral(_asset)) revert CollateralNotSupported(_asset);

        if (assetInfo[_asset].lastInterestUpdateTimestamp == 0) {
            assetInfo[_asset].lastInterestUpdateTimestamp = block.timestamp;
        }

        assetInfo[_asset].allocatedAmt += _amount;
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

        uint256 interestEarned = checkInterestEarned(_asset);
        if (interestEarned != 0) {
            assetInfo[_asset].lastInterestUpdateTimestamp = block.timestamp;
            uint256 harvestAmt = _splitAndSendReward(_asset, yieldReceiver, msg.sender, interestEarned);
            emit InterestCollected(_asset, yieldReceiver, harvestAmt);
        }
    }

    /// @inheritdoc InitializableAbstractStrategy
    function collectReward() external override nonReentrant {
        address yieldReceiver = IStrategyVault(vault).yieldReceiver();

        uint256 timeElapsed = block.timestamp - lastRewardTime;
        uint256 bal = IERC20(rewardToken).balanceOf(address(this));
        uint256 rewardEarned = timeElapsed * rewardPerSecond;
        rewardEarned = rewardEarned > bal ? bal : rewardEarned;
        if (rewardEarned != 0) {
            lastRewardTime = block.timestamp;
            uint256 harvestAmt = _splitAndSendReward(rewardToken, yieldReceiver, msg.sender, rewardEarned);
            emit RewardTokenCollected(rewardToken, yieldReceiver, harvestAmt);
        }
    }

    /// @inheritdoc InitializableAbstractStrategy
    function supportsCollateral(address _asset) public view override returns (bool) {
        return asset[_asset];
    }

    /// @inheritdoc InitializableAbstractStrategy
    function checkRewardEarned() public view override returns (RewardData[] memory) {
        RewardData[] memory rewardData = new RewardData[](1);
        uint256 timeElapsed = block.timestamp - lastRewardTime;
        uint256 bal = IERC20(rewardToken).balanceOf(address(this));
        uint256 rewardEarned = timeElapsed * rewardPerSecond;
        rewardEarned = rewardEarned > bal ? bal : rewardEarned;
        rewardData[0] = RewardData({token: rewardToken, amount: rewardEarned});
        return rewardData;
    }

    /// @inheritdoc InitializableAbstractStrategy
    function checkInterestEarned(address _asset) public view override returns (uint256) {
        if (!supportsCollateral(_asset)) revert CollateralNotSupported(_asset);

        uint256 timeElapsed = block.timestamp - assetInfo[_asset].lastInterestUpdateTimestamp;
        uint256 bal = IERC20(_asset).balanceOf(address(this)) - assetInfo[_asset].allocatedAmt;
        uint256 interestEarned = timeElapsed * assetInfo[_asset].interestPerSecond;
        interestEarned = interestEarned > bal ? bal : interestEarned;
        return interestEarned;
    }

    /// @inheritdoc InitializableAbstractStrategy
    function checkBalance(address _asset) public view override returns (uint256) {
        if (!supportsCollateral(_asset)) revert CollateralNotSupported(_asset);
        return assetInfo[_asset].allocatedAmt;
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
        assetInfo[_asset].allocatedAmt -= _amount;
        emit Withdrawal(_asset, _amount);

        return _amount;
    }
}
