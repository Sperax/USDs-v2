// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {InitializableAbstractStrategy} from "../InitializableAbstractStrategy.sol";
import {IVault} from "../interfaces/IVault.sol";
import {IAaveLendingPool, IAToken, IPoolAddressesProvider} from "./interfaces/IAavePool.sol";

/// @title AAVE strategy for USDs protocol
/// @notice A yield earning strategy for USDs protocol
contract AaveStrategy is InitializableAbstractStrategy {
    using SafeERC20 for IERC20;
    struct AssetInfo {
        uint256 allocatedAmt; // Tracks the allocated amount of an asset.
        uint256 intLiqThreshold; // tracks the interest liq threshold for an asset.
    }
    uint16 private constant REFERRAL_CODE = 0;
    IAaveLendingPool public aavePool;
    mapping(address => AssetInfo) public assetInfo;

    event IntLiqThresholdChanged(
        address indexed asset,
        uint256 intLiqThreshold
    );

    /// Initializer for setting up strategy internal state. This overrides the
    /// InitializableAbstractStrategy initializer as AAVE needs several extra
    /// addresses for the rewards program.
    /// @param _platformAddress Address of the AAVE pool
    /// @param _vaultAddress Address of the vault
    function initialize(
        address _platformAddress, // AAVE PoolAddress provider 0xa97684ead0e402dC232d5A977953DF7ECBaB3CDb
        address _vaultAddress
    ) external initializer {
        _isNonZeroAddr(_platformAddress);
        _isNonZeroAddr(_vaultAddress);
        aavePool = IAaveLendingPool(
            IPoolAddressesProvider(_platformAddress).getPool()
        ); // aave Lending Pool 0x794a61358D6845594F94dc1DB02A252b5b4814aD

        InitializableAbstractStrategy._initialize(
            _vaultAddress,
            new address[](0),
            new address[](0)
        );
    }

    /// @notice Provide support for asset by passing its pToken address.
    ///      This method can only be called by the system owner
    /// @param _asset    Address for the asset
    /// @param _pToken   Address for the corresponding platform token
    function setPTokenAddress(
        address _asset,
        address _pToken,
        uint256 _intLiqThreshold
    ) external onlyOwner {
        _setPTokenAddress(_asset, _pToken);
        assetInfo[_asset] = AssetInfo({
            allocatedAmt: 0,
            intLiqThreshold: _intLiqThreshold
        });
    }

    /// @notice Remove a supported asset by passing its index.
    ///      This method can only be called by the system owner
    /// @param _assetIndex Index of the asset to be removed
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
        require(supportsCollateral(_asset), "Collateral not supported");
        assetInfo[_asset].intLiqThreshold = _intLiqThreshold;

        emit IntLiqThresholdChanged(_asset, _intLiqThreshold);
    }

    /// @inheritdoc InitializableAbstractStrategy
    function deposit(
        address _asset,
        uint256 _amount
    ) external override onlyVault nonReentrant {
        require(supportsCollateral(_asset), "Collateral not supported");
        require(_amount > 0, "Must deposit something");
        // Following line also doubles as a check that we are depositing
        // an asset that we support.
        assetInfo[_asset].allocatedAmt += _amount;

        IERC20(_asset).safeTransferFrom(msg.sender, address(this), _amount);
        IERC20(_asset).safeApprove(address(aavePool), _amount);
        aavePool.supply(_asset, _amount, address(this), REFERRAL_CODE);

        emit Deposit(_asset, _getATokenFor(_asset), _amount);
    }

    /// @inheritdoc InitializableAbstractStrategy
    function withdraw(
        address _recipient,
        address _asset,
        uint256 _amount
    ) external override onlyVault nonReentrant returns (uint256) {
        uint256 amountReceived = _withdraw(_recipient, _asset, _amount);
        return amountReceived;
    }

    /// @inheritdoc InitializableAbstractStrategy
    function withdrawToVault(
        address _asset,
        uint256 _amount
    ) external override onlyOwner nonReentrant returns (uint256) {
        uint256 amountReceived = _withdraw(vaultAddress, _asset, _amount);
        return amountReceived;
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
        address yieldReceiver = IVault(vaultAddress).yieldReceiver();
        address aToken = _getATokenFor(_asset);
        uint256 assetInterest = checkInterestEarned(_asset);
        interestAssets = new address[](1);
        interestAmts = new uint256[](1);
        if (assetInterest > assetInfo[_asset].intLiqThreshold) {
            uint256 actual = aavePool.withdraw(
                _asset,
                assetInterest,
                yieldReceiver
            );
            interestAssets[0] = _asset;
            interestAmts[0] = assetInterest;
            emit InterestCollected(_asset, aToken, actual);
        }
    }

    /// @inheritdoc InitializableAbstractStrategy
    function collectReward()
        external
        pure
        override
        returns (address[] memory, uint256[] memory)
    {
        revert("No reward incentive for AAVE");
        // No reward token for Aave
    }

    /// @inheritdoc InitializableAbstractStrategy
    function checkInterestEarned(
        address _asset
    ) public view override returns (uint256) {
        uint256 balance = checkLPTokenBalance(_asset);
        uint256 allocatedAmt = assetInfo[_asset].allocatedAmt;
        if (balance > allocatedAmt) {
            return balance - allocatedAmt;
        } else {
            return 0;
        }
    }

    /// @inheritdoc InitializableAbstractStrategy
    function checkBalance(
        address _asset
    ) public view override returns (uint256 balance) {
        // Balance is always with token aToken decimals
        balance = assetInfo[_asset].allocatedAmt;
    }

    /// @inheritdoc InitializableAbstractStrategy
    function checkAvailableBalance(
        address _asset
    ) public view override returns (uint256) {
        uint256 availableLiquidity = IERC20(_asset).balanceOf(
            _getATokenFor(_asset)
        );
        uint256 allocateValue = assetInfo[_asset].allocatedAmt;
        if (availableLiquidity <= allocateValue) {
            return availableLiquidity;
        }
        return allocateValue;
    }

    /// @inheritdoc InitializableAbstractStrategy
    function checkLPTokenBalance(
        address _asset
    ) public view override returns (uint256 balance) {
        address aToken = _getATokenFor(_asset);
        balance = IERC20(aToken).balanceOf(address(this));
    }

    /// @inheritdoc InitializableAbstractStrategy
    function supportsCollateral(
        address _asset
    ) public view override returns (bool) {
        return assetToPToken[_asset] != address(0);
    }

    /// @inheritdoc InitializableAbstractStrategy
    function checkRewardEarned() public pure override returns (uint256) {
        return 0;
    }

    /// @notice Withdraw asset from Aave lending Pool
    /// @param _recipient Address to receive withdrawn asset
    /// @param _asset Address of asset to withdraw
    /// @param _amount Amount of asset to withdraw
    function _withdraw(
        address _recipient,
        address _asset,
        uint256 _amount
    ) internal returns (uint256) {
        _isNonZeroAddr(_recipient);
        require(_amount > 0, "Invalid amount");
        address aToken = _getATokenFor(_asset);
        assetInfo[_asset].allocatedAmt -= _amount;
        uint256 actual = aavePool.withdraw(_asset, _amount, _recipient);
        require(actual == _amount, "Did not withdraw enough");
        emit Withdrawal(_asset, aToken, actual);
        return actual;
    }

    /// @dev Internal method to respond to the addition of new asset / aTokens
    ///      We need to give the AAVE lending pool approval to transfer the
    ///      asset.
    /// @param _asset Address of the asset to approve
    /// @param _aToken Address of the aToken
    function _abstractSetPToken(
        address _asset,
        address _aToken
    ) internal view override {
        require(
            IAToken(_aToken).UNDERLYING_ASSET_ADDRESS() == _asset,
            "Incorrect asset-pToken pair"
        );
    }

    /// @notice Get the aToken wrapped in the IERC20 interface for this asset.
    ///      Fails if the pToken doesn't exist in our mappings.
    /// @param _asset Address of the asset
    /// @return Corresponding aToken to this asset
    function _getATokenFor(address _asset) internal view returns (address) {
        address aToken = assetToPToken[_asset];
        require(aToken != address(0), "Collateral not supported");
        return aToken;
    }
}
