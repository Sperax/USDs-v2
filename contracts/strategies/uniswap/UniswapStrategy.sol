// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {InitializableAbstractStrategy, Helpers, IStrategyVault} from "../InitializableAbstractStrategy.sol";
import {
    IUniswapV3Factory, INonfungiblePositionManager as INFPM, IUniswapV3TickSpacing
} from "./interfaces/UniswapV3.sol";
import {IUniswapUtils} from "./interfaces/IUniswapUtils.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

/// @title UniswapV3 strategy for USDs protocol
/// @notice A yield earning strategy for USDs protocol
/// @author Sperax Foundation
/// @dev Parts of this code were inspired from https://docs.uniswap.org/contracts/v3/guides/providing-liquidity/the-full-contract.
/// Important contract addresses- https://docs.uniswap.org/contracts/v3/reference/deployments
contract UniswapStrategy is InitializableAbstractStrategy, IERC721Receiver {
    using SafeERC20 for IERC20;

    struct UniswapPoolData {
        address tokenA; // tokenA address
        address tokenB; // tokenB address
        uint24 feeTier; // fee tier
        int24 tickLower; // tick lower
        int24 tickUpper; // tick upper
        INFPM nfpm; // NonfungiblePositionManager contract
        IUniswapV3Factory uniV3Factory; // UniswapV3 Factory contract
        IUniswapV3Pool pool; // UniswapV3 pool address
        IUniswapUtils uniswapUtils; // UniswapHelper contract
        uint256 lpTokenId; // LP token id minted for the uniswapPoolData config
    }

    UniswapPoolData public uniswapPoolData; // Uniswap pool data

    // Events
    event MintNewPosition(uint256 tokenId);
    event IncreaseLiquidity(uint256 liquidity, uint256 amount0, uint256 amount1);
    event DecreaseLiquidity(uint256 liquidity, uint256 amount0, uint256 amount1);

    // Custom errors
    error InvalidUniswapPoolConfig();
    error NoRewardIncentive();
    error NotUniv3NFT();
    error NotSelf();
    error InvalidTickRange();

    /// @notice Initializes the strategy with the provided addresses and sets the addresses of the PToken contracts for the Uniswap pool.
    /// @param _vault The address of the USDs Vault contract.
    /// @param _uniswapPoolData The Uniswap pool data including token addresses and fee tier.
    /// @param _depositSlippage The deposit slippage percentage.
    function initialize(address _vault, UniswapPoolData memory _uniswapPoolData, uint16 _depositSlippage)
        external
        initializer
    {
        Helpers._isNonZeroAddr(address(_uniswapPoolData.uniswapUtils));

        address derivedPool = IUniswapV3Factory(_uniswapPoolData.uniV3Factory).getPool(
            _uniswapPoolData.tokenA, _uniswapPoolData.tokenB, _uniswapPoolData.feeTier
        );
        if (derivedPool == address(0) || derivedPool != address(_uniswapPoolData.pool)) {
            revert InvalidUniswapPoolConfig();
        }

        _validateTickRange(derivedPool, _uniswapPoolData.tickLower, _uniswapPoolData.tickUpper);

        // Sort tokens
        if (_uniswapPoolData.tokenA > _uniswapPoolData.tokenB) {
            (_uniswapPoolData.tokenA, _uniswapPoolData.tokenB) = (_uniswapPoolData.tokenB, _uniswapPoolData.tokenA);
        }

        uniswapPoolData = _uniswapPoolData;
        _setPTokenAddress(_uniswapPoolData.tokenA, address(_uniswapPoolData.nfpm));
        _setPTokenAddress(_uniswapPoolData.tokenB, address(_uniswapPoolData.nfpm));

        InitializableAbstractStrategy._initialize({
            _vault: _vault,
            _depositSlippage: _depositSlippage,
            _withdrawSlippage: 0
        });
    }

    /// @inheritdoc InitializableAbstractStrategy
    /// @dev Deposits a specified amount of an asset into this contract.
    function deposit(address _asset, uint256 _amount) external override nonReentrant {
        Helpers._isNonZeroAmt(_amount);
        if (!supportsCollateral(_asset)) revert CollateralNotSupported(_asset);

        IERC20(_asset).safeTransferFrom(msg.sender, address(this), _amount);

        emit Deposit(_asset, _amount);
    }

    /// @notice Allocates deposited assets into the Uniswap V3 pool to provide liquidity.
    /// @param _amounts An array containing the amounts of tokens to be allocated.
    function allocate(uint256[2] calldata _amounts) external nonReentrant {
        Helpers._isNonZeroAmt(_amounts[0] + _amounts[1]);

        UniswapPoolData storage poolData = uniswapPoolData;

        uint256[] memory minAmounts = new uint256[](2);
        minAmounts[0] = _amounts[0] - (_amounts[0] * depositSlippage / Helpers.MAX_PERCENTAGE);
        minAmounts[1] = _amounts[1] - (_amounts[1] * depositSlippage / Helpers.MAX_PERCENTAGE);

        IERC20(poolData.tokenA).safeIncreaseAllowance(address(poolData.nfpm), _amounts[0]);
        IERC20(poolData.tokenB).safeIncreaseAllowance(address(poolData.nfpm), _amounts[1]);

        uint128 liquidity;
        uint256 amount0;
        uint256 amount1;

        // Case 1: first time mint
        if (poolData.lpTokenId == 0) {
            uint256 tokenId;

            // Creates a new position and adds liquidity
            (tokenId, liquidity, amount0, amount1) = poolData.nfpm.mint(
                INFPM.MintParams({
                    token0: poolData.tokenA,
                    token1: poolData.tokenB,
                    fee: poolData.feeTier,
                    tickLower: poolData.tickLower,
                    tickUpper: poolData.tickUpper,
                    amount0Desired: _amounts[0],
                    amount1Desired: _amounts[1],
                    amount0Min: minAmounts[0],
                    amount1Min: minAmounts[1],
                    recipient: address(this),
                    deadline: block.timestamp
                })
            );

            poolData.lpTokenId = tokenId;

            emit MintNewPosition(tokenId);
        }
        // Case 2: minting to increase liquidity
        else {
            // Increases liquidity in the current range
            (liquidity, amount0, amount1) = poolData.nfpm.increaseLiquidity(
                INFPM.IncreaseLiquidityParams({
                    tokenId: poolData.lpTokenId,
                    amount0Desired: _amounts[0],
                    amount1Desired: _amounts[1],
                    amount0Min: minAmounts[0],
                    amount1Min: minAmounts[1],
                    deadline: block.timestamp
                })
            );
        }

        emit IncreaseLiquidity(uint256(liquidity), amount0, amount1);
    }

    /// @notice Redeems a specified amount of liquidity from the Uniswap V3 pool.
    /// @param _liquidity The amount of liquidity to redeem.
    /// @param _minAmountOut An array specifying the minimum burn amounts for each token.
    function redeem(uint256 _liquidity, uint256[2] calldata _minAmountOut) external onlyOwner nonReentrant {
        Helpers._isNonZeroAmt(_liquidity);

        uint256 lpTokenId = uniswapPoolData.lpTokenId;
        INFPM nfpm = uniswapPoolData.nfpm;

        (uint256 amount0, uint256 amount1) = nfpm.decreaseLiquidity(
            INFPM.DecreaseLiquidityParams({
                tokenId: lpTokenId,
                liquidity: uint128(_liquidity),
                amount0Min: _minAmountOut[0],
                amount1Min: _minAmountOut[1],
                deadline: block.timestamp
            })
        );

        nfpm.collect(
            INFPM.CollectParams({
                tokenId: lpTokenId,
                recipient: address(this),
                amount0Max: uint128(amount0),
                amount1Max: uint128(amount1)
            })
        );

        emit DecreaseLiquidity(_liquidity, amount0, amount1);
    }

    /// @inheritdoc InitializableAbstractStrategy
    /// @dev Withdraws a specified amount of an asset from this contract.
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
    /// @dev Withdraws a specified amount of an asset from this contract.
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
    /// @dev Collects interest earned from the Uniswap V3 pool and distributes it.
    function collectInterest(address) external override nonReentrant {
        address yieldReceiver = IStrategyVault(vault).yieldReceiver();
        address tokenA = uniswapPoolData.tokenA;
        address tokenB = uniswapPoolData.tokenB;

        // TODO not checking if lpTokenId == 0 and it will anyways revert on collect

        // set amount0Max and amount1Max to uint256.max to collect all fees
        (uint256 amount0, uint256 amount1) = uniswapPoolData.nfpm.collect(
            INFPM.CollectParams({
                tokenId: uniswapPoolData.lpTokenId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );

        if (amount0 != 0) {
            uint256 harvestAmt0 = _splitAndSendReward(tokenA, yieldReceiver, msg.sender, amount0);
            emit InterestCollected(tokenA, yieldReceiver, harvestAmt0);
        }

        if (amount1 != 0) {
            uint256 harvestAmt1 = _splitAndSendReward(tokenB, yieldReceiver, msg.sender, amount1);
            emit InterestCollected(tokenB, yieldReceiver, harvestAmt1);
        }
    }

    /// @notice Handles incoming ERC721 tokens (Uniswap V3 NFTs).
    /// @param operator The address that triggered the transfer.
    /// @return The selector of the `onERC721Received` function.
    function onERC721Received(address operator, address, uint256, bytes calldata) external view returns (bytes4) {
        // TODO check
        if (msg.sender != address(uniswapPoolData.nfpm)) {
            revert NotUniv3NFT();
        }
        if (operator != address(this)) {
            revert NotSelf();
        }

        return IERC721Receiver.onERC721Received.selector;
    }

    /// @inheritdoc InitializableAbstractStrategy
    /// @dev Calls checkBalance internally as the Uniswap V3 pools does not lock the deposited assets.
    function checkAvailableBalance(address _asset) external view override returns (uint256) {
        return IERC20(_asset).balanceOf(address(this));
    }

    /// @inheritdoc InitializableAbstractStrategy
    function checkInterestEarned(address _asset) external view override returns (uint256 interest) {
        if (!supportsCollateral(_asset)) revert CollateralNotSupported(_asset);

        uint256 lpTokenId = uniswapPoolData.lpTokenId;

        if (lpTokenId == 0) {
            return 0;
        }

        // Get fees for both token0 and token1
        (uint256 feesToken0, uint256 feesToken1) =
            uniswapPoolData.uniswapUtils.fees(address(uniswapPoolData.nfpm), lpTokenId);

        if (_asset == uniswapPoolData.tokenA) {
            return feesToken0;
        } else if (_asset == uniswapPoolData.tokenB) {
            return feesToken1;
        }
    }

    /// @inheritdoc InitializableAbstractStrategy
    function checkLPTokenBalance(address) external view override returns (uint256 balance) {
        if (uniswapPoolData.lpTokenId == 0) {
            return 0;
        }

        (,,,,,,, uint128 liquidity,,,,) = INFPM(uniswapPoolData.nfpm).positions(uniswapPoolData.lpTokenId);
        return uint256(liquidity);
    }

    /// @inheritdoc InitializableAbstractStrategy
    /// @dev No rewards for the Uniswap V3 pool, hence revert.
    function collectReward() external pure override {
        // No reward token for Uniswap
        revert NoRewardIncentive();
    }

    /// @inheritdoc InitializableAbstractStrategy
    /// @dev No rewards for the Uniswap V3 pool, hence return 0.
    function checkRewardEarned() external pure override returns (uint256) {
        return 0;
    }

    /// @inheritdoc InitializableAbstractStrategy
    /// @dev The total balance, including allocated and unallocated amounts.
    function checkBalance(address _asset) public view override returns (uint256 balance) {
        if (!supportsCollateral(_asset)) revert CollateralNotSupported(_asset);

        uint256 lpTokenId = uniswapPoolData.lpTokenId;
        uint256 unallocatedBalance = IERC20(_asset).balanceOf(address(this));

        if (lpTokenId == 0) {
            return unallocatedBalance;
        }

        (,,,,,,, uint128 liquidity,,,,) = INFPM(uniswapPoolData.nfpm).positions(lpTokenId);
        (uint256 amount0, uint256 amount1) = getAmountsForLiquidity(liquidity);

        if (_asset == uniswapPoolData.tokenA) {
            return amount0 + unallocatedBalance;
        } else if (_asset == uniswapPoolData.tokenB) {
            return amount1 + unallocatedBalance;
        }
    }

    /// @inheritdoc InitializableAbstractStrategy
    function supportsCollateral(address _asset) public view override returns (bool) {
        return assetToPToken[_asset] != address(0);
    }

    /**
     * @notice Calculates the amounts of token0 and token1 that will be received for a given liquidity amount.
     * @param _liquidity The amount of liquidity to be removed.
     * @return amount0 The amount of token0 that will be received.
     * @return amount1 The amount of token1 that will be received.
     * @dev This function reverts if the pool is not initialized.
     */
    function getAmountsForLiquidity(uint128 _liquidity) public view returns (uint256, uint256) {
        (uint160 sqrtPriceX96,,,,,,) = uniswapPoolData.pool.slot0();
        (uint256 amount0, uint256 amount1) = uniswapPoolData.uniswapUtils.getAmountsForLiquidity(
            sqrtPriceX96, uniswapPoolData.tickLower, uniswapPoolData.tickUpper, _liquidity
        );

        return (amount0, amount1);
    }

    /// @dev Internal function to withdraw a specified amount of an asset.
    /// @param _recipient The address to which the assets will be sent.
    /// @param _asset The address of the asset to be withdrawn.
    /// @param _amount The amount of the asset to be withdrawn.
    function _withdraw(address _recipient, address _asset, uint256 _amount) internal {
        Helpers._isNonZeroAmt(_amount, "Must withdraw something");
        // TODO is this required?
        if (!supportsCollateral(_asset)) revert CollateralNotSupported(_asset);

        IERC20(_asset).safeTransfer(_recipient, _amount);

        emit Withdrawal(_asset, _amount);
    }

    // solhint-disable-next-line no-empty-blocks
    function _abstractSetPToken(address _asset, address _lpToken) internal view override {}

    function _validateTickRange(address _pool, int24 _tickLower, int24 _tickUpper) private view {
        int24 spacing = IUniswapV3TickSpacing(_pool).tickSpacing();

        if (
            !(
                _tickLower < _tickUpper && _tickLower >= -887272 && _tickLower % spacing == 0 && _tickUpper <= 887272
                    && _tickUpper % spacing == 0
            )
        ) {
            revert InvalidTickRange();
        }
    }
}
