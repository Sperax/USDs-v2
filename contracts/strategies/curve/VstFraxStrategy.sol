// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {InitializableAbstractStrategy} from "../InitializableAbstractStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IOracle} from "../../interfaces/IOracle.sol";
import {ICurve2Pool} from "./interfaces/ICurve2Pool.sol";
import {IFraxFarm} from "./interfaces/IFraxFarm.sol";

/// @title Curve FRAX-VST Strategy
/// @notice Investment strategy for investing stablecoins via Curve 2Pool
/// @author Sperax Inc
contract VstFraxStrategy is InitializableAbstractStrategy {
    using SafeERC20 for IERC20;

    struct InitData {
        address platformAddress;
        address vaultAddress;
        address yieldReceiver;
        address fraxFarmAddr;
        address oracleAddr;
        uint256 assetPriceMin; // VST & Frax peg lower bound, 1e8 = $1
        uint256 assetPriceMax; // VST & Frax peg upper bound, 1e8 = $1
        uint256 depositSlippage; // deposit slippage tolerance LP -> asset, 200 = 2%
        uint256 withdrawSlippage; // withdrawSlippage Slippage tolerance asset -> LP, 200 = 2%
        uint256 intLiqThreshold;
        uint256 lockPeriod; // Farm stake initial lockup period, in seconds
        uint256 stakePercentage; // Percentage of LP to stake to farm, 200 = 2%
    }

    uint256 public constant PCT_PREC = 10000;
    uint256 public constant PRICE_PREC = 1e18;

    address public fraxFarm;
    address public curvePool;
    address public oracle;

    bool public skipPegCheck; // for emergency use
    uint256 public assetPriceMin;
    uint256 public assetPriceMax;
    uint256 public depositSlippage;
    uint256 public withdrawSlippage;
    uint256 public intLiqThreshold;
    uint256 public lockPeriod;
    uint256 public stakePercentage;

    uint256 public allocatedAmt;

    event SkipPegCheckStatus(bool status);
    event PegCheckBoundChanged(uint256 assetPriceMin, uint256 assetPriceMax);
    event SlippageChanged(uint256 depositSlippage, uint256 withdrawSlippage);
    event IntLiqThresholdChanged(uint256 intLiqThreshold);
    event FarmParameterChanged(uint256 lockPeriod, uint256 stakePercentage);

    /// @dev Initializer for setting up strategy internal state
    /// @param _data Initialization data for strategy
    function initialize(InitData calldata _data) external initializer {
        _isNonZeroAddr(_data.platformAddress);
        _isNonZeroAddr(_data.fraxFarmAddr);
        _isNonZeroAddr(_data.oracleAddr);
        fraxFarm = _data.fraxFarmAddr;
        curvePool = _data.platformAddress;
        oracle = _data.oracleAddr;
        rewardTokenAddress.push(IFraxFarm(_data.fraxFarmAddr).rewardsToken0());
        rewardTokenAddress.push(IFraxFarm(_data.fraxFarmAddr).rewardsToken1());
        for (uint256 i = 0; i < 2; ++i) {
            _setPTokenAddress(
                ICurve2Pool(curvePool).coins(i),
                _data.platformAddress
            );
        }
        assetPriceMin = _data.assetPriceMin;
        assetPriceMax = _data.assetPriceMax;
        depositSlippage = _data.depositSlippage;
        withdrawSlippage = _data.withdrawSlippage;
        intLiqThreshold = _data.intLiqThreshold;
        lockPeriod = _data.lockPeriod;
        stakePercentage = _data.stakePercentage;
        // Should call InitializableAbstractStrategy._initialize() at the end
        // otherwise abstractSetPToken() might fail
        _initialize(
            _data.vaultAddress,
            _data.yieldReceiver,
            new address[](0),
            new address[](0)
        );
    }

    /// @notice Toggle the skip VST & FRAX peg check flag.
    /// @dev When switched on, the token peg check will be skipped.
    function togglePegCheck() external onlyOwner {
        skipPegCheck = !skipPegCheck;
        emit SkipPegCheckStatus(skipPegCheck);
    }

    /// @notice Update the lower & upper bound of VST & FRAX price check
    function changeAssetPriceBound(
        uint256 _assetPriceMin,
        uint256 _assetPriceMax
    ) external onlyOwner {
        require(_assetPriceMin <= _assetPriceMax, "Invalid bound");
        assetPriceMin = _assetPriceMin;
        assetPriceMax = _assetPriceMax;
        emit PegCheckBoundChanged(assetPriceMin, assetPriceMax);
    }

    /// @notice Change to a new depositSlippage & withdrawSlippage
    function changeSlippage(
        uint256 _depositSlippage,
        uint256 _withdrawSlippage
    ) external onlyOwner {
        require(
            _depositSlippage <= PCT_PREC && _withdrawSlippage <= PCT_PREC,
            "Slippage exceeds 100%"
        );
        depositSlippage = _depositSlippage;
        withdrawSlippage = _withdrawSlippage;
        emit SlippageChanged(depositSlippage, withdrawSlippage);
    }

    /// @notice Change to a new interest liquidation threshold
    /// @dev collectInterest() would skip if interest available is less than
    ///        the current intLiqThreshold
    function changeInterestLiqThreshold(
        uint256 _intLiqThreshold
    ) external onlyOwner {
        intLiqThreshold = _intLiqThreshold;
        emit IntLiqThresholdChanged(intLiqThreshold);
    }

    /// @notice Change the parameters of Frax farm stake
    /// @param _lockPeriod       Farm stake initial lockup period, in seconds
    /// @param _stakePercentage  Percentage of LP to stake to farm, 200 = 2%
    function changeFarmParameters(
        uint256 _lockPeriod,
        uint256 _stakePercentage
    ) external onlyOwner {
        require(
            _lockPeriod >= IFraxFarm(fraxFarm).lock_time_min(),
            "lockPeriod less than minimum"
        );
        require(_stakePercentage <= PCT_PREC, "stakePercentage exceeds 100%");
        lockPeriod = _lockPeriod;
        stakePercentage = _stakePercentage;
        emit FarmParameterChanged(lockPeriod, stakePercentage);
    }

    /// @notice Deposit asset into the Curve Frax-VST balancedly
    /// @inheritdoc InitializableAbstractStrategy
    function deposit(
        address _asset,
        uint256 _amount
    ) external override onlyVault nonReentrant {
        require(supportsCollateral(_asset), "Unsupported collateral");
        _isValidAmount(_amount);
        IERC20(_asset).safeTransferFrom(msg.sender, address(this), _amount);
    }

    /// @notice Allocate Funds to curve pool.
    /// @param _amounts Respective amounts of [VST, FRAX] to be deposited.
    /// @param _minMintAmt Min expected amount of LP tokens to be minted.
    function allocate(
        uint256[2] memory _amounts,
        uint256 _minMintAmt
    ) external onlyOwner nonReentrant returns (uint256) {
        _isValidAmount(_amounts[0] + _amounts[1]);
        IERC20(assetsMapped[0]).safeIncreaseAllowance(curvePool, _amounts[0]);
        IERC20(assetsMapped[1]).safeIncreaseAllowance(curvePool, _amounts[1]);
        uint256 pTokensMinted = ICurve2Pool(curvePool).add_liquidity(
            _amounts,
            _minMintAmt
        );
        allocatedAmt = allocatedAmt + convertToCollateral(pTokensMinted);
        _stakeToFarm();

        emit Deposit(
            assetsMapped[0],
            address(assetToPToken[assetsMapped[0]]),
            _amounts[0]
        );
        emit Deposit(
            assetsMapped[1],
            address(assetToPToken[assetsMapped[1]]),
            _amounts[1]
        );
        return pTokensMinted;
    }

    /// @inheritdoc InitializableAbstractStrategy
    /// @dev Revert when VSt / FRAX depeg and _pegCheck() is activated
    function withdraw(
        address _recipient,
        address _asset,
        uint256 _amount
    ) external override onlyVault nonReentrant returns (uint256) {
        require(_pegCheck(), "VST or FRAX depegged");
        return _withdraw(_recipient, _asset, _amount);
    }

    /// @dev Withdraw a specific asset to Vault via owner
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

    /**
    /// @notice Function to withdraw amounts to vault
    /// @param _amounts amount of vst and frax to be withdrawn
    /// @param _maxBurnAmt max Amount of LP tokens we are willing to burn.
     */
    function redeemLPToVault(
        uint256[2] memory _amounts,
        uint256 _maxBurnAmt
    ) external onlyOwner nonReentrant returns (uint256) {
        _isValidAmount(_amounts[0] + _amounts[1]);
        (uint256 contractPTokens, , uint256 totalPTokens) = getTotalPTokens();
        require(_maxBurnAmt <= totalPTokens, "Insufficient LP token balance");
        if (contractPTokens < _maxBurnAmt) {
            _withdrawFromFarm();
        }
        uint256 lpBurned = ICurve2Pool(curvePool).remove_liquidity_imbalance(
            _amounts,
            _maxBurnAmt,
            vaultAddress
        );
        allocatedAmt = allocatedAmt - convertToCollateral(lpBurned);
        _stakeToFarm();
        emit Withdrawal(assetsMapped[0], address(curvePool), _amounts[0]);
        emit Withdrawal(assetsMapped[1], address(curvePool), _amounts[1]);
        return lpBurned;
    }

    /// @inheritdoc InitializableAbstractStrategy
    /// @dev    Skip when VST / FRAX depegged, or interest available is less
    ///           than intLiqThreshold
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
        uint256 pTokensToBurn = convertToPToken(interestAmt); // @note By default collect interest in FRAX only
        uint256 coinId = 1;
        if (
            pTokensToBurn == 0 || interestAmt < intLiqThreshold || !_pegCheck()
        ) {
            return (new address[](2), new uint256[](2));
        }
        uint256 amountRecv = _redeemPToken(
            pTokensToBurn,
            coinId,
            yieldReceiver
        );
        interestAssets = assetsMapped;
        interestAmts = new uint256[](2);
        interestAmts[coinId] = amountRecv;

        emit InterestCollected(assetsMapped[coinId], curvePool, amountRecv);
    }

    /// @inheritdoc InitializableAbstractStrategy
    function collectReward()
        external
        override
        onlyVault
        nonReentrant
        returns (address[] memory rewardAssets, uint256[] memory rewardAmts)
    {
        rewardAssets = rewardTokenAddress;
        address _yieldReceiver = yieldReceiver;
        // Collect claimable rewards
        rewardAmts = new uint256[](2);
        IFraxFarm(fraxFarm).getReward();
        for (uint256 i; i < 2; ++i) {
            // Since the contract will auotomatically collect some rewards
            // when unstaking, there can be rewards on the contract
            rewardAmts[i] = IERC20(rewardAssets[i]).balanceOf(address(this));
            IERC20(rewardAssets[i]).safeTransfer(_yieldReceiver, rewardAmts[i]);
            emit RewardTokenCollected(
                rewardAssets[i],
                _yieldReceiver,
                rewardAmts[i]
            );
        }
    }

    /// @inheritdoc InitializableAbstractStrategy
    function checkRewardEarned() external view override returns (uint256) {
        (uint256 claimableRwd0, uint256 claimableRwd1) = IFraxFarm(fraxFarm)
            .earned(address(this));
        uint256 onContractRwd = IERC20(rewardTokenAddress[0]).balanceOf(
            address(this)
        ) + IERC20(rewardTokenAddress[1]).balanceOf(address(this));
        return claimableRwd0 + claimableRwd1 + onContractRwd;
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

    /**
    /// @notice Function to get the unallocated balance of an asset.
    /// @dev Always try to keep it 0.
    /// @param _asset Address of the asset.
     */
    function checkUnallocatedBalance(
        address _asset
    ) public view returns (uint256) {
        return IERC20(_asset).balanceOf(address(this));
    }

    /// @inheritdoc InitializableAbstractStrategy
    function checkAvailableBalance(
        address _asset
    ) public view override returns (uint256) {
        if (!_pegCheck()) {
            return 0;
        }
        uint256 i = _getPoolCoinIndex(_asset);
        uint256 lockedValue;
        (bool staked, IFraxFarm.LockedStake memory stakeData) = _getStake();
        if (staked) {
            if (stakeData.ending_timestamp > block.timestamp) {
                lockedValue = convertToCollateral(stakeData.liquidity);
            }
        }
        uint256 availableAmt = allocatedAmt - lockedValue;
        return
            _getBalancedAmt(availableAmt)[i] + checkUnallocatedBalance(_asset);
    }

    /// @inheritdoc InitializableAbstractStrategy
    function checkBalance(
        address _asset
    ) public view override returns (uint256) {
        uint256 i = _getPoolCoinIndex(_asset);
        return
            _getBalancedAmt(allocatedAmt)[i] + checkUnallocatedBalance(_asset);
    }

    /// @notice Get the total amount held in the strategy
    /// @dev Assuming balanced withdrawal
    function checkTotalBalance() public view returns (uint256) {
        (, , uint256 totalPTokens) = getTotalPTokens();
        return convertToCollateral(totalPTokens);
    }

    /// @dev Calculate the total platform token balance (i.e. 2CRV) that exist in
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
        contractPTokens = IERC20(assetToPToken[assetsMapped[0]]).balanceOf(
            address(this)
        );
        farmPTokens = IFraxFarm(fraxFarm).lockedLiquidityOf(address(this)); //TODO: verify this
        totalPTokens = contractPTokens + farmPTokens;
    }

    /// @notice Convert asset amounts to equiv
    function convertToPToken(
        uint256 _collateralAmt
    ) public view returns (uint256) {
        return
            (_collateralAmt * PRICE_PREC) /
            ICurve2Pool(curvePool).get_virtual_price();
    }

    /// @notice Get the amount of pToken to stake such that a portion of pToken stays in farm
    /// @dev The portion is defined by stakePercentage
    /// @dev If there is already enough pToken in the farm, returns 0
    function convertToCollateral(
        uint256 _pTokenAmt
    ) public view returns (uint256) {
        return
            (_pTokenAmt * ICurve2Pool(curvePool).get_virtual_price()) /
            PRICE_PREC;
    }

    /// @notice Get the total amount of asset/collateral earned as interest
    /// @param _asset  Address of the asset
    /// @return interestEarned
    ///           The amount of asset/collateral earned as interest
    function checkInterestEarned(
        address _asset
    ) public view override returns (uint256) {
        require(supportsCollateral(_asset), "Unsupported collateral");
        uint256 totalInterest = checkTotalBalance() - allocatedAmt;
        // LP_amt * LP_virual price - allocatedAmt
        // TotalBalance = LP_amt * LP_virual price = (total FRAX amount + total VST amount we hold)
        return totalInterest;
    }

    /// @notice Call the necessary approvals for the Curve pool and gauge
    /// @param _asset    Address of the asset
    /// @param _pToken   Address of the corresponding platform token (i.e. 2CRV)
    function _abstractSetPToken(
        address _asset,
        address _pToken
    ) internal override {}

    /// @notice Withdraw assets from Curve pool balancedly (based on one token input)
    /// @param _recipient        Address to receive withdrawn assets
    /// @param _asset            Address of the asset used to calculate balanced withdrawal
    /// @param _amount           Amount of the asset used to calculate balanced withdrawal
    /// @return amount_received  Actual _asset amount received
    function _withdraw(
        address _recipient,
        address _asset,
        uint256 _amount
    ) private returns (uint256) {
        require(_recipient != address(0), "Invalid recipient");
        require(supportsCollateral(_asset), "Unsupported collateral");
        _isValidAmount(_amount);
        uint256 pTokensToBurn = convertToPToken(_amount);
        uint256 coinId = _getPoolCoinIndex(_asset);
        uint256 amountRecv = _redeemPToken(pTokensToBurn, coinId, _recipient);
        allocatedAmt = allocatedAmt - convertToCollateral(pTokensToBurn);
        emit Withdrawal(_asset, curvePool, amountRecv);
        return amountRecv;
    }

    /// @notice Function to redeem existing LP tokens.
    /// @dev Function withdraw only in single collateral defined by coinId.
    /// @param _pTokensToBurn Amount of LP tokens to burn.
    /// @param _coinId Id of the coin in curve pool (0 -> vst, 1 -> frax)
    /// @param _recipient Address to receive the redeemed tokens.
    function _redeemPToken(
        uint256 _pTokensToBurn,
        uint256 _coinId,
        address _recipient
    ) private returns (uint256 amountsRecv) {
        (uint256 contractPTokens, , ) = getTotalPTokens();
        // We have enough LP tokens, make sure they are all on this contract
        if (contractPTokens < _pTokensToBurn) {
            // Not enough of pool token exists on this contract, some must be
            // staked in Farm, unstake everything (retake later)
            _withdrawFromFarm();
        }
        // Calculate the minimum amounts to receive based on slippage and
        // expectedRecvAmts
        uint256 minAmt = ICurve2Pool(curvePool).calc_withdraw_one_coin(
            _pTokensToBurn,
            int128(int256(_coinId))
        );

        amountsRecv = ICurve2Pool(curvePool).remove_liquidity_one_coin(
            _pTokensToBurn,
            int128(int256(_coinId)),
            minAmt,
            _recipient
        );
        // Restake the unused liquidity
        _stakeToFarm();

        return amountsRecv;
    }

    /// @notice Stake to farm such that a portion of pToken stays in farm
    /// @dev The portion is defined by stakePercentage
    /// @dev Stake nothing if is already enough pToken in the farm
    /// @dev If there is already an active stake, add the liquidity in that stake
    function _stakeToFarm() private {
        (bool staked, IFraxFarm.LockedStake memory stakeData) = _getStake();
        uint256 amtToStake = _getStakeAmt();
        if (amtToStake == 0) {
            return;
        }
        // If there is no existing stake, stake
        IERC20(assetToPToken[assetsMapped[0]]).safeApprove(
            address(fraxFarm),
            amtToStake
        );
        if (!staked) {
            IFraxFarm(fraxFarm).stakeLocked(amtToStake, lockPeriod);
            // If there is one existing stake, add additional liquidity in that stake
        } else {
            IFraxFarm(fraxFarm).lockAdditional(stakeData.kek_id, amtToStake);
        }
    }

    /// @notice Withdraw everything from the farm
    /// @dev Revert if there is 0 stake, or if there are more than 1 stake
    function _withdrawFromFarm() private {
        (bool staked, IFraxFarm.LockedStake memory stakeData) = _getStake();
        require(staked, "Insufficient LP");
        IFraxFarm(fraxFarm).withdrawLocked(stakeData.kek_id);
    }

    /// @notice Get the index of the coin in VST-FRAX pool
    function _getPoolCoinIndex(address _asset) private view returns (uint256) {
        for (uint256 i; i < 2; ++i) {
            if (assetsMapped[i] == _asset) return i;
        }
        revert("Unsupported collateral");
    }

    /// @notice Get balanced token amounts based on one token input
    /// @param _asset    Address of the asset
    /// @param _amount   Amount of the asset
    /// @return amounts  The array of balanced token amounts
    function _getBalancedAmt(
        address _asset,
        uint256 _amount
    ) private view returns (uint256[2] memory amounts) {
        uint256 i = _getPoolCoinIndex(_asset);
        uint256[2] memory poolBalance = ICurve2Pool(curvePool).get_balances();
        uint256 j = i == 1 ? 0 : 1;
        // _amountJ = _amount / balance[i] * balance[j]
        uint256 _amountJ = (_amount * poolBalance[j]) / poolBalance[i];
        amounts[i] = _amount;
        amounts[j] = _amountJ;
    }

    /// @notice Get balanced token amounts based on total amount
    /// @param _totalAmt  Total amount
    /// @return amounts The array of balanced token amounts
    function _getBalancedAmt(
        uint256 _totalAmt
    ) private view returns (uint256[2] memory amounts) {
        uint256[2] memory poolBalance = ICurve2Pool(curvePool).get_balances();
        amounts[0] =
            (_totalAmt * poolBalance[0]) /
            (poolBalance[0] + poolBalance[1]);
        amounts[1] = _totalAmt - amounts[0];
    }

    /// @notice Get index of the stake, if there is an exisiting stake
    /// @dev The contract should have either 0 or 1 stake at any given time
    function _getStake()
        private
        view
        returns (bool staked, IFraxFarm.LockedStake memory stakeData)
    {
        IFraxFarm.LockedStake[] memory stakes = IFraxFarm(fraxFarm)
            .lockedStakesOf(address(this));

        uint256 numStakes = stakes.length;
        if (numStakes > 0) {
            staked = stakes[numStakes - 1].liquidity != 0;
            stakeData = stakes[numStakes - 1];
        }
    }

    /// @notice Get the amount of LP to stake such that stakePercentage % of LP
    ///        stays in the farm
    /// @dev If there is already enough pToken in the farm, returns 0
    function _getStakeAmt() private view returns (uint256 amtToStake) {
        (, uint256 farmPTokens, uint256 totalPTokens) = getTotalPTokens();
        uint256 idealFarmPTokens = (totalPTokens * stakePercentage) / PCT_PREC;
        amtToStake = idealFarmPTokens - farmPTokens;
    }

    /// @notice Check if VST & FRAX hold the peg
    function _pegCheck() private view returns (bool) {
        if (skipPegCheck) {
            return true;
        }
        IOracle.PriceData memory vstPrice = IOracle(oracle).getPrice(
            assetsMapped[0]
        );
        IOracle.PriceData memory fraxPrice = IOracle(oracle).getPrice(
            assetsMapped[1]
        );
        return
            vstPrice.price >= assetPriceMin &&
            vstPrice.price <= assetPriceMax &&
            fraxPrice.price >= assetPriceMin &&
            fraxPrice.price <= assetPriceMax;
    }
}
