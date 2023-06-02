// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20, ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ISaddlePool} from "./interfaces/ISaddlePool.sol";
import {ISaddleFarm} from "./interfaces/ISaddleFarm.sol";
import {InitializableAbstractStrategy} from "../InitializableAbstractStrategy.sol";

/// @title Curve FRAX-VST Strategy
/// @notice Investment strategy for investing stablecoins via Curve 2Pool
/// @author Sperax Inc
contract UsdcFraxStrategy is InitializableAbstractStrategy {
    using SafeERC20 for IERC20;

    uint256 public constant PRICE_PREC = 1e18;
    uint256 public constant DEADLINE = 1000; // 1000sec

    address public farm;
    address public sdl;
    address public pool;
    address public lpToken;
    uint256 public pid;
    uint256 public intLiqThreshold;
    uint256 public allocatedAmt;
    uint256 public lastRewardCollection;

    event IntLiqThresholdChanged(uint256 intLiqThreshold);
    event VaultAddressUpdated(address oldAddress, address newAddress);

    /// @dev Initializer for setting up strategy internal state
    /// @param _usdcFraxPool Saddle pool address
    /// @param _sdl Saddle token address (Reward token)
    /// @param _lpToken Address of lp token.
    /// @param _pid frax-USDC Pool Id in the farm.
    /// @param _farmAddress Saddle Masterchef
    /// @param _vaultAddress Address of the vaultCore.
    /// @param _intLiqThreshold Threshold value for min interest to be collected.
    function initialize(
        address _usdcFraxPool,
        address _sdl,
        address _lpToken,
        uint256 _pid,
        address _farmAddress,
        address _vaultAddress,
        address _yieldReceiver,
        uint256 _intLiqThreshold
    ) external initializer {
        _isNonZeroAddr(_usdcFraxPool);
        _isNonZeroAddr(_farmAddress);
        lastRewardCollection = block.timestamp;
        pool = _usdcFraxPool;
        sdl = _sdl;
        farm = _farmAddress;
        lpToken = _lpToken;
        vaultAddress = _vaultAddress;
        pid = _pid;
        intLiqThreshold = _intLiqThreshold;
        rewardTokenAddress.push(_sdl);
        _initialize(
            _vaultAddress,
            _yieldReceiver,
            new address[](0),
            new address[](0)
        );
        for (uint8 i; i < 2; ++i) {
            _setPTokenAddress(address(ISaddlePool(pool).getToken(i)), _lpToken);
        }
    }

    /// @dev Change to a new interest liquidation threshold
    /// @dev collectInterest() would skip if interest available is less than
    //          the current intLiqThreshold
    function changeInterestLiqThreshold(
        uint256 _intLiqThreshold
    ) external onlyOwner {
        intLiqThreshold = _intLiqThreshold;
        emit IntLiqThresholdChanged(intLiqThreshold);
    }

    function updateVault(address _newVault) external onlyOwner {
        _isNonZeroAddr(_newVault);
        emit VaultAddressUpdated(vaultAddress, _newVault);
        vaultAddress = _newVault;
    }

    /// @inheritdoc InitializableAbstractStrategy
    function deposit(
        address _asset,
        uint256 _amount
    ) external override onlyVault nonReentrant {
        _supportedCollateral(_asset);
        _isValidAmount(_amount);
        IERC20(_asset).safeTransferFrom(vaultAddress, address(this), _amount);
    }

    /// @notice Allocate Funds to curve pool.
    /// @param _amounts Respective amounts of [USDC, FRAX] to be deposited.
    /// @dev _amounts to have the precision value of the respective tokens.
    /// @param _minMintAmt Min expected amount of LP tokens to be minted.
    function allocate(
        uint256[] memory _amounts,
        uint256 _minMintAmt
    ) external onlyOwner nonReentrant returns (uint256) {
        _isValidAmount(_amounts[0] + (_amounts[1]));
        IERC20(assetsMapped[0]).safeIncreaseAllowance(pool, _amounts[0]);
        IERC20(assetsMapped[1]).safeIncreaseAllowance(pool, _amounts[1]);
        uint256 pTokensMinted = ISaddlePool(pool).addLiquidity(
            _amounts,
            _minMintAmt,
            block.timestamp + DEADLINE
        );
        allocatedAmt = allocatedAmt + convertToCollateral(pTokensMinted);
        _stakeToFarm();

        emit Deposit(assetsMapped[0], lpToken, _amounts[0]);
        emit Deposit(assetsMapped[1], lpToken, _amounts[1]);
        return pTokensMinted;
    }

    /// @inheritdoc InitializableAbstractStrategy
    function withdraw(
        address _recipient,
        address _asset,
        uint256 _amount
    ) external override onlyVault nonReentrant returns (uint256) {
        _isNonZeroAddr(_recipient);
        _supportedCollateral(_asset);
        _isValidAmount(_amount);
        uint256 decimals = ERC20(_asset).decimals();
        uint256 precAdjustedAmt = _amount * 10 ** (18 - decimals);
        uint256 pTokensToBurn = convertToPToken(precAdjustedAmt);
        uint8 coinId = _getPoolCoinIndex(_asset);
        (, , uint256 totalPTokens) = getTotalPTokens();
        require(pTokensToBurn <= totalPTokens, "Insufficient LP");
        _withdrawFromFarm(pTokensToBurn);

        // Calculate the minimum amounts to receive based on slippage and
        uint256 minAmt = ISaddlePool(pool).calculateRemoveLiquidityOneToken(
            pTokensToBurn,
            coinId
        );

        IERC20(lpToken).safeIncreaseAllowance(pool, pTokensToBurn);
        uint256 amountRecv = ISaddlePool(pool).removeLiquidityOneToken(
            pTokensToBurn,
            coinId,
            minAmt,
            block.timestamp + DEADLINE
        );
        allocatedAmt = allocatedAmt - convertToCollateral(pTokensToBurn);
        _stakeToFarm();
        IERC20(_asset).safeTransfer(_recipient, amountRecv);
        emit Withdrawal(_asset, lpToken, amountRecv);
        return amountRecv;
    }

    /// @inheritdoc InitializableAbstractStrategy
    function withdrawToVault(
        address _asset,
        uint256 _amount
    ) external override onlyOwner nonReentrant returns (uint256) {
        uint256 unallocatedBal = checkUnallocatedBalance(_asset);
        uint256 amountToWithdraw = _amount <= unallocatedBal
            ? _amount
            : unallocatedBal;
        IERC20(_asset).safeTransfer(vaultAddress, amountToWithdraw);
        return amountToWithdraw;
    }

    /// @notice Function to withdraw amounts to vault
    /// @param _amounts amount of usdc and frax to be withdrawn
    /// @dev The _amounts should be with the respective precisions.
    /// @param _maxBurnAmt max Amount of LP tokens we are willing to burn.
    function redeemLPToVault(
        uint256[] memory _amounts,
        uint256 _maxBurnAmt
    ) external onlyOwner nonReentrant returns (uint256) {
        _isValidAmount(_amounts[0] + _amounts[1]);
        (, , uint256 totalPTokens) = getTotalPTokens();
        require(_maxBurnAmt <= totalPTokens, "Insufficient LP");
        _withdrawFromFarm(_maxBurnAmt);
        IERC20(lpToken).safeIncreaseAllowance(pool, _maxBurnAmt);
        uint256 lpBurned = ISaddlePool(pool).removeLiquidityImbalance(
            _amounts,
            _maxBurnAmt,
            block.timestamp + DEADLINE
        );
        IERC20(lpToken).safeApprove(pool, 0);
        allocatedAmt = allocatedAmt - convertToCollateral(lpBurned);
        _stakeToFarm();

        for (uint8 i; i < 2; ++i) {
            IERC20(assetsMapped[i]).safeTransfer(vaultAddress, _amounts[i]);
            emit Withdrawal(assetsMapped[i], lpToken, _amounts[i]);
        }
        return lpBurned;
    }

    /// @inheritdoc InitializableAbstractStrategy
    function collectInterest(
        address _asset
    )
        external
        override
        onlyVault
        nonReentrant
        returns (address[] memory interestAssets, uint256[] memory interestAmts)
    {
        uint256 interestAmt = checkInterestEarned(_asset);
        uint256 pTokensToBurn = convertToPToken(interestAmt);
        if (pTokensToBurn == 0 || interestAmt < intLiqThreshold) {
            return (new address[](2), new uint256[](2));
        }
        uint256[] memory minAmounts = ISaddlePool(pool)
            .calculateRemoveLiquidity(pTokensToBurn);
        _withdrawFromFarm(pTokensToBurn);
        IERC20(lpToken).safeIncreaseAllowance(pool, pTokensToBurn);
        interestAmts = ISaddlePool(pool).removeLiquidity(
            pTokensToBurn,
            minAmounts,
            block.timestamp + DEADLINE
        );
        interestAssets = assetsMapped;
        _stakeToFarm();
        for (uint8 i; i < 2; ++i) {
            IERC20(interestAssets[i]).safeTransfer(
                yieldReceiver,
                interestAmts[i]
            );
            emit InterestCollected(interestAssets[i], lpToken, interestAmts[i]);
        }
    }

    /// @inheritdoc InitializableAbstractStrategy
    function collectReward()
        external
        override
        onlyVault
        nonReentrant
        returns (address[] memory rewardAssets, uint256[] memory rewardAmts)
    {
        uint256 pendingSaddle = ISaddleFarm(farm).pendingSaddle(
            pid,
            address(this)
        );
        rewardAssets = new address[](1);
        rewardAmts = new uint256[](1);
        if (pendingSaddle > 0) {
            rewardAssets[0] = sdl;
            rewardAmts[0] = pendingSaddle;
            ISaddleFarm(farm).harvest(pid, yieldReceiver);
            emit RewardTokenCollected(
                rewardAssets[0],
                yieldReceiver,
                rewardAmts[0]
            );
        }
        lastRewardCollection = block.timestamp;
    }

    /// @inheritdoc InitializableAbstractStrategy
    function checkRewardEarned() external view override returns (uint256) {
        uint256 pendingSDL = 0;
        if (block.timestamp > lastRewardCollection) {
            pendingSDL = ISaddleFarm(farm).pendingSaddle(pid, address(this));
        }
        return pendingSDL;
    }

    /// @inheritdoc InitializableAbstractStrategy
    function checkLPTokenBalance(
        address
    ) external view override returns (uint256) {
        (, , uint256 totalPtokens) = getTotalPTokens();
        return totalPtokens;
    }

    /// @inheritdoc InitializableAbstractStrategy
    function supportsCollateral(
        address _asset
    ) public view override returns (bool) {
        return assetToPToken[_asset] != address(0);
    }

    /// @notice Function to get the unallocated balance of an asset.
    /// @dev Always try to keep it 0.
    /// @param _asset Address of the asset.
    function checkUnallocatedBalance(
        address _asset
    ) public view returns (uint256) {
        return IERC20(_asset).balanceOf(address(this));
    }

    /// @inheritdoc InitializableAbstractStrategy
    function checkAvailableBalance(
        address _asset
    ) public view override returns (uint256) {
        return checkBalance(_asset);
    }

    /// @inheritdoc InitializableAbstractStrategy
    function checkBalance(
        address _asset
    ) public view override returns (uint256) {
        uint256 i = _getPoolCoinIndex(_asset);
        return
            ISaddlePool(pool).calculateRemoveLiquidity(
                convertToPToken(allocatedAmt)
            )[i] + (checkUnallocatedBalance(_asset));
    }

    /**
    /// @notice Get the total amount held in the strategy
    /// @dev Assuming balanced withdrawal
     */
    function checkTotalBalance() public view returns (uint256) {
        (, , uint256 totalPTokens) = getTotalPTokens();
        return convertToCollateral(totalPTokens);
    }

    /// @inheritdoc InitializableAbstractStrategy
    function checkInterestEarned(
        address _asset
    ) public view override returns (uint256) {
        _supportedCollateral(_asset);
        uint256 totalInterest = checkTotalBalance() - allocatedAmt;
        // LP_amt * LP_virual price - allocatedAmt
        // TotalBalance = LP_amt * LP_virual price = (total FRAX amount + total VST amount we hold)
        return totalInterest;
    }

    /// @dev Calculate The LP token that exist in
    /// this contract or is staked in the Gauge (or in other words, the total
    /// amount platform tokens we own).
    function getTotalPTokens()
        public
        view
        returns (
            uint256 contractPTokens,
            uint256 farmPTokens,
            uint256 totalPTokens
        )
    {
        contractPTokens = IERC20(lpToken).balanceOf(address(this));
        farmPTokens = ISaddleFarm(farm).userInfo(pid, address(this)).amount;
        totalPTokens = contractPTokens + farmPTokens;
    }

    /// @notice Convert asset amounts to equiv
    /// @param _collateralAmt The amount of collateral to convert to LP amount
    //                          (_collateralAmt needs to be of precision 1e18)
    function convertToPToken(
        uint256 _collateralAmt
    ) public view returns (uint256) {
        return
            (_collateralAmt * PRICE_PREC) / ISaddlePool(pool).getVirtualPrice();
    }

    /// @notice Get the amount of pToken to stake such that a portion of pToken stays in farm
    /// @dev The portion is defined by stakePercentage
    /// @dev If there is already enough pToken in the farm, returns 0
    function convertToCollateral(
        uint256 _pTokenAmt
    ) public view returns (uint256) {
        return (_pTokenAmt * ISaddlePool(pool).getVirtualPrice()) / PRICE_PREC;
    }

    /// @notice Call the necessary approvals for the Curve pool and gauge
    /// @param _asset    Address of the asset
    /// @param _pToken   Address of the corresponding platform token (i.e. 2CRV)
    function _abstractSetPToken(
        address _asset,
        address _pToken
    ) internal override {}

    /// @notice Stake to farm such that a portion of pToken stays in farm
    /// @dev The portion is defined by stakePercentage
    /// @dev Stake nothing if is already enough pToken in the farm
    /// @dev If there is already an active stake, add the liquidity in that stake
    function _stakeToFarm() private {
        (uint256 contractPTokens, , ) = getTotalPTokens();
        if (contractPTokens > 0) {
            IERC20(assetToPToken[assetsMapped[0]]).safeIncreaseAllowance(
                address(farm),
                contractPTokens
            );
            ISaddleFarm(farm).deposit(pid, contractPTokens, address(this));
        }
    }

    /// @notice Withdraw everything from the farm
    /// @dev Revert if there is 0 stake, or if there are more than 1 stake
    function _withdrawFromFarm(uint256 _amount) private {
        ISaddleFarm.UserInfo memory farmDeposit = ISaddleFarm(farm).userInfo(
            pid,
            address(this)
        );
        require(_amount <= farmDeposit.amount, "Insufficient LP in farm");
        ISaddleFarm(farm).withdraw(pid, _amount, address(this));
    }

    /// @notice Check if `_asset` is supported in the strategy
    function _supportedCollateral(address _asset) private view {
        require(assetToPToken[_asset] != address(0), "Unsupported collateral");
    }

    /// @notice Get the index of the coin in VST-FRAX pool
    function _getPoolCoinIndex(address _asset) private view returns (uint8) {
        for (uint8 i; i < 2; ++i) {
            if (assetsMapped[i] == _asset) return i;
        }
        revert("Unsupported collateral");
    }
}
