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
        uint16 depositSlippage = 0;
        uint16 withdrawSlippage = 0;
        InitializableAbstractStrategy._initialize(
            _vaultAddress,
            depositSlippage,
            withdrawSlippage
        );
    }

    /// @notice Provide support for asset by passing its lpToken address.
    ///      This method can only be called by the system owner
    /// @param _asset    Address for the asset
    /// @param _lpToken   Address for the corresponding platform token
    function setPTokenAddress(
        address _asset,
        address _lpToken,
        uint256 _intLiqThreshold
    ) external onlyOwner {
        _setPTokenAddress(_asset, _lpToken);
        assetInfo[_asset] = AssetInfo({
            allocatedAmt: 0,
            intLiqThreshold: _intLiqThreshold
        });
    }

    /// @notice Remove a supported asset by passing its index.
    ///      This method can only be called by the system owner
    /// @param _assetIndex Index of the asset to be removed
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

        emit Deposit(_asset, _getPTokenFor(_asset), _amount);
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
    ) external override onlyVault nonReentrant {
        address yieldReceiver = IVault(vaultAddress).yieldReceiver();
        address harvestor = msg.sender;
        uint256 assetInterest = checkInterestEarned(_asset);
        if (assetInterest > assetInfo[_asset].intLiqThreshold) {
            uint256 interestCollected = aavePool.withdraw(
                _asset,
                assetInterest,
                address(this)
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
    function collectReward() external pure override {
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
        // Balance is always with token lpToken decimals
        balance = assetInfo[_asset].allocatedAmt;
    }

    /// @inheritdoc InitializableAbstractStrategy
    function checkAvailableBalance(
        address _asset
    ) public view override returns (uint256) {
        uint256 availableLiquidity = IERC20(_asset).balanceOf(
            _getPTokenFor(_asset)
        );
        uint256 allocatedValue = assetInfo[_asset].allocatedAmt;
        if (availableLiquidity <= allocatedValue) {
            return availableLiquidity;
        }
        return allocatedValue;
    }

    /// @inheritdoc InitializableAbstractStrategy
    function checkLPTokenBalance(
        address _asset
    ) public view override returns (uint256 balance) {
        address lpToken = _getPTokenFor(_asset);
        balance = IERC20(lpToken).balanceOf(address(this));
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
        address lpToken = _getPTokenFor(_asset);
        assetInfo[_asset].allocatedAmt -= _amount;
        uint256 actual = aavePool.withdraw(_asset, _amount, _recipient);
        require(actual == _amount, "Did not withdraw enough");
        emit Withdrawal(_asset, lpToken, actual);
        return actual;
    }

    /// @dev Internal method to respond to the addition of new asset / lpTokens
    ///      We need to give the AAVE lending pool approval to transfer the
    ///      asset.
    /// @param _asset Address of the asset to approve
    /// @param _lpToken Address of the lpToken
    function _abstractSetPToken(
        address _asset,
        address _lpToken
    ) internal view override {
        require(
            IAToken(_lpToken).UNDERLYING_ASSET_ADDRESS() == _asset,
            "Incorrect asset-lpToken pair"
        );
    }

    /// @notice Get the lpToken wrapped in the IERC20 interface for this asset.
    ///      Fails if the lpToken doesn't exist in our mappings.
    /// @param _asset Address of the asset
    /// @return Corresponding lpToken to this asset
    function _getPTokenFor(address _asset) internal view returns (address) {
        address lpToken = assetToPToken[_asset];
        require(lpToken != address(0), "Collateral not supported");
        return lpToken;
    }
}
