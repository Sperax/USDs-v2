//SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

abstract contract InitializableAbstractStrategy is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    address public vaultAddress;
    address public yieldReceiver;
    address[] internal assetsMapped;
    address[] public rewardTokenAddress;
    mapping(address => address) public assetToPToken;

    event VaultUpdated(address newVaultAddr);
    event yieldReceiverUpdated(address newYieldReceiver);
    event PTokenAdded(address indexed asset, address pToken);
    event PTokenRemoved(address indexed asset, address pToken);
    event Deposit(address indexed asset, address pToken, uint256 amount);
    event Withdrawal(address indexed asset, address pToken, uint256 amount);
    event InterestCollected(
        address indexed asset,
        address recipient,
        uint256 amount
    );
    event RewardTokenCollected(
        address indexed rwdToken,
        address recipient,
        uint256 amount
    );

    modifier onlyVault() {
        require(msg.sender == vaultAddress, "Caller is not the Vault");
        _;
    }

    modifier onlyVaultOrOwner() {
        require(
            msg.sender == vaultAddress || msg.sender == owner(),
            "Caller is not the Vault or owner"
        );
        _;
    }

    // Disabling initializer for the implementation contract.
    constructor() {
        _disableInitializers();
    }

    function updateVaultCore(address _newVault) external onlyOwner {
        vaultAddress = _newVault;
    }

    function updateYieldReciever(address _newYieldReceiver) external onlyOwner {
        yieldReceiver = _newYieldReceiver;
    }

    /// @dev Deposit an amount of asset into the platform
    /// @param _asset Address for the asset
    /// @param _amount Units of asset to deposit
    function deposit(address _asset, uint256 _amount) external virtual;

    /// @dev Withdraw an amount of asset from the platform.
    /// @param _recipient Address to which the asset should be sent
    /// @param _asset Address of the asset
    /// @param _amount Units of asset to withdraw
    /// @return amountReceived The actual amount received
    function withdraw(
        address _recipient,
        address _asset,
        uint256 _amount
    ) external virtual returns (uint256 amountReceived);

    /// @dev Withdraw an amount of asset from the platform to vault
    /// @param _asset  Address of the asset
    /// @param _amount  Units of asset to withdraw
    ///
    function withdrawToVault(
        address _asset,
        uint256 _amount
    ) external virtual returns (uint256 amount);

    /// @notice Withdraw the interest earned of asset from the platform.
    /// @param _asset Address of the asset
    /// @return interestAssets Token composition of the received interests
    /// @return interestAmts The amount of each token in the received interests
    function collectInterest(
        address _asset
    )
        external
        virtual
        returns (
            address[] memory interestAssets,
            uint256[] memory interestAmts
        );

    /// @notice Collect accumulated reward token and send to Vault
    /// @return rewardAssets Token composition of the received rewards
    /// @return rewardAmts The amount of each token in the received rewards
    function collectReward()
        external
        virtual
        returns (address[] memory rewardAssets, uint256[] memory rewardAmts);

    /// @notice Get the amount of a specific asset held in the strategy,
    ///           excluding the interest
    /// @dev Curve: assuming balanced withdrawal
    /// @param _asset Address of the asset
    ///
    function checkBalance(
        address _asset
    ) external view virtual returns (uint256);

    /// @notice Get the amount of a specific asset held in the strategy,
    ///         excluding the interest and any locked liquidity that is not
    ///         available for instant withdrawal
    /// @dev Curve: assuming balanced withdrawal
    /// @param _asset Address of the asset
    function checkAvailableBalance(
        address _asset
    ) external view virtual returns (uint256);

    /// @notice AAVE: Get the interest earned on a specific asset
    /// Curve: Get the total interest earned
    /// @dev Curve: to avoid double-counting, _asset has to be of index
    ///           'entryTokenIndex'
    /// @param _asset Address of the asset
    function checkInterestEarned(
        address _asset
    ) external view virtual returns (uint256);

    /// @notice Get the amount of claimable reward
    function checkRewardEarned() external view virtual returns (uint256);

    /// @notice Get the total LP token balance for a asset.
    /// @param _asset Address of the asset.
    function checkLPTokenBalance(
        address _asset
    ) external view virtual returns (uint256);

    /// @notice Check if an asset/collateral is supported.
    /// @param _asset Address of the asset
    /// @return bool Whether asset is supported
    function supportsCollateral(
        address _asset
    ) external view virtual returns (bool);

    function _initialize(
        address _vaultAddress,
        address _yieldReceiver,
        address[] memory _assets,
        address[] memory _pTokens
    ) internal {
        OwnableUpgradeable.__Ownable_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
        _isNonZeroAddr(_vaultAddress);
        _isNonZeroAddr(_yieldReceiver);

        vaultAddress = _vaultAddress;
        yieldReceiver = _yieldReceiver;
        for (uint8 i = 0; i < _assets.length; ) {
            _setPTokenAddress(_assets[i], _pTokens[i]);
            unchecked {
                ++i;
            }
        }
    }

    ///  @notice Provide support for asset by passing its pToken address.
    ///       Add to internal mappings and execute the platform specific,
    ///  abstract method `_abstractSetPToken`
    ///  @param _asset Address for the asset
    ///  @param _pToken Address for the corresponding platform token
    function _setPTokenAddress(address _asset, address _pToken) internal {
        require(assetToPToken[_asset] == address(0), "pToken already set");
        _isNonZeroAddr(_asset);
        _isNonZeroAddr(_pToken);

        assetToPToken[_asset] = _pToken;
        assetsMapped.push(_asset);

        emit PTokenAdded(_asset, _pToken);
        // Perform any strategy specific logic.
        _abstractSetPToken(_asset, _pToken);
    }

    /// @notice Call the necessary approvals for the underlying strategy
    /// @param _asset Address of the asset
    /// @param _pToken Address of the corresponding reciept token.
    function _abstractSetPToken(
        address _asset,
        address _pToken
    ) internal virtual;

    /// @notice Check for non-zero address
    /// @param _addr Address to be validated
    function _isNonZeroAddr(address _addr) internal pure {
        require(_addr != address(0), "Invalid address");
    }

    /// @notice Check for non-zero mount
    /// @param _amount Amount to be validated
    function _isValidAmount(uint256 _amount) internal pure {
        require(_amount > 0, "Invalid amount");
    }
}
