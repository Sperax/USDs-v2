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
        address tokenA; // 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9
        address tokenB; // 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8
        address router; // 0xc873fEcbd354f5A56E00E710B90EF4201db2448d
        address positionHelper; // 0xe458018Ad4283C90fB7F5460e24C4016F81b8175
        address factory; // 0x6EcCab422D763aC031210895C81787E87B43A652
        address nftPool; // 0xcC9f28dAD9b85117AB5237df63A5EE6fC50B02B7
    }

    bytes4 private constant _ERC721_RECEIVED = 0x150b7a02;
    uint256 public spNFTId;
    StrategyData public strategyData;
    mapping(address => uint256) private allocatedAmounts;

    event StrategyDataUpdated(StrategyData);
    event IncreaseLiquidity(uint256 liquidity, uint256 amountA, uint256 amountB);
    event DecreaseLiquidity(uint256 liquidity, uint256 amountA, uint256 amountB);

    error InvalidAsset();
    error NotCamelotNFTPool();
    error NotSelf();
    error AddLiquidityFailed();

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
        rewardTokenAddress[0] = grail;
        rewardTokenAddress[1] = xGrail;
    }

    /// @inheritdoc InitializableAbstractStrategy
    /// @dev Deposits `_amount` of `_asset` from caller into this contract.
    function deposit(address _asset, uint256 _amount) external override nonReentrant {
        if (!supportsCollateral(_asset)) revert CollateralNotSupported(_asset);
        Helpers._isNonZeroAmt(_amount);

        IERC20(_asset).safeTransferFrom(msg.sender, address(this), _amount);

        emit Deposit(_asset, _amount);
    }

    function allocate(address[] calldata _assets, uint256[2] calldata _amounts) external onlyOwner nonReentrant {
        StrategyData memory _strategyData = strategyData; // Gas savings

        if (_assets[0] != _strategyData.tokenA) revert CollateralNotSupported(_assets[0]);
        if (_assets[1] != _strategyData.tokenB) revert CollateralNotSupported(_assets[1]);
        Helpers._isNonZeroAmt(_amounts[0]);
        Helpers._isNonZeroAmt(_amounts[1]);

        IERC20(_assets[0]).safeApprove(_strategyData.router, _amounts[0]);
        IERC20(_assets[1]).safeApprove(_strategyData.router, _amounts[1]);

        uint256[] memory minAmounts = new uint256[](2);
        minAmounts[0] = _amounts[0] - (_amounts[0] * depositSlippage / Helpers.MAX_PERCENTAGE);
        minAmounts[1] = _amounts[1] - (_amounts[1] * depositSlippage / Helpers.MAX_PERCENTAGE);

        uint256 amountA;
        uint256 amountB;
        uint256 liquidity;
        // If allocation is happening for the first time
        if (spNFTId == 0) {
            IPositionHelper(_strategyData.positionHelper).addLiquidityAndCreatePosition(
                _assets[0],
                _assets[1],
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
            (amountA, amountB) = _checkAvailableBalance(liquidity);
        } else {
            address pair = IRouter(_strategyData.router).getPair(_assets[0], _assets[1]);
            (amountA, amountB,) = IRouter(_strategyData.router).addLiquidity(
                _assets[0],
                _assets[1],
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
        allocatedAmounts[_assets[0]] += amountA;
        allocatedAmounts[_assets[1]] += amountB;

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

    function redeem(uint256 _liquidityToWithdraw) external onlyOwner nonReentrant {
        StrategyData memory _sData = strategyData;
        (uint256 amountAMin, uint256 amountBMin) = _checkAvailableBalance(_liquidityToWithdraw);
        amountAMin = amountAMin = amountAMin * withdrawSlippage / Helpers.MAX_PERCENTAGE;
        amountBMin = amountBMin = amountBMin * withdrawSlippage / Helpers.MAX_PERCENTAGE;
        INFTPool(_sData.nftPool).withdrawFromPosition(spNFTId, _liquidityToWithdraw);
        (uint256 amountA, uint256 amountB) = IRouter(_sData.router).removeLiquidity(
            _sData.tokenA, _sData.tokenB, _liquidityToWithdraw, amountAMin, amountBMin, address(this), block.timestamp
        );
        allocatedAmounts[_sData.tokenA] -= amountA;
        allocatedAmounts[_sData.tokenB] -= amountB;
        emit DecreaseLiquidity(_liquidityToWithdraw, amountA, amountB);
    }

    /// @inheritdoc InitializableAbstractStrategy
    function collectReward() external override {
        address yieldReceiver = IStrategyVault(vault).yieldReceiver();
        INFTPool(strategyData.nftPool).harvestPositionTo(spNFTId, yieldReceiver);
    }

    function onNFTHarvest(
        address, /*operator*/
        address to,
        uint256, /*tokenId*/
        uint256 grailAmount,
        uint256 xGrailAmount
    ) external returns (bool) {
        // @todo figure out xGrail rewards
        require(msg.sender == strategyData.nftPool, "Not Allowed");
        emit RewardTokenCollected(rewardTokenAddress[0], to, grailAmount);
        emit RewardTokenCollected(rewardTokenAddress[1], to, xGrailAmount);
        return true;
    }

    // Functions needed by Camelot staking positions NFT manager
    function onERC721Received(address operator, address, /*from*/ uint256 tokenId, bytes calldata /*data*/ )
        external
        returns (bytes4)
    {
        if (msg.sender != strategyData.nftPool) revert NotCamelotNFTPool();
        if (operator != address(this)) revert NotSelf();
        spNFTId = tokenId;
        return _ERC721_RECEIVED;
    }

    function updateStrategyData(StrategyData memory _strategyData) external onlyOwner {
        strategyData = _strategyData;
        emit StrategyDataUpdated(_strategyData);
    }

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
    function checkRewardEarned() external view override returns (uint256 reward) {
        reward = INFTPool(strategyData.nftPool).pendingRewards(spNFTId);
    }

    function checkLPTokenBalance(address _asset) external view override returns (uint256 balance) {
        _checkValidAsset(_asset);
        (balance,,,,,,,) = INFTPool(strategyData.nftPool).getStakingPosition(spNFTId);
    }

    function checkBalance(address _asset) external view override returns (uint256 balance) {
        balance = allocatedAmounts[_asset] + IERC20(_asset).balanceOf(address(this));
    }

    function checkAvailableBalance(address _asset) external view override returns (uint256 balance) {
        (uint256 liquidity,,,,,,,) = INFTPool(strategyData.nftPool).getStakingPosition(spNFTId);
        (uint256 amountA, uint256 amountB) = _checkAvailableBalance(liquidity);
        if (_asset == strategyData.tokenA) balance = amountA;
        if (_asset == strategyData.tokenB) balance = amountB;
    }

    function checkAvailableLiquidity() external view returns (uint256 liquidity) {
        (liquidity,,,,,,,) = INFTPool(strategyData.nftPool).getStakingPosition(spNFTId);
    }

    function onNFTAddToPosition(address, /*operator*/ uint256, /*tokenId*/ uint256 /*lpAmount*/ )
        external
        pure
        returns (bool)
    {
        // @todo add checks
        return true;
    }

    function onNFTWithdraw(address, /*operator*/ uint256, /*tokenId*/ uint256 /*lpAmount*/ )
        external
        pure
        returns (bool)
    {
        // @todo add checks
        return true;
    }

    function checkInterestEarned(address /*_asset*/ ) external pure override returns (uint256) {
        // @todo implement
        return 0;
    }

    function collectInterest(address _asset) external pure override {
        // @todo implement
    }

    /// @inheritdoc InitializableAbstractStrategy
    function supportsCollateral(address _asset) public view override returns (bool) {
        return assetToPToken[_asset] != address(0);
    }

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

    function _checkAvailableBalance(uint256 liquidity) private view returns (uint256 amountA, uint256 amountB) {
        StrategyData memory _sData = strategyData;
        address pair = IRouter(_sData.router).getPair(_sData.tokenA, _sData.tokenB);
        uint256 balance0 = IERC20(_sData.tokenA).balanceOf(pair);
        uint256 balance1 = IERC20(_sData.tokenB).balanceOf(pair);
        uint256 _totalSupply = IPair(pair).totalSupply();
        amountA = (liquidity * balance0) / _totalSupply;
        amountB = (liquidity * balance1) / _totalSupply;
    }

    function _checkValidAsset(address _asset) private view {
        if (_asset != strategyData.tokenA && _asset != strategyData.tokenB) {
            revert InvalidAsset();
        }
    }
}