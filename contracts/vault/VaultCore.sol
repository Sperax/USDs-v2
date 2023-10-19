// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {OwnableUpgradeable, Initializable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {
    SafeERC20Upgradeable,
    IERC20Upgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IFeeCalculator} from "./interfaces/IFeeCalculator.sol";
import {IUSDs} from "../interfaces/IUSDs.sol";
import {IOracle} from "../interfaces/IOracle.sol";
import {IRebaseManager} from "../interfaces/IRebaseManager.sol";
import {ICollateralManager} from "./interfaces/ICollateralManager.sol";
import {IStrategy} from "./interfaces/IStrategy.sol";
import {Helpers} from "../libraries/Helpers.sol";

/// @title Savings Manager (Vault) Contract for USDs Protocol
/// @author Sperax Foundation
/// @notice This contract enables users to mint and redeem USDs with allowed collaterals.
/// @notice It also allocates collateral to strategies based on the Collateral Manager contract.
contract VaultCore is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address public feeVault; // SPABuyback contract
    address public yieldReceiver;
    address public collateralManager;
    address public feeCalculator;
    address public oracle;
    address public rebaseManager;

    event FeeVaultUpdated(address newFeeVault);
    event YieldReceiverUpdated(address newYieldReceiver);
    event CollateralManagerUpdated(address newCollateralManager);
    event FeeCalculatorUpdated(address newFeeCalculator);
    event RebaseManagerUpdated(address newRebaseManager);
    event OracleUpdated(address newOracle);
    event Minted(
        address indexed wallet, address indexed collateralAddr, uint256 usdsAmt, uint256 collateralAmt, uint256 feeAmt
    );
    event Redeemed(
        address indexed wallet, address indexed collateralAddr, uint256 usdsAmt, uint256 collateralAmt, uint256 feeAmt
    );
    event RebasedUSDs(uint256 rebaseAmt);
    event Allocated(address indexed collateral, address indexed strategy, uint256 amount);

    error AllocationNotAllowed(address collateral, address strategy, uint256 amount);
    error RedemptionPausedForCollateral(address collateral);
    error InsufficientCollateral(address collateral, address strategy, uint256 amount, uint256 availableAmount);
    error InvalidStrategy(address _collateral, address _strategyAddr);
    error MintFailed();

    constructor() {
        _disableInitializers();
    }

    function initialize() external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
    }

    /// @notice Updates the address receiving fee.
    /// @param _feeVault New desired address.
    function updateFeeVault(address _feeVault) external onlyOwner {
        Helpers._isNonZeroAddr(_feeVault);
        feeVault = _feeVault;
        emit FeeVaultUpdated(_feeVault);
    }

    /// @notice Updates the address receiving yields from strategies.
    /// @param _yieldReceiver New desired address.
    function updateYieldReceiver(address _yieldReceiver) external onlyOwner {
        Helpers._isNonZeroAddr(_yieldReceiver);
        yieldReceiver = _yieldReceiver;
        emit YieldReceiverUpdated(_yieldReceiver);
    }

    /// @notice Updates the address having the configuration for collaterals.
    /// @param _collateralManager New desired address.
    function updateCollateralManager(address _collateralManager) external onlyOwner {
        Helpers._isNonZeroAddr(_collateralManager);
        collateralManager = _collateralManager;
        emit CollateralManagerUpdated(_collateralManager);
    }

    /// @notice Updates the address having the configuration for rebases.
    /// @param _rebaseManager New desired address.
    function updateRebaseManager(address _rebaseManager) external onlyOwner {
        Helpers._isNonZeroAddr(_rebaseManager);
        rebaseManager = _rebaseManager;
        emit RebaseManagerUpdated(_rebaseManager);
    }

    /// @notice Updates the fee calculator library.
    /// @param _feeCalculator New desired address.
    function updateFeeCalculator(address _feeCalculator) external onlyOwner {
        Helpers._isNonZeroAddr(_feeCalculator);
        feeCalculator = _feeCalculator;
        emit FeeCalculatorUpdated(_feeCalculator);
    }

    /// @notice Updates the price oracle address.
    /// @param _oracle New desired address.
    function updateOracle(address _oracle) external onlyOwner {
        Helpers._isNonZeroAddr(_oracle);
        oracle = _oracle;
        emit OracleUpdated(_oracle);
    }

    /// @notice Allocates `_amount` of `_collateral` to `_strategy`.
    /// @param _collateral Address of the desired collateral.
    /// @param _strategy Address of the desired strategy.
    /// @param _amount Amount of collateral to be allocated.
    function allocate(address _collateral, address _strategy, uint256 _amount) external nonReentrant {
        // Validate the allocation based on the desired configuration
        if (!ICollateralManager(collateralManager).validateAllocation(_collateral, _strategy, _amount)) {
            revert AllocationNotAllowed(_collateral, _strategy, _amount);
        }
        IERC20Upgradeable(_collateral).safeIncreaseAllowance(_strategy, _amount);
        IStrategy(_strategy).deposit(_collateral, _amount);
        emit Allocated(_collateral, _strategy, _amount);
    }

    /// @notice Mint USDs by depositing collateral.
    /// @param _collateral Address of the collateral.
    /// @param _collateralAmt Amount of collateral to mint USDs with.
    /// @param _minUSDSAmt Minimum expected amount of USDs to be minted.
    /// @param _deadline Expiry time of the transaction.
    function mint(address _collateral, uint256 _collateralAmt, uint256 _minUSDSAmt, uint256 _deadline)
        external
        nonReentrant
    {
        _mint(_collateral, _collateralAmt, _minUSDSAmt, _deadline);
    }

    /// @notice Mint USDs by depositing collateral (backward compatibility).
    /// @param _collateral Address of the collateral.
    /// @param _collateralAmt Amount of collateral to mint USDs with.
    /// @param _minUSDSAmt Minimum expected amount of USDs to be minted.
    /// @param _deadline Expiry time of the transaction.
    /// @dev This function is for backward compatibility.
    function mintBySpecifyingCollateralAmt(
        address _collateral,
        uint256 _collateralAmt,
        uint256 _minUSDSAmt,
        uint256, // Deprecated
        uint256 _deadline
    ) external nonReentrant {
        _mint(_collateral, _collateralAmt, _minUSDSAmt, _deadline);
    }

    /// @notice Redeem USDs for `_collateral`.
    /// @param _collateral Address of the collateral.
    /// @param _usdsAmt Amount of USDs to be redeemed.
    /// @param _minCollAmt Minimum expected amount of collateral to be received.
    /// @param _deadline Expiry time of the transaction.
    /// @dev In case where there is not sufficient collateral available in the vault,
    ///      the collateral is withdrawn from the default strategy configured for the collateral.
    function redeem(address _collateral, uint256 _usdsAmt, uint256 _minCollAmt, uint256 _deadline)
        external
        nonReentrant
    {
        _redeem({
            _collateral: _collateral,
            _usdsAmt: _usdsAmt,
            _minCollateralAmt: _minCollAmt,
            _deadline: _deadline,
            _strategyAddr: address(0)
        });
    }

    /// @notice Redeem USDs for `_collateral` from a specific strategy.
    /// @param _collateral Address of the collateral.
    /// @param _usdsAmt Amount of USDs to be redeemed.
    /// @param _minCollAmt Minimum expected amount of collateral to be received.
    /// @param _deadline Expiry time of the transaction.
    /// @param _strategy Address of the strategy to withdraw excess collateral from.
    function redeem(address _collateral, uint256 _usdsAmt, uint256 _minCollAmt, uint256 _deadline, address _strategy)
        external
        nonReentrant
    {
        _redeem({
            _collateral: _collateral,
            _usdsAmt: _usdsAmt,
            _minCollateralAmt: _minCollAmt,
            _deadline: _deadline,
            _strategyAddr: _strategy
        });
    }

    /// @notice Get the expected redeem result.
    /// @param _collateral Desired collateral address.
    /// @param _usdsAmt Amount of USDs to be redeemed.
    /// @return calculatedCollateralAmt Expected amount of collateral to be released
    /// based on the price calculation.
    /// @return usdsBurnAmt Expected amount of USDs to be burnt in the process.
    /// @return feeAmt Amount of USDs collected as fee for redemption.
    /// @return vaultAmt Amount of collateral released from Vault.
    /// @return strategyAmt Amount of collateral to withdraw from the strategy.
    function redeemView(address _collateral, uint256 _usdsAmt)
        external
        view
        returns (
            uint256 calculatedCollateralAmt,
            uint256 usdsBurnAmt,
            uint256 feeAmt,
            uint256 vaultAmt,
            uint256 strategyAmt
        )
    {
        (calculatedCollateralAmt, usdsBurnAmt, feeAmt, vaultAmt, strategyAmt,) =
            _redeemView(_collateral, _usdsAmt, address(0));
    }

    /// @notice Get the expected redeem result from a specific strategy.
    /// @param _collateral Desired collateral address.
    /// @param _usdsAmt Amount of USDs to be redeemed.
    /// @param _strategyAddr Address of strategy to redeem from.
    /// @return calculatedCollateralAmt Expected amount of collateral to be released
    /// based on the price calculation.
    /// @return usdsBurnAmt Expected amount of USDs to be burnt in the process.
    /// @return feeAmt Amount of USDs collected as fee for redemption.
    /// @return vaultAmt Amount of collateral released from Vault.
    /// @return strategyAmt Amount of collateral to withdraw from the strategy.
    function redeemView(address _collateral, uint256 _usdsAmt, address _strategyAddr)
        external
        view
        returns (
            uint256 calculatedCollateralAmt,
            uint256 usdsBurnAmt,
            uint256 feeAmt,
            uint256 vaultAmt,
            uint256 strategyAmt
        )
    {
        (calculatedCollateralAmt, usdsBurnAmt, feeAmt, vaultAmt, strategyAmt,) =
            _redeemView(_collateral, _usdsAmt, _strategyAddr);
    }

    /// @notice Rebase USDs to share earned yield with the USDs holders.
    /// @dev If Rebase manager returns a non-zero value, it calls the rebase function on the USDs contract.
    function rebase() public {
        uint256 rebaseAmt = IRebaseManager(rebaseManager).fetchRebaseAmt();
        if (rebaseAmt != 0) {
            IUSDs(Helpers.USDS).rebase(rebaseAmt);
            emit RebasedUSDs(rebaseAmt);
        }
    }

    /// @notice Get the expected mint result (USDs amount, fee).
    /// @param _collateral Address of collateral.
    /// @param _collateralAmt Amount of collateral.
    /// @return Returns the expected USDs mint amount and fee for minting.
    function mintView(address _collateral, uint256 _collateralAmt) public view returns (uint256, uint256) {
        // Get mint configuration
        ICollateralManager.CollateralMintData memory collateralMintConfig =
            ICollateralManager(collateralManager).getMintParams(_collateral);

        // Fetch the latest price of the collateral
        IOracle.PriceData memory collateralPriceData = IOracle(oracle).getPrice(_collateral);
        // Calculate the downside peg
        uint256 downsidePeg =
            (collateralPriceData.precision * collateralMintConfig.downsidePeg) / Helpers.MAX_PERCENTAGE;

        // Downside peg check
        if (collateralPriceData.price < downsidePeg || !collateralMintConfig.mintAllowed) {
            return (0, 0);
        }

        // Skip fee collection for owner
        uint256 feePercentage = 0;
        if (msg.sender != owner()) {
            // Calculate mint fee based on collateral data
            feePercentage = IFeeCalculator(feeCalculator).getMintFee(_collateral);
        }

        // Normalize _collateralAmt to be of decimals 18
        uint256 normalizedCollateralAmt = _collateralAmt * collateralMintConfig.conversionFactor;

        // Calculate total USDs amount
        uint256 usdsAmt = normalizedCollateralAmt;
        if (collateralPriceData.price < collateralPriceData.precision) {
            usdsAmt = (normalizedCollateralAmt * collateralPriceData.price) / collateralPriceData.precision;
        }

        // Calculate the fee amount and usds to mint
        uint256 feeAmt = (usdsAmt * feePercentage) / Helpers.MAX_PERCENTAGE;
        uint256 toMinterAmt = usdsAmt - feeAmt;

        return (toMinterAmt, feeAmt);
    }

    /// @notice Mint USDs by depositing collateral.
    /// @param _collateral Address of the collateral.
    /// @param _collateralAmt Amount of collateral to deposit.
    /// @param _minUSDSAmt Minimum expected amount of USDs to be minted.
    /// @param _deadline Deadline timestamp for executing mint.
    /// @dev Mints USDs by locking collateral based on user input, ensuring a minimum
    /// expected minted amount is met.
    /// @dev If the minimum expected amount is not met, the transaction will revert.
    /// @dev Fee is collected, and collateral is transferred accordingly.
    /// @dev A rebase operation is triggered after minting.
    function _mint(address _collateral, uint256 _collateralAmt, uint256 _minUSDSAmt, uint256 _deadline) private {
        Helpers._checkDeadline(_deadline);
        (uint256 toMinterAmt, uint256 feeAmt) = mintView(_collateral, _collateralAmt);
        if (toMinterAmt == 0) revert MintFailed();
        if (toMinterAmt < _minUSDSAmt) {
            revert Helpers.MinSlippageError(toMinterAmt, _minUSDSAmt);
        }

        rebase();

        IERC20Upgradeable(_collateral).safeTransferFrom(msg.sender, address(this), _collateralAmt);
        IUSDs(Helpers.USDS).mint(msg.sender, toMinterAmt);
        if (feeAmt != 0) {
            IUSDs(Helpers.USDS).mint(feeVault, feeAmt);
        }

        emit Minted({
            wallet: msg.sender,
            collateralAddr: _collateral,
            usdsAmt: toMinterAmt,
            collateralAmt: _collateralAmt,
            feeAmt: feeAmt
        });
    }

    /// @notice Redeem USDs for collateral.
    /// @param _collateral Address of the collateral to receive.
    /// @param _usdsAmt Amount of USDs to redeem.
    /// @param _minCollateralAmt Minimum expected collateral amount to be received.
    /// @param _deadline Deadline timestamp for executing the redemption.
    /// @param _strategyAddr Address of the strategy to withdraw from.
    /// @dev Redeems USDs for collateral, ensuring a minimum expected collateral amount
    /// is met.
    /// @dev If the minimum expected collateral amount is not met, the transaction will revert.
    /// @dev Fee is collected, collateral is transferred, and a rebase operation is triggered.
    function _redeem(
        address _collateral,
        uint256 _usdsAmt,
        uint256 _minCollateralAmt,
        uint256 _deadline,
        address _strategyAddr
    ) private {
        Helpers._checkDeadline(_deadline);
        (
            uint256 collateralAmt,
            uint256 burnAmt,
            uint256 feeAmt,
            uint256 vaultAmt,
            uint256 strategyAmt,
            IStrategy strategy
        ) = _redeemView(_collateral, _usdsAmt, _strategyAddr);

        if (strategyAmt != 0) {
            // Withdraw from the strategy to VaultCore
            uint256 strategyAmtReceived = strategy.withdraw(address(this), _collateral, strategyAmt);
            // Update collateral amount according to the received amount from the strategy
            strategyAmt = strategyAmtReceived < strategyAmt ? strategyAmtReceived : strategyAmt;
            collateralAmt = vaultAmt + strategyAmt;
        }

        if (collateralAmt < _minCollateralAmt) {
            revert Helpers.MinSlippageError(collateralAmt, _minCollateralAmt);
        }

        // Collect USDs for Redemption
        IERC20Upgradeable(Helpers.USDS).safeTransferFrom(msg.sender, address(this), _usdsAmt);
        IUSDs(Helpers.USDS).burn(burnAmt);
        if (feeAmt != 0) {
            IERC20Upgradeable(Helpers.USDS).safeTransfer(feeVault, feeAmt);
        }
        // Transfer desired collateral to the user
        IERC20Upgradeable(_collateral).safeTransfer(msg.sender, collateralAmt);
        rebase();
        emit Redeemed({
            wallet: msg.sender,
            collateralAddr: _collateral,
            usdsAmt: burnAmt,
            collateralAmt: collateralAmt,
            feeAmt: feeAmt
        });
    }

    /// @notice Get the expected redeem result.
    /// @param _collateral Desired collateral address.
    /// @param _usdsAmt Amount of USDs to be redeemed.
    /// @param _strategyAddr Address of the strategy to redeem from.
    /// @return calculatedCollateralAmt Expected amount of collateral to be released
    ///         based on the price calculation.
    /// @return usdsBurnAmt Expected amount of USDs to be burnt in the process.
    /// @return feeAmt Amount of USDs collected as a fee for redemption.
    /// @return vaultAmt Amount of collateral released from Vault.
    /// @return strategyAmt Amount of collateral to withdraw from the strategy.
    /// @return strategy Strategy contract to withdraw collateral from.
    /// @dev Calculates the expected results of a redemption, including collateral
    ///      amount, fees, and strategy-specific details.
    /// @dev Ensures that the redemption is allowed for the specified collateral.
    /// @dev Calculates fees, burn amounts, and collateral amounts based on prices
    ///      and conversion factors.
    /// @dev Determines if collateral needs to be withdrawn from a strategy, and if
    ///      so, checks the availability of collateral in the strategy.

    function _redeemView(address _collateral, uint256 _usdsAmt, address _strategyAddr)
        private
        view
        returns (
            uint256 calculatedCollateralAmt,
            uint256 usdsBurnAmt,
            uint256 feeAmt,
            uint256 vaultAmt,
            uint256 strategyAmt,
            IStrategy strategy
        )
    {
        ICollateralManager.CollateralRedeemData memory collateralRedeemConfig =
            ICollateralManager(collateralManager).getRedeemParams(_collateral);

        if (!collateralRedeemConfig.redeemAllowed) {
            revert RedemptionPausedForCollateral(_collateral);
        }

        IOracle.PriceData memory collateralPriceData = IOracle(oracle).getPrice(_collateral);

        // Skip fee collection for Owner
        uint256 feePercentage = 0;
        if (msg.sender != owner()) {
            feePercentage = IFeeCalculator(feeCalculator).getRedeemFee(_collateral);
        }

        // Calculate actual fee and burn amount in terms of USDs
        feeAmt = (_usdsAmt * feePercentage) / Helpers.MAX_PERCENTAGE;
        usdsBurnAmt = _usdsAmt - feeAmt;

        // Calculate collateral amount
        calculatedCollateralAmt = usdsBurnAmt;
        if (collateralPriceData.price >= collateralPriceData.precision) {
            // Apply downside peg
            calculatedCollateralAmt = (usdsBurnAmt * collateralPriceData.precision) / collateralPriceData.price;
        }

        // Normalize collateral amount to be of base decimal
        calculatedCollateralAmt /= collateralRedeemConfig.conversionFactor;

        vaultAmt = IERC20Upgradeable(_collateral).balanceOf(address(this));

        if (calculatedCollateralAmt > vaultAmt) {
            unchecked {
                strategyAmt = calculatedCollateralAmt - vaultAmt;
            }
            // Withdraw from default strategy
            if (_strategyAddr == address(0)) {
                if (collateralRedeemConfig.defaultStrategy == address(0)) {
                    revert InsufficientCollateral(_collateral, address(0), calculatedCollateralAmt, vaultAmt);
                }
                strategy = IStrategy(collateralRedeemConfig.defaultStrategy);
                // Withdraw from specified strategy
            } else {
                if (!ICollateralManager(collateralManager).isValidStrategy(_collateral, _strategyAddr)) {
                    revert InvalidStrategy(_collateral, _strategyAddr);
                }
                strategy = IStrategy(_strategyAddr);
            }
            uint256 availableBal = strategy.checkAvailableBalance(_collateral);
            if (availableBal < strategyAmt) {
                revert InsufficientCollateral(
                    _collateral, _strategyAddr, calculatedCollateralAmt, vaultAmt + availableBal
                );
            }
        }
    }
}
