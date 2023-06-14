pragma solidity 0.8.16;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ILPStaking} from "./interfaces/ILPStaking.sol";
import {IStargateRouter} from "./interfaces/IStargateRouter.sol";
import {IStargatePool} from "./interfaces/IStargatePool.sol";
import {InitializableAbstractStrategy} from "../InitializableAbstractStrategy.sol";

/// Pool Ids: https://stargateprotocol.gitbook.io/stargate/developers/pool-ids
// USDC: 1
// USDT: 2
// ETH: 13

/// Addresses https://stargateprotocol.gitbook.io/stargate/developers/contract-addresses/mainnet#arbitrum
// chainId: 10
// Router.sol: 0x53Bf833A5d6c4ddA888F69c22C88C9f356a41614
// RouterEth.sol:  0xbf22f0f184bCcbeA268dF387a49fF5238dD23E40
// StargateToken.sol: 0x6694340fc020c5E6B96567843da2df01b2CE1eb6
// Pool.sol (USDC): 0x892785f33CdeE22A30AEF750F285E18c18040c3e
// Pool.sol (USDT): 0xB6CfcF89a7B22988bfC96632aC2A9D6daB60d641
// LPStaking.sol: 0xeA8DfEE1898a7e0a59f7527F076106d7e44c2176
// Bridge.sol: 0x352d8275AAE3e0c2404d9f68f6cEE084B5bEB3DD

