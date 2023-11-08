//SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {InitializableAbstractStrategy, Helpers, IStrategyVault} from "../InitializableAbstractStrategy.sol";
import "./interfaces/ICamelot.sol";

/// @title Camelot strategy for USDs protocol
/// @author Sperax Foundation
/// @notice A yield earning strategy for USDs protocol
/// @notice Important contract addresses:https://docs.camelot.exchange/contracts/amm-v2
/// @dev Built for Camelot v2 which uses Algebra finance's implementation of Uniswap v2.
contract CamelotStrategy is InitializableAbstractStrategy, INFTHandler {
    using SafeERC20 for IERC20;

    struct StrategyData {
        address tokenA;
        address tokenB;
        address router;
        address positionHelper;
        address factory;
        address nftPool;
    }

    bytes4 private constant _ERC721_RECEIVED = 0x150b7a02;
    uint256 public spNFTId;
    StrategyData public strategyData;
    uint256 public allocatedAmount;

    event StrategyDataUpdated(StrategyData);
    event IncreaseLiquidity(uint256 liquidity, uint256 amountA, uint256 amountB);
    event DecreaseLiquidity(uint256 liquidity, uint256 amountA, uint256 amountB);
    // This event is emitted when xGrail.redeem is called
    // It is emitted while creation of redemption request and not actual redemption
    // The actual redemption emits RewardTokenCollected event
    event XGrailRedeemed(uint256 xGrailAmount);

    error InvalidAsset();
    error NotCamelotNFTPool();
    error AddLiquidityFailed();
    error InvalidRedeemIndex();

    /// @notice Initializer function of the strategy
    /// @param _strategyData variable of type StrategyData
    /// @param _vault USDs Vault address
    /// @param _depositSlippage Permitted deposit slippage 100 = 1%
    /// @param _withdrawSlippage Permitted withdrawal slippage 100 = 1%
    function initialize(
        StrategyData memory _strategyData,
        address _vault,
        uint16 _depositSlippage,
        uint16 _withdrawSlippage
    ) external initializer {
        _validateStrategyData(_strategyData);
        Helpers._isNonZeroAddr(_strategyData.tokenA);
        Helpers._isNonZeroAddr(_strategyData.tokenB);
        Helpers._isNonZeroAddr(_strategyData.router);
        Helpers._isNonZeroAddr(_strategyData.positionHelper);
        Helpers._isNonZeroAddr(_strategyData.factory);
        Helpers._isNonZeroAddr(_strategyData.nftPool);
        address pair = IRouter(_strategyData.router).getPair(_strategyData.tokenA, _strategyData.tokenB);
        strategyData = _strategyData;
        InitializableAbstractStrategy._initialize(_vault, _depositSlippage, _withdrawSlippage);
        _setPTokenAddress(_strategyData.tokenA, pair);
        _setPTokenAddress(_strategyData.tokenB, pair);
        (, address grail, address xGrail,,,,,) = INFTPool(_strategyData.nftPool).getPoolInfo();
        rewardTokenAddress.push(grail);
        rewardTokenAddress.push(xGrail);
    }

    /// @inheritdoc InitializableAbstractStrategy
    /// @dev Deposits `_amount` of `_asset` from caller into this contract.
    function deposit(address _asset, uint256 _amount) external override nonReentrant {
        if (!supportsCollateral(_asset)) revert CollateralNotSupported(_asset);
        Helpers._isNonZeroAmt(_amount);

        IERC20(_asset).safeTransferFrom(msg.sender, address(this), _amount);

        emit Deposit(_asset, _amount);
    }

    /// @notice A function to allocate funds into the strategy
    /// @param _amounts Array of amounts of `_assets` to be allocated
    function allocate(uint256[2] calldata _amounts) external nonReentrant {
        StrategyData memory _strategyData = strategyData; // Gas savings

        Helpers._isNonZeroAmt(_amounts[0]);
        Helpers._isNonZeroAmt(_amounts[1]);

        uint256[] memory minAmounts = new uint256[](2);
        minAmounts[0] = _amounts[0] - (_amounts[0] * depositSlippage / Helpers.MAX_PERCENTAGE);
        minAmounts[1] = _amounts[1] - (_amounts[1] * depositSlippage / Helpers.MAX_PERCENTAGE);

        uint256 amountA;
        uint256 amountB;
        uint256 liquidity;
        // If allocation is happening for the first time
        if (spNFTId == 0) {
            IERC20(_strategyData.tokenA).safeApprove(_strategyData.positionHelper, _amounts[0]);
            IERC20(_strategyData.tokenB).safeApprove(_strategyData.positionHelper, _amounts[1]);
            IPositionHelper(_strategyData.positionHelper).addLiquidityAndCreatePosition(
                _strategyData.tokenA,
                _strategyData.tokenB,
                _amounts[0],
                _amounts[1],
                minAmounts[0],
                minAmounts[1],
                block.timestamp,
                address(this), // to (receiver of nft)
                _strategyData.nftPool,
                0 // Lock duration
            );
            (liquidity,,,,,,,) = INFTPool(_strategyData.nftPool).getStakingPosition(spNFTId);
            (amountA, amountB) = _checkBalance(liquidity);
        } else {
            IERC20(_strategyData.tokenA).safeApprove(_strategyData.router, _amounts[0]);
            IERC20(_strategyData.tokenB).safeApprove(_strategyData.router, _amounts[1]);
            address pair = IRouter(_strategyData.router).getPair(_strategyData.tokenA, _strategyData.tokenB);
            (amountA, amountB,) = IRouter(_strategyData.router).addLiquidity(
                _strategyData.tokenA,
                _strategyData.tokenB,
                _amounts[0],
                _amounts[1],
                minAmounts[0],
                minAmounts[1],
                address(this), // liquidity tokens to be minted to
                block.timestamp // deadline
            );
            liquidity = IERC20(pair).balanceOf(address(this));
            if (liquidity == 0) revert AddLiquidityFailed();
            IERC20(pair).safeApprove(_strategyData.nftPool, liquidity);
            INFTPool(_strategyData.nftPool).addToPosition(spNFTId, liquidity);
        }

        allocatedAmount += liquidity;

        emit IncreaseLiquidity(liquidity, amountA, amountB);
    }

    /// @inheritdoc InitializableAbstractStrategy
    function withdraw(address _recipient, address _asset, uint256 _amount)
        external
        override
        onlyVault
        nonReentrant
        returns (uint256)
    {
        Helpers._isNonZeroAddr(_recipient);
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

    /// @notice A function to redeem collateral from strategy
    /// @param _liquidityToWithdraw Amount of liquidity (lp token amount) to be withdrawn
    function redeem(uint256 _liquidityToWithdraw) external onlyOwner nonReentrant {
        StrategyData memory _sData = strategyData;
        (uint256 amountAMin, uint256 amountBMin) = _checkBalance(_liquidityToWithdraw);
        amountAMin = amountAMin = amountAMin * withdrawSlippage / Helpers.MAX_PERCENTAGE;
        amountBMin = amountBMin = amountBMin * withdrawSlippage / Helpers.MAX_PERCENTAGE;
        INFTPool(_sData.nftPool).withdrawFromPosition(spNFTId, _liquidityToWithdraw);
        address pair = IRouter(_sData.router).getPair(_sData.tokenA, _sData.tokenB);
        IERC20(pair).safeApprove(_sData.router, _liquidityToWithdraw);
        (uint256 amountA, uint256 amountB) = IRouter(_sData.router).removeLiquidity(
            _sData.tokenA, _sData.tokenB, _liquidityToWithdraw, amountAMin, amountBMin, address(this), block.timestamp
        );

        allocatedAmount -= _liquidityToWithdraw;
        emit DecreaseLiquidity(_liquidityToWithdraw, amountA, amountB);
    }

    /// @notice A function to update the StrategyData struct if there is a change from Camelot's side
    /// @param _strategyData StrategyData type struct with the updated values
    function updateStrategyData(StrategyData memory _strategyData) external onlyOwner {
        _validateStrategyData(_strategyData);
        strategyData = _strategyData;
        emit StrategyDataUpdated(_strategyData);
    }

    /// @inheritdoc InitializableAbstractStrategy
    function collectReward() external override {
        address yieldReceiver = IStrategyVault(vault).yieldReceiver();
        INFTPool(strategyData.nftPool).harvestPosition(spNFTId);

        // Handling grail rewards
        _handleGrailRewards(yieldReceiver);

        // Handling xGrail
        address xGrail = rewardTokenAddress[1];
        // reusing variable rewardBalance
        uint256 xGrailBalance = IERC20(xGrail).balanceOf(address(this));
        if (xGrailBalance != 0) {
            IXGrailToken(xGrail).redeem(xGrailBalance, 15 days);
            emit XGrailRedeemed(xGrailBalance);
        }
    }

    /// @notice A function to collect vested grail and dividends
    /// @param redeemIndex Valid redeem index of a redeem request created in xGrail contract via `collectReward` function.
    /// @dev Collects dividends first and then finalizes redeem.
    function collectVestedGrailAndDividends(uint256 redeemIndex) external {
        address xGrail = rewardTokenAddress[1];
        if (redeemIndex >= IXGrailToken(xGrail).getUserRedeemsLength(address(this))) {
            revert InvalidRedeemIndex();
        }
        (,,, address dividendsContract,) = IXGrailToken(xGrail).getUserRedeem(address(this), redeemIndex);
        IDividendV2(dividendsContract).harvestAllDividends();
        uint256 dividendTokensLength = IDividendV2(dividendsContract).distributedTokensLength();
        address yieldReceiver = IStrategyVault(vault).yieldReceiver();
        address _token;
        uint256 _balance;
        uint256 _harvestAmt;
        for (uint8 i; i < dividendTokensLength;) {
            _token = IDividendV2(dividendsContract).distributedToken(i);
            if (_token != xGrail) {
                _balance = IERC20(_token).balanceOf(address(this));
                if (_balance != 0) {
                    _harvestAmt = _splitAndSendReward(_token, yieldReceiver, msg.sender, _balance);
                    emit RewardTokenCollected(_token, yieldReceiver, _harvestAmt);
                }
            }
        }
        IXGrailToken(xGrail).finalizeRedeem(redeemIndex);
        _handleGrailRewards(yieldReceiver);
    }

    // Functions needed by Camelot staking positions NFT manager
    /// @notice This function is called when NFT is minted to this address
    function onERC721Received(address, /*operator*/ address, /*from*/ uint256 tokenId, bytes calldata /*data*/ )
        external
        returns (bytes4)
    {
        if (msg.sender != strategyData.nftPool) revert NotCamelotNFTPool();
        spNFTId = tokenId;
        return _ERC721_RECEIVED;
    }

    /// @notice This function is called when rewards are harvested
    function onNFTHarvest(
        address, /*operator*/
        address, /*to*/
        uint256, /*tokenId*/
        uint256, /*grailAmount*/
        uint256 /*xGrailAmount*/
    ) external view returns (bool) {
        // @todo figure out xGrail rewards
        if (msg.sender != strategyData.nftPool) revert NotCamelotNFTPool();
        return true;
    }

    /// @notice This function is called when liquidity is added to an existing position
    function onNFTAddToPosition(address, /*operator*/ uint256, /*tokenId*/ uint256 /*lpAmount*/ )
        external
        view
        returns (bool)
    {
        if (msg.sender != strategyData.nftPool) revert NotCamelotNFTPool();
        return true;
    }

    /// @notice This function is called when liquidity is withdrawn from an NFT position
    function onNFTWithdraw(address, /*operator*/ uint256, /*tokenId*/ uint256 /*lpAmount*/ )
        external
        view
        returns (bool)
    {
        if (msg.sender != strategyData.nftPool) revert NotCamelotNFTPool();
        return true;
    }

    /// @notice This function can be called before allocating funds into the strategy
    ///         it accepts desired amounts, checks pool condition and returns the amount
    ///         which will be needed/ accepted by the strategy for a balanced allocation
    /// @param amountADesired Amount of token A that is desired to be allocated
    /// @param amountBDesired Amount of token B that is desired to be allocated
    /// @return amountA Amount A tokens which will be accepted in allocation
    /// @return amountB Amount B tokens which will be accepted in allocation
    function getDepositAmounts(uint256 amountADesired, uint256 amountBDesired)
        external
        view
        returns (uint256 amountA, uint256 amountB)
    {
        StrategyData memory _strategyData = strategyData;
        address pair = IRouter(_strategyData.router).getPair(_strategyData.tokenA, _strategyData.tokenB);
        (uint112 reserveA, uint112 reserveB,,) = IPair(pair).getReserves();
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint256 amountBOptimal = IRouter(_strategyData.router).quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = IRouter(_strategyData.router).quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    /// @inheritdoc InitializableAbstractStrategy
    function checkRewardEarned() external view override returns (uint256 rewards) {
        rewards = INFTPool(strategyData.nftPool).pendingRewards(spNFTId);
    }

    /// @inheritdoc InitializableAbstractStrategy
    function checkLPTokenBalance(address _asset) external view override returns (uint256 balance) {
        _checkValidAsset(_asset);
        (balance,,,,,,,) = INFTPool(strategyData.nftPool).getStakingPosition(spNFTId);
    }

    /// @inheritdoc InitializableAbstractStrategy
    /// @dev The total balance, including allocated and unallocated amounts.
    function checkBalance(address _asset) external view override returns (uint256 balance) {
        (uint256 liquidity,,,,,,,) = INFTPool(strategyData.nftPool).getStakingPosition(spNFTId);
        (uint256 amountA, uint256 amountB) = _checkBalance(liquidity);
        if (_asset == strategyData.tokenA) {
            balance = amountA + IERC20(_asset).balanceOf(address(this));
        }
        if (_asset == strategyData.tokenB) {
            balance = amountB + IERC20(_asset).balanceOf(address(this));
        }
    }

    /// @inheritdoc InitializableAbstractStrategy
    function checkInterestEarned(address) external pure override returns (uint256) {
        return 0;
    }

    /// @inheritdoc InitializableAbstractStrategy
    function collectInterest(address) external pure override {
        revert Helpers.CustomError("Operation not permitted");
    }

    /// @inheritdoc InitializableAbstractStrategy
    function checkAvailableBalance(address _asset) public view override returns (uint256 balance) {
        if (!supportsCollateral(_asset)) revert CollateralNotSupported(_asset);
        balance = IERC20(_asset).balanceOf(address(this));
    }

    /// @inheritdoc InitializableAbstractStrategy
    function supportsCollateral(address _asset) public view override returns (bool) {
        return assetToPToken[_asset] != address(0);
    }

    /// @inheritdoc InitializableAbstractStrategy
    /* solhint-disable no-empty-blocks */
    function _abstractSetPToken(address _asset, address _pToken) internal override {}

    /// @dev Internal function to withdraw a specified amount of an asset.
    /// @param _recipient The address to which the assets will be sent.
    /// @param _asset The address of the asset to be withdrawn.
    /// @param _amount The amount of the asset to be withdrawn.
    function _withdraw(address _recipient, address _asset, uint256 _amount) internal {
        Helpers._isNonZeroAmt(_amount, "Must withdraw something");
        IERC20(_asset).safeTransfer(_recipient, _amount);

        emit Withdrawal(_asset, _amount);
    }

    /// @notice A private function to handle grail rewards
    function _handleGrailRewards(address yieldReceiver) private {
        address grail = rewardTokenAddress[0];
        uint256 rewardBalance = IERC20(grail).balanceOf(address(this));
        if (rewardBalance != 0) {
            uint256 harvestAmt = _splitAndSendReward(grail, yieldReceiver, msg.sender, rewardBalance);
            emit RewardTokenCollected(grail, yieldReceiver, harvestAmt);
        }
    }

    /// @notice A function to check available balance of tokens as per liquidity
    /// @param liquidity Amount of liquidity present/ lp token balance
    /// @return amountA Amount A tokens available in pool
    /// @return amountB Amount B tokens available in pool
    function _checkBalance(uint256 liquidity) private view returns (uint256 amountA, uint256 amountB) {
        StrategyData memory _sData = strategyData;
        address pair = IRouter(_sData.router).getPair(_sData.tokenA, _sData.tokenB);
        uint256 balance0 = IERC20(_sData.tokenA).balanceOf(pair);
        uint256 balance1 = IERC20(_sData.tokenB).balanceOf(pair);
        uint256 _totalSupply = IPair(pair).totalSupply();
        amountA = (liquidity * balance0) / _totalSupply;
        amountB = (liquidity * balance1) / _totalSupply;
    }

    /// @notice Checks whether _asset is tokenA or tokenB
    /// @param _asset Address of asset to be checked
    /// @dev Reverts if asset is not valid
    function _checkValidAsset(address _asset) private view {
        if (_asset != strategyData.tokenA && _asset != strategyData.tokenB) {
            revert InvalidAsset();
        }
    }

    function _validateStrategyData(StrategyData memory _strategyData) private pure {
        Helpers._isNonZeroAddr(_strategyData.tokenA);
        Helpers._isNonZeroAddr(_strategyData.tokenB);
        Helpers._isNonZeroAddr(_strategyData.router);
        Helpers._isNonZeroAddr(_strategyData.positionHelper);
        Helpers._isNonZeroAddr(_strategyData.factory);
        Helpers._isNonZeroAddr(_strategyData.nftPool);
    }
}
