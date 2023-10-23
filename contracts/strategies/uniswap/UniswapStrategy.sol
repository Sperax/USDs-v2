// SPDX-License-Identifier: MIT
// TODO should we add a checkUnallocatedBalance?
pragma solidity 0.8.16;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {InitializableAbstractStrategy, Helpers, IStrategyVault} from "../InitializableAbstractStrategy.sol";
import {
    IUniswapV3Factory, INonfungiblePositionManager as INFPM, IUniswapV3TickSpacing
} from "./interfaces/UniswapV3.sol";
import {PositionValue} from "./libraries/PositionValue.sol";

/// @title UniswapV3 strategy for USDs protocol
/// @notice A yield earning strategy for USDs protocol
/// @author Sperax Foundation
/// @dev Parts of this code were inspired from https://docs.uniswap.org/contracts/v3/guides/providing-liquidity/the-full-contract.
contract UniswapStrategy is InitializableAbstractStrategy, IERC721Receiver {
    using SafeERC20 for IERC20;

    struct UniswapPoolData {
        address tokenA; // tokenA address
        address tokenB; // tokenB address
        uint24 feeTier; // fee tier
        int24 tickLower; // tick lower
        int24 tickUpper; // tick upper
    }

    INFPM public nfpm; // NonfungiblePositionManager contract
    IUniswapV3Factory public uniV3Factory; // UniswapV3 Factory contract
    UniswapPoolData public uniswapPoolData; // Uniswap pool data
    uint256 public lpTokenId; // LP token id minted for the uniswapPoolData config

    mapping(address => uint256) public allocatedAmt; // Tracks the allocated amount for an asset.

    // Events
    event MintNewPosition(uint256 tokenId);
    event IncreaseLiquidity(uint256 liquidity, uint256 amount0, uint256 amount1);
    event DecreaseLiquidity(uint256 liquidity, uint256 amount0, uint256 amount1);

    // Custom errors
    error InvalidUniswapPoolConfig();
    error NoRewardToken();
    error NotUniv3NFT();
    error NotSelf();
    error InvalidTickRange();

    /// @notice Initializes the strategy with the provided addresses.
    /// @param _vault The address of the USDs Vault contract.
    /// @param _nfpm The address of the NonfungiblePositionManager contract.
    /// @param _uniV3Factory The address of the Uniswap V3 Factory contract.
    function initialize(address _vault, address _nfpm, address _uniV3Factory) external initializer {
        Helpers._isNonZeroAddr(_nfpm);
        Helpers._isNonZeroAddr(_uniV3Factory);

        nfpm = INFPM(_nfpm);
        uniV3Factory = IUniswapV3Factory(_uniV3Factory);

        InitializableAbstractStrategy._initialize({_vault: _vault, _depositSlippage: 0, _withdrawSlippage: 0});
    }

    /// @notice Sets the addresses of the PToken contracts for the Uniswap pool.
    /// @param _uniswapPoolData The Uniswap pool data including token addresses and fee tier.
    function setPTokenAddress(UniswapPoolData memory _uniswapPoolData) external onlyOwner {
        address pool = uniV3Factory.getPool(_uniswapPoolData.tokenA, _uniswapPoolData.tokenB, _uniswapPoolData.feeTier);
        if (pool == address(0)) {
            revert InvalidUniswapPoolConfig();
        }

        _validateTickRange(pool, _uniswapPoolData.tickLower, _uniswapPoolData.tickUpper);

        // Sort tokens
        if (_uniswapPoolData.tokenA > _uniswapPoolData.tokenB) {
            (_uniswapPoolData.tokenA, _uniswapPoolData.tokenB) = (_uniswapPoolData.tokenB, _uniswapPoolData.tokenA);
        }

        address nfpmAddress = address(nfpm); // gas optimization

        uniswapPoolData = _uniswapPoolData;
        _setPTokenAddress(_uniswapPoolData.tokenA, nfpmAddress);
        _setPTokenAddress(_uniswapPoolData.tokenB, nfpmAddress);
    }

    /// @notice Removes PToken addresses based on asset indexes.
    /// @param _assetIndexes An array of asset indexes to remove PToken addresses.
    // TODO Is this function even valid for Uniswap?
    function removePToken(uint256[2] calldata _assetIndexes) external onlyOwner {
        for (uint256 i; i < 2;) {
            address asset = _removePTokenAddress(_assetIndexes[i]);
            if (allocatedAmt[asset] != 0) {
                revert CollateralAllocated(asset);
            }
            delete allocatedAmt[asset];
            unchecked {
                ++i;
            }
        }
    }

    /// @inheritdoc InitializableAbstractStrategy
    /// @dev Deposits a specified amount of an asset into this contract.
    function deposit(address _asset, uint256 _amount) external override nonReentrant {
        if (!supportsCollateral(_asset)) revert CollateralNotSupported(_asset);
        Helpers._isNonZeroAmt(_amount);

        IERC20(_asset).safeTransferFrom(msg.sender, address(this), _amount);

        emit Deposit(_asset, _amount);
    }

    /// @notice Allocates deposited assets into the Uniswap V3 pool to provide liquidity.
    /// @param _amounts An array containing the amounts of tokens to be allocated.
    /// @param _minMintAmt An array specifying the minimum minting amounts for each token.
    function allocate(uint256[2] calldata _amounts, uint256[2] calldata _minMintAmt) external onlyOwner nonReentrant {
        // TODO do we want to check non zero for each amount?
        Helpers._isNonZeroAmt(_amounts[0] + _amounts[1]);

        UniswapPoolData memory poolData = uniswapPoolData;

        // TODO should use safeIncreaseAllowance instead?
        IERC20(poolData.tokenA).safeApprove(address(nfpm), _amounts[0]);
        IERC20(poolData.tokenB).safeApprove(address(nfpm), _amounts[1]);

        uint128 liquidity;
        uint256 amount0;
        uint256 amount1;

        // Case 1: first time mint
        if (lpTokenId == 0) {
            uint256 tokenId;

            // Creates a new position and adds liquidity
            (tokenId, liquidity, amount0, amount1) = nfpm.mint(
                INFPM.MintParams({
                    token0: poolData.tokenA,
                    token1: poolData.tokenB,
                    fee: poolData.feeTier,
                    tickLower: poolData.tickLower,
                    tickUpper: poolData.tickUpper,
                    amount0Desired: _amounts[0],
                    amount1Desired: _amounts[1],
                    amount0Min: _minMintAmt[0],
                    amount1Min: _minMintAmt[1],
                    recipient: address(this),
                    deadline: block.timestamp
                })
            );

            lpTokenId = tokenId;

            emit MintNewPosition(tokenId);
        }
        // Case 2: minting to increase liquidity
        else {
            // Increases liquidity in the current range
            (liquidity, amount0, amount1) = nfpm.increaseLiquidity(
                INFPM.IncreaseLiquidityParams({
                    tokenId: lpTokenId,
                    amount0Desired: _amounts[0],
                    amount1Desired: _amounts[1],
                    amount0Min: _minMintAmt[0],
                    amount1Min: _minMintAmt[1],
                    deadline: block.timestamp
                })
            );
        }

        allocatedAmt[poolData.tokenA] += amount0;
        allocatedAmt[poolData.tokenB] += amount1;

        emit IncreaseLiquidity(uint256(liquidity), amount0, amount1);
    }

    /// @notice Redeems a specified amount of liquidity from the Uniswap V3 pool.
    /// @param _liquidity The amount of liquidity to redeem.
    /// @param _minBurnAmt An array specifying the minimum burn amounts for each token.
    function redeem(uint256 _liquidity, uint256[2] calldata _minBurnAmt) external onlyOwner nonReentrant {
        Helpers._isNonZeroAmt(_liquidity);

        UniswapPoolData memory poolData = uniswapPoolData;

        (uint256 amount0, uint256 amount1) = nfpm.decreaseLiquidity(
            INFPM.DecreaseLiquidityParams({
                tokenId: lpTokenId,
                liquidity: uint128(_liquidity),
                amount0Min: _minBurnAmt[0],
                amount1Min: _minBurnAmt[1],
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

        allocatedAmt[poolData.tokenA] -= amount0;
        allocatedAmt[poolData.tokenB] -= amount1;

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

        // set amount0Max and amount1Max to uint256.max to collect all fees
        INFPM.CollectParams memory params = INFPM.CollectParams({
            tokenId: lpTokenId,
            recipient: address(this),
            amount0Max: type(uint128).max,
            amount1Max: type(uint128).max
        });

        (uint256 amount0, uint256 amount1) = nfpm.collect(params);

        UniswapPoolData memory poolData = uniswapPoolData;

        if (amount0 != 0) {
            uint256 harvestAmt0 = _splitAndSendReward(poolData.tokenA, yieldReceiver, msg.sender, amount0);
            emit InterestCollected(poolData.tokenA, yieldReceiver, harvestAmt0);
        }

        if (amount1 != 0) {
            uint256 harvestAmt1 = _splitAndSendReward(poolData.tokenB, yieldReceiver, msg.sender, amount1);
            emit InterestCollected(poolData.tokenB, yieldReceiver, harvestAmt1);
        }
    }

    /// @notice Handles incoming ERC721 tokens (Uniswap V3 NFTs).
    /// @param operator The address that triggered the transfer.
    /// @return The selector of the `onERC721Received` function.
    function onERC721Received(address operator, address, uint256, bytes calldata) external view returns (bytes4) {
        // TODO check
        if (msg.sender != address(nfpm)) {
            revert NotUniv3NFT();
        }
        if (operator != address(this)) {
            revert NotSelf();
        }

        return IERC721Receiver.onERC721Received.selector;
    }

    /// @inheritdoc InitializableAbstractStrategy
    /// @dev The total balance, including allocated and unallocated amounts.
    function checkBalance(address _asset) external view virtual override returns (uint256 balance) {
        // Balance is always with token lpToken decimals
        balance = allocatedAmt[_asset] + IERC20(_asset).balanceOf(address(this));
    }

    /// @inheritdoc InitializableAbstractStrategy
    /// @dev The total balance, including allocated and unallocated amounts.
    function checkAvailableBalance(address _asset) external view virtual override returns (uint256) {
        UniswapPoolData memory poolData = uniswapPoolData;

        uint256 balance = IERC20(_asset).balanceOf(address(this));
        uint256 availableLiquidity =
            IERC20(_asset).balanceOf(uniV3Factory.getPool(poolData.tokenA, poolData.tokenB, poolData.feeTier));
        uint256 allocatedValue = allocatedAmt[_asset];
        if (availableLiquidity <= allocatedValue) {
            return availableLiquidity + balance;
        }
        return allocatedValue + balance;
    }

    /// @inheritdoc InitializableAbstractStrategy
    function checkInterestEarned(address _asset) external view override returns (uint256) {
        UniswapPoolData memory poolData = uniswapPoolData;

        // Get fees for both token0 and token1
        (uint256 feesToken0, uint256 feesToken1) = PositionValue.fees(nfpm, lpTokenId);

        if (_asset == poolData.tokenA) {
            return feesToken0;
        } else if (_asset == poolData.tokenB) {
            return feesToken1;
        } else {
            // Handle the case where _asset is neither token0 nor token1
            revert CollateralNotSupported(_asset);
        }
    }

    // TODO of no use.
    /// @inheritdoc InitializableAbstractStrategy
    function checkLPTokenBalance(address) external view override returns (uint256 balance) {
        balance = nfpm.balanceOf(address(this));
    }

    /// @inheritdoc InitializableAbstractStrategy
    /// @dev No rewards for the Uniswap V3 pool, hence revert.
    function collectReward() external pure override {
        // No reward token for Uniswap
        revert NoRewardToken();
    }

    /// @inheritdoc InitializableAbstractStrategy
    /// @dev No rewards for the Uniswap V3 pool, hence return 0.
    function checkRewardEarned() external pure override returns (uint256) {
        return 0;
    }

    /// @inheritdoc InitializableAbstractStrategy
    function supportsCollateral(address _asset) public view override returns (bool) {
        return assetToPToken[_asset] != address(0);
    }

    /// @dev Internal function to withdraw a specified amount of an asset.
    /// @param _recipient The address to which the assets will be sent.
    /// @param _asset The address of the asset to be withdrawn.
    /// @param _amount The amount of the asset to be withdrawn.
    function _withdraw(address _recipient, address _asset, uint256 _amount) internal {
        Helpers._isNonZeroAddr(_recipient);
        Helpers._isNonZeroAmt(_amount, "Must withdraw something");
        // TODO is this required?
        if (!supportsCollateral(_asset)) revert CollateralNotSupported(_asset);

        IERC20(_asset).safeTransfer(vault, _amount);

        emit Withdrawal(_asset, _amount);
    }

    // TODO of no use.
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