/// @title Stargate strategy for USDs protocol
/// @notice A yield earning strategy for USDs protocol
contract StargateStrategy is InitializableAbstractStrategy {
    using SafeERC20 for IERC20;
    struct AssetInfo {
        uint256 allocatedAmt; // tracks the allocated amount for an asset.
        uint256 intLiqThreshold; // tracks the interest liq threshold for an asset.
        uint256 rewardPID; // maps asset to farm reward pool id
        uint16 pid; // maps asset to pool id
    }

    uint256 public constant SLIPPAGE_PREC = 10000;
    bool public skipRwdValidation; // skip reward validation, for emergency use.
    address public router;
    address public farm;
    uint256 public withdrawSlippage;
    uint256 public depositSlippage;
    mapping(address => AssetInfo) private assetInfo;

    event SkipRwdValidationStatus(bool status);
    event SlippageChanged(uint256 depositSlippage, uint256 withdrawSlippage);
    event IntLiqThresholdChanged(
        address indexed asset,
        uint256 intLiqThreshold
    );

    function initialize(
        address _router,
        address _vaultAddress,
        address _yieldReceiver,
        address _stg,
        address _farm,
        uint256 _depositSlippage, // 200 = 2%
        uint256 _withdrawSlippage // 200 = 2%
    ) external initializer {
        _isNonZeroAddr(_router);
        _isNonZeroAddr(_stg);
        _isNonZeroAddr(_farm);
        router = _router;
        farm = _farm;
        depositSlippage = _depositSlippage;
        withdrawSlippage = _withdrawSlippage;

        address[] memory rewardTokens;
        rewardTokens = new address[](1);
        rewardTokens[0] = _stg;

        InitializableAbstractStrategy._initialize(
            _vaultAddress,
            _yieldReceiver,
            new address[](0),
            new address[](0)
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
        require(address(lpToken) == _pToken, "Incorrect _rewardPID");
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
        uint256 numAssets = assetsMapped.length;
        require(_assetIndex < numAssets, "Invalid index");
        address asset = assetsMapped[_assetIndex];
        require(assetInfo[asset].allocatedAmt == 0, "Collateral allocted");
        address pToken = assetToPToken[asset];

        assetsMapped[_assetIndex] = assetsMapped[numAssets - 1];
        assetsMapped.pop();
        delete assetToPToken[asset];
        delete assetInfo[asset];

        emit PTokenRemoved(asset, pToken);
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

    /// @notice Change to a new depositSlippage & withdrawSlippage
    /// @param _depositSlippage Slilppage tolerance for allocation
    /// @param _withdrawSlippage Slippage tolerance for withdrawal
    function changeSlippage(
        uint256 _depositSlippage,
        uint256 _withdrawSlippage
    ) external onlyOwner {
        require(
            _depositSlippage <= SLIPPAGE_PREC &&
                _withdrawSlippage <= SLIPPAGE_PREC,
            "Slippage exceeds 100%"
        );
        depositSlippage = _depositSlippage;
        withdrawSlippage = _withdrawSlippage;
        emit SlippageChanged(depositSlippage, withdrawSlippage);
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
        address sToken = _getSTokenFor(_asset);
        IERC20(_asset).safeTransferFrom(msg.sender, address(this), _amount);
        IERC20(_asset).safeApprove(router, _amount);

        // Add liquidity in the stargate pool.
        IStargateRouter(router).addLiquidity(
            assetInfo[_asset].pid,
            _amount,
            address(this)
        );

        // Deposit the generated sToken in the farm.
        // @dev We are assuming that the 100% of sToken is deposited in the farm.
        uint256 sTokenBal = IERC20(sToken).balanceOf(address(this));
        uint256 depositAmt = _convertToCollateral(_asset, sTokenBal);
        uint256 minDepositAmt = (_amount * (SLIPPAGE_PREC - depositSlippage)) /
            SLIPPAGE_PREC;

        require(depositAmt >= minDepositAmt, "Insufficient deposit amount");

        // Update the allocated amount in the strategy
        assetInfo[_asset].allocatedAmt += depositAmt;

        IERC20(sToken).safeApprove(farm, sTokenBal);
        ILPStaking(farm).deposit(assetInfo[_asset].rewardPID, sTokenBal);
        emit Deposit(_asset, sToken, depositAmt);
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
    function collectInterest(
        address _asset
    )
        external
        override
        nonReentrant
        returns (address[] memory interestAssets, uint256[] memory interestAmts)
    {
        uint256 earnedInterest = checkInterestEarned(_asset);
        interestAssets = new address[](1);
        interestAmts = new uint256[](1);
        if (earnedInterest > assetInfo[_asset].intLiqThreshold) {
            interestAssets[0] = _asset;
            interestAmts[0] = _withdraw(
                true,
                yieldReceiver,
                _asset,
                earnedInterest
            );
        }
    }

    /// @inheritdoc InitializableAbstractStrategy
    function collectReward()
        external
        override
        nonReentrant
        returns (address[] memory rewardAssets, uint256[] memory rewardAmts)
    {
        rewardAssets = new address[](1);
        rewardAssets[0] = rewardTokenAddress[0];
        rewardAmts = new uint256[](1);
        uint256 numAssets = assetsMapped.length;
        for (uint256 i = 0; i < numAssets; ) {
            address asset = assetsMapped[i];
            uint256 rewardAmt = checkPendingRewards(asset);
            if (
                rewardAmt > 0 &&
                (skipRwdValidation ||
                    rewardAmt <= IERC20(rewardTokenAddress[0]).balanceOf(farm))
            ) {
                ILPStaking(farm).deposit(assetInfo[asset].rewardPID, 0);
            }
            unchecked {
                ++i;
            }
        }
        rewardAmts[0] = IERC20(rewardTokenAddress[0]).balanceOf(address(this));
        IERC20(rewardTokenAddress[0]).safeTransfer(
            yieldReceiver,
            rewardAmts[0]
        );

        emit RewardTokenCollected(
            rewardTokenAddress[0],
            yieldReceiver,
            rewardAmts[0]
        );
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
        uint256 sTokenBal = checkLPTokenBalance(_asset);

        uint256 collateralBal = _convertToCollateral(_asset, sTokenBal);
        if (collateralBal <= assetInfo[_asset].allocatedAmt) {
            return 0;
        }
        return collateralBal - assetInfo[_asset].allocatedAmt;
    }

    /// @inheritdoc InitializableAbstractStrategy
    function checkBalance(
        address _asset
    ) public view override returns (uint256) {
        uint256 sTokenBal = checkLPTokenBalance(_asset);
        uint256 calcCollateralBal = _convertToCollateral(_asset, sTokenBal);
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

        IStargatePool pool = IStargatePool(_getSTokenFor(_asset));
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
        (uint256 sTokenStaked, ) = ILPStaking(farm).userInfo(
            assetInfo[_asset].rewardPID,
            address(this)
        );
        return sTokenStaked;
    }

    /// @inheritdoc InitializableAbstractStrategy
    function _abstractSetPToken(
        address _asset,
        address _pToken
    ) internal override {}

    /// @notice Convert amount of sToken to collateral.
    /// @param _asset Address for the asset
    /// @param _sTokenAmount Amount of sToken
    function _convertToCollateral(
        address _asset,
        uint256 _sTokenAmount
    ) internal view returns (uint256) {
        IStargatePool pool = IStargatePool(assetToPToken[_asset]);
        return
            (_sTokenAmount * pool.totalLiquidity() * pool.convertRate()) /
            pool.totalSupply();
    }

    /// @notice Convert amount of collateral to sToken.
    /// @param _asset Address for the asset
    /// @param _collateralAmount Amount of collateral
    function _convertToSToken(
        address _asset,
        uint256 _collateralAmount
    ) internal view returns (uint256) {
        IStargatePool pool = IStargatePool(assetToPToken[_asset]);
        return (_collateralAmount * pool.totalSupply()) / pool.totalLiquidity();
    }

    /// @notice Get the sToken this asset.
    ///      Fails if the sToken doesn't exist in our mappings.
    /// @param _asset Address of the asset
    /// @return Corresponding sToken to this asset
    function _getSTokenFor(address _asset) internal view returns (address) {
        address sToken = assetToPToken[_asset];
        require(sToken != address(0), "Collateral not supported");
        return sToken;
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
        address sToken = assetToPToken[_asset];
        uint256 sTokenAmt = _convertToSToken(_asset, _amount);
        ILPStaking(farm).withdraw(assetInfo[_asset].rewardPID, sTokenAmt);

        uint256 minRecvAmt = (_amount * (SLIPPAGE_PREC - withdrawSlippage)) /
            SLIPPAGE_PREC;
        uint256 amtRecv = IStargateRouter(router).instantRedeemLocal(
            assetInfo[_asset].pid,
            sTokenAmt,
            _recipient
        );
        require(amtRecv >= minRecvAmt, "Did not withdraw enough");

        if (!_withdrawInterest) {
            assetInfo[_asset].allocatedAmt -= amtRecv;
            emit Withdrawal(_asset, sToken, amtRecv);
        } else {
            emit InterestCollected(_asset, sToken, amtRecv);
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
