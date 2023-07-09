// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ILPStaking} from "./interfaces/ILPStaking.sol";
import {IStargateRouter} from "./interfaces/IStargateRouter.sol";
import {IStargatePool} from "./interfaces/IStargatePool.sol";
import {InitializableAbstractStrategy} from "../InitializableAbstractStrategy.sol";
import {IVault} from "../interfaces/IVault.sol";

/// @title Stargate strategy for USDs protocol
/// @notice A yield earning strategy for USDs protocol
/// @notice Important contract addresses:
///         Addresses https://stargateprotocol.gitbook.io/stargate/developers/contract-addresses/mainnet#arbitrum
contract StargateStrategy is InitializableAbstractStrategy {
    using SafeERC20 for IERC20;
    struct AssetInfo {
        uint256 allocatedAmt; // tracks the allocated amount for an asset.
        uint256 intLiqThreshold; // tracks the interest liq threshold for an asset.
        uint256 rewardPID; // maps asset to farm reward pool id
        uint16 pid; // maps asset to pool id
    }

    bool public skipRwdValidation; // skip reward validation, for emergency use.
    address public router;
    address public farm;
    mapping(address => AssetInfo) public assetInfo;

    event SkipRwdValidationStatus(bool status);
    event IntLiqThresholdChanged(
        address indexed asset,
        uint256 intLiqThreshold
    );

    function initialize(
        address _router,
        address _vaultAddress,
        address _stg,
        address _farm,
        uint16 _depositSlippage, // 200 = 2%
        uint16 _withdrawSlippage // 200 = 2%
    ) external initializer {
        _isNonZeroAddr(_router);
        _isNonZeroAddr(_stg);
        _isNonZeroAddr(_farm);
        router = _router;
        farm = _farm;

        // register reward token
        rewardTokenAddress.push(_stg);

        InitializableAbstractStrategy._initialize(
            _vaultAddress,
            _depositSlippage,
            _withdrawSlippage
        );
    }

    /// @notice Provide support for asset by passing its pToken address.
    ///      This method can only be called by the system owner
    /// @param _asset    Address for the asset
    /// @param _pToken   Address for the corresponding platform token
    /// @param _pid   Pool Id for the asset
    /// @param _rewardPid   Farm Pool Id for the asset
    /// @param _intLiqThreshold   Liquidity threshold for interest
    function setPTokenAddress(
        address _asset,
        address _pToken,
        uint16 _pid,
        uint256 _rewardPid,
        uint256 _intLiqThreshold
    ) external onlyOwner {
        require(
            IStargatePool(_pToken).token() == _asset,
            "Incorrect asset & pToken pair"
        );
        require(IStargatePool(_pToken).poolId() == _pid, "Incorrect pool id");
        (IERC20 lpToken, , , ) = ILPStaking(farm).poolInfo(_rewardPid);
        require(address(lpToken) == _pToken, "Incorrect reward pid");
        _setPTokenAddress(_asset, _pToken);
        assetInfo[_asset] = AssetInfo({
            allocatedAmt: 0,
            pid: _pid,
            rewardPID: _rewardPid,
            intLiqThreshold: _intLiqThreshold
        });
    }

    /// @dev Remove a supported asset by passing its index.
    ///       This method can only be called by the system owner
    ///  @param _assetIndex Index of the asset to be removed
    function removePToken(uint256 _assetIndex) external onlyOwner {
        address asset = _removePTokenAddress(_assetIndex);
        require(assetInfo[asset].allocatedAmt == 0, "Collateral allocated");
        delete assetInfo[asset];
    }

    /// @notice Update the interest liquidity threshold for an asset.
    /// @param _asset Address of the asset
    /// @param _intLiqThreshold Liquidity threshold for interest
    function updateIntLiqThreshold(
        address _asset,
        uint256 _intLiqThreshold
    ) external onlyOwner {
        require(
            assetInfo[_asset].intLiqThreshold != _intLiqThreshold,
            "Invalid threshold value"
        );
        require(supportsCollateral(_asset), "Asset not supported");
        assetInfo[_asset].intLiqThreshold = _intLiqThreshold;

        emit IntLiqThresholdChanged(_asset, _intLiqThreshold);
    }

    /// @notice Toggle the skip reward validation flag.
    /// @dev When switched on, the reward validation will be skipped.
    ///    Can result in a forfeiting of rewards.
    function toggleRwdValidation() external onlyOwner {
        skipRwdValidation = !skipRwdValidation;
        emit SkipRwdValidationStatus(skipRwdValidation);
    }

    /// @inheritdoc InitializableAbstractStrategy
    function deposit(
        address _asset,
        uint256 _amount
    ) external override onlyVault nonReentrant {
        _isValidAmount(_amount);
        require(_validateRwdClaim(_asset), "Insufficient rwd fund in farm");
        address lpToken = assetToPToken[_asset];
        IERC20(_asset).safeTransferFrom(msg.sender, address(this), _amount);
        IERC20(_asset).safeApprove(router, _amount);

        // Add liquidity in the stargate pool.
        IStargateRouter(router).addLiquidity(
            assetInfo[_asset].pid,
            _amount,
            address(this)
        );
        // Deposit the generated lpToken in the farm.
        // @dev We are assuming that the 100% of lpToken is deposited in the farm.
        uint256 lpTokenBal = IERC20(lpToken).balanceOf(address(this));
        uint256 depositAmt = _convertToCollateral(_asset, lpTokenBal);
        uint256 minDepositAmt = (_amount *
            (PERCENTAGE_PREC - depositSlippage)) / PERCENTAGE_PREC;
        require(depositAmt >= minDepositAmt, "Insufficient deposit amount");

        // Update the allocated amount in the strategy
        assetInfo[_asset].allocatedAmt += depositAmt;

        IERC20(lpToken).safeApprove(farm, lpTokenBal);
        ILPStaking(farm).deposit(assetInfo[_asset].rewardPID, lpTokenBal);
        emit Deposit(_asset, lpToken, depositAmt);
    }

    /// @inheritdoc InitializableAbstractStrategy
    function withdraw(
        address _recipient,
        address _asset,
        uint256 _amount
    ) external override onlyVault nonReentrant returns (uint256) {
        return _withdraw(false, _recipient, _asset, _amount);
    }

    /// @inheritdoc InitializableAbstractStrategy
    function withdrawToVault(
        address _asset,
        uint256 _amount
    ) external override onlyOwner nonReentrant returns (uint256) {
        return _withdraw(false, vaultAddress, _asset, _amount);
    }

    /// @inheritdoc InitializableAbstractStrategy
    function collectInterest(address _asset) external override nonReentrant {
        address yieldReceiver = IVault(vaultAddress).yieldReceiver();
        address harvestor = msg.sender;
        uint256 earnedInterest = checkInterestEarned(_asset);
        if (earnedInterest > assetInfo[_asset].intLiqThreshold) {
            uint256 interestCollected = _withdraw(
                true,
                address(this),
                _asset,
                earnedInterest
            );
            uint256 harvestAmt = _splitAndSendReward(
                _asset,
                yieldReceiver,
                harvestor,
                interestCollected
            );
            emit InterestCollected(_asset, yieldReceiver, harvestAmt);
        }
    }

    /// @inheritdoc InitializableAbstractStrategy
    function collectReward() external override nonReentrant {
        address yieldReceiver = IVault(vaultAddress).yieldReceiver();
        address harvestor = msg.sender;
        address rewardToken = rewardTokenAddress[0];
        uint256 numAssets = assetsMapped.length;
        for (uint256 i = 0; i < numAssets; ) {
            address asset = assetsMapped[i];
            uint256 rewardAmt = checkPendingRewards(asset);
            if (
                rewardAmt > 0 &&
                (skipRwdValidation ||
                    rewardAmt <= IERC20(rewardToken).balanceOf(farm))
            ) {
                ILPStaking(farm).deposit(assetInfo[asset].rewardPID, 0);
            }
            unchecked {
                ++i;
            }
        }
        uint256 rewardEarned = IERC20(rewardToken).balanceOf(address(this));
        uint256 harvestAmt = _splitAndSendReward(
            rewardToken,
            yieldReceiver,
            harvestor,
            rewardEarned
        );
        emit RewardTokenCollected(rewardToken, yieldReceiver, harvestAmt);
    }

    /// @inheritdoc InitializableAbstractStrategy
    function supportsCollateral(
        address _asset
    ) public view override returns (bool) {
        return assetToPToken[_asset] != address(0);
    }

    /// @notice Get the amount STG pending to be collected.
    /// @param _asset Address for the asset
    function checkPendingRewards(address _asset) public view returns (uint256) {
        require(supportsCollateral(_asset), "Collateral not supported");
        return
            ILPStaking(farm).pendingStargate(
                assetInfo[_asset].rewardPID,
                address(this)
            );
    }

    /// @inheritdoc InitializableAbstractStrategy
    function checkRewardEarned() public view override returns (uint256) {
        uint256 pendingRewards = 0;
        uint256 numAssets = assetsMapped.length;
        for (uint256 i = 0; i < numAssets; ) {
            address asset = assetsMapped[i];
            pendingRewards += ILPStaking(farm).pendingStargate(
                assetInfo[asset].rewardPID,
                address(this)
            );
            unchecked {
                ++i;
            }
        }
        uint256 claimedRewards = IERC20(rewardTokenAddress[0]).balanceOf(
            address(this)
        );
        return claimedRewards + pendingRewards;
    }

    /// @inheritdoc InitializableAbstractStrategy
    function checkInterestEarned(
        address _asset
    ) public view override returns (uint256) {
        uint256 lpTokenBal = checkLPTokenBalance(_asset);

        uint256 collateralBal = _convertToCollateral(_asset, lpTokenBal);
        if (collateralBal <= assetInfo[_asset].allocatedAmt) {
            return 0;
        }
        return collateralBal - assetInfo[_asset].allocatedAmt;
    }

    /// @inheritdoc InitializableAbstractStrategy
    function checkBalance(
        address _asset
    ) public view override returns (uint256) {
        uint256 lpTokenBal = checkLPTokenBalance(_asset);
        uint256 calcCollateralBal = _convertToCollateral(_asset, lpTokenBal);
        if (assetInfo[_asset].allocatedAmt <= calcCollateralBal) {
            return assetInfo[_asset].allocatedAmt;
        }
        return calcCollateralBal;
    }

    /// @inheritdoc InitializableAbstractStrategy
    function checkAvailableBalance(
        address _asset
    ) public view override returns (uint256) {
        if (!_validateRwdClaim(_asset)) {
            // Insufficient rwd fund in farm
            // @dev to bypass this check toggle skipRwdValidation to true
            return 0;
        }

        IStargatePool pool = IStargatePool(assetToPToken[_asset]);
        uint256 availableFunds = _convertToCollateral(
            _asset,
            pool.deltaCredit()
        );
        if (availableFunds <= assetInfo[_asset].allocatedAmt) {
            return availableFunds;
        }
        return assetInfo[_asset].allocatedAmt;
    }

    /// @inheritdoc InitializableAbstractStrategy
    function checkLPTokenBalance(
        address _asset
    ) public view override returns (uint256) {
        require(supportsCollateral(_asset), "Collateral not supported");
        (uint256 lpTokenStaked, ) = ILPStaking(farm).userInfo(
            assetInfo[_asset].rewardPID,
            address(this)
        );
        return lpTokenStaked;
    }

    /// @inheritdoc InitializableAbstractStrategy
    function _abstractSetPToken(
        address _asset,
        address _pToken
    ) internal override {}

    /// @notice Convert amount of lpToken to collateral.
    /// @param _asset Address for the asset
    /// @param _lpTokenAmount Amount of lpToken
    function _convertToCollateral(
        address _asset,
        uint256 _lpTokenAmount
    ) internal view returns (uint256) {
        IStargatePool pool = IStargatePool(assetToPToken[_asset]);
        return
            ((_lpTokenAmount * pool.totalLiquidity()) / pool.totalSupply()) *
            pool.convertRate();
    }

    /// @notice Convert amount of collateral to lpToken.
    /// @param _asset Address for the asset
    /// @param _collateralAmount Amount of collateral
    function _convertToPToken(
        address _asset,
        uint256 _collateralAmount
    ) internal view returns (uint256) {
        IStargatePool pool = IStargatePool(assetToPToken[_asset]);
        return
            (_collateralAmount * pool.totalSupply()) /
            (pool.totalLiquidity() * pool.convertRate());
    }

    /// @notice Helper function for withdrawal.
    /// @dev Validate if the farm has enough STG to withdraw as rewards.
    function _withdraw(
        bool _withdrawInterest,
        address _recipient,
        address _asset,
        uint256 _amount
    ) private returns (uint256) {
        _isNonZeroAddr(_recipient);
        require(_amount > 0, "Must withdraw something");
        require(_validateRwdClaim(_asset), "Insufficient rwd fund in farm");
        address lpToken = assetToPToken[_asset];
        uint256 lpTokenAmt = _convertToPToken(_asset, _amount);
        ILPStaking(farm).withdraw(assetInfo[_asset].rewardPID, lpTokenAmt);
        uint256 minRecvAmt = (_amount * (PERCENTAGE_PREC - withdrawSlippage)) /
            PERCENTAGE_PREC;
        uint256 amtRecv = IStargateRouter(router).instantRedeemLocal(
            assetInfo[_asset].pid,
            lpTokenAmt,
            _recipient
        ) * IStargatePool(assetToPToken[_asset]).convertRate();
        require(amtRecv >= minRecvAmt, "Did not withdraw enough");

        if (!_withdrawInterest) {
            assetInfo[_asset].allocatedAmt -= amtRecv;
            emit Withdrawal(_asset, lpToken, amtRecv);
        }

        return amtRecv;
    }

    /// @notice Validate if the farm has sufficient funds to claim rewards.
    /// @param _asset Address for the asset
    /// @dev skipRwdValidation is a flag to skip the validation.
    function _validateRwdClaim(address _asset) private view returns (bool) {
        if (skipRwdValidation) {
            return true;
        }
        return
            checkPendingRewards(_asset) <=
            IERC20(rewardTokenAddress[0]).balanceOf(farm);
    }
}
