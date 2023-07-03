//SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {AccessControlUpgradeable, Initializable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {SafeERC20Upgradeable, IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IFeeCalculator} from "./interfaces/IFeeCalculator.sol";
import {IUSDs} from "../interfaces/IUSDs.sol";
import {IOracle} from "../interfaces/IOracle.sol";
import {IRebaseManager} from "../interfaces/IRebaseManager.sol";
import {ICollateralManager} from "./interfaces/ICollateralManager.sol";
import {IStrategy} from "./interfaces/IStrategy.sol";

contract VaultCore is
    Initializable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    bytes32 private constant ALLOCATOR_ROLE = keccak256("ALLOCATOR_ROLE");
    address public constant USDS = 0xD74f5255D557944cf7Dd0E45FF521520002D5748;

    address public feeVault;
    address public yieldReceiver;
    address public collateralManager;
    address public feeCalculator;
    address public oracle;
    address public rebaseManager;

    event FeeVaultChanged(address newFeeManager);
    event YieldReceiverChanged(address newYieldReceiver);
    event CollateralManagerChanged(address newCollateralManagerChanged);
    event FeeCalculatorChanged(address newFeeCalculator);
    event OracleChanged(address newOracle);
    event Minted(
        address indexed wallet,
        address indexed collateralAddr,
        uint256 usdsAmt,
        uint256 collateralAmt,
        uint256 feeAmt
    );
    event Redeemed(
        address indexed wallet,
        address indexed collateralAddr,
        uint256 usdsAmt,
        uint256 collateralAmt,
        uint256 feeAmt
    );
    event RebasedUSDs(uint256 rebaseAmt);

    modifier onlyOwner() {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Unauthorized caller");
        _;
    }

    /// @notice Updates the address receiving fee
    /// @param _feeVault updated address of the fee vault
    function updateFeeVault(address _feeVault) external onlyOwner {
        _isNonZeroAddr(_feeVault);
        feeVault = _feeVault;
        emit FeeVaultChanged(feeVault);
    }

    /// @notice Updates the address receiving yields from strategies
    /// @param _yieldReceiver new desired address
    function updateYieldReceiver(address _yieldReceiver) external onlyOwner {
        _isNonZeroAddr(_yieldReceiver);
        yieldReceiver = _yieldReceiver;
        emit YieldReceiverChanged(yieldReceiver);
    }

    /// @notice Updates the address having the config for collaterals
    /// @param _collateralManager new desired address
    function updateCollateralManager(
        address _collateralManager
    ) external onlyOwner {
        _isNonZeroAddr(_collateralManager);
        collateralManager = _collateralManager;
        emit CollateralManagerChanged(collateralManager);
    }

    /// @notice Updates the fee calculator library
    /// @param _feeCalculator new desired address
    function updateFeeCalculator(address _feeCalculator) external onlyOwner {
        _isNonZeroAddr(_feeCalculator);
        feeCalculator = _feeCalculator;
        emit FeeCalculatorChanged(yieldReceiver);
    }

    /// @notice Updates the price oracle address.
    function updateOracle(address _oracle) external onlyOwner {
        _isNonZeroAddr(_oracle);
        oracle = _oracle;
        emit OracleChanged(oracle);
    }

    /// @notice Allocate `_amount` of`_collateral` to `_strategy`
    /// @param _collateral address of the desired collateral
    /// @param _strategy address of the desired strategy
    /// @param _amount amount of collateral to be allocated
    function allocate(
        address _collateral,
        address _strategy,
        uint256 _amount
    ) external nonReentrant {
        require(hasRole(ALLOCATOR_ROLE, msg.sender), "Unauthorized caller");

        // Validate the allocation is based on the desired configuration
        require(
            ICollateralManager(collateralManager).validateAllocation(
                _collateral,
                _strategy,
                _amount
            ),
            "Allocation not allowed"
        );
        IERC20Upgradeable(_collateral).safeIncreaseAllowance(
            _strategy,
            _amount
        );
        IStrategy(_strategy).deposit(_collateral, _amount);
    }

    /// @notice mint USDs by depositing collateral
    /// @param _collateral address of the collateral
    /// @param _collateralAmt amount of collateral to mint USDs with
    /// @param _minUSDSAmt minimum expected amount of USDs to be minted
    /// @param _deadline the expiry time of the transaction
    function mint(
        address _collateral,
        uint256 _collateralAmt,
        uint256 _minUSDSAmt,
        uint256 _deadline
    ) external nonReentrant {
        require(block.timestamp <= _deadline, "Deadline passed");
        _mint(_collateral, _collateralAmt, _minUSDSAmt);
    }

    /// @notice mint USDs by depositing collateral
    /// @param _collateral address of the collateral
    /// @param _collateralAmt amount of collateral to mint USDs with
    /// @param _minUSDSAmt minimum expected amount of USDs to be minted
    /// @param _deadline the expiry time of the transaction
    /// @dev This function is for backward compatibility
    function mintBySpecifyingCollateralAmt(
        address _collateral,
        uint256 _collateralAmt,
        uint256 _minUSDSAmt,
        uint256, // deprecated
        uint256 _deadline
    ) external nonReentrant {
        require(block.timestamp <= _deadline, "Deadline passed");
        _mint(_collateral, _collateralAmt, _minUSDSAmt);
    }

    /// @notice redeem USDs for `_collateral`
    /// @param _collateral address of the collateral
    /// @param _usdsAmt Amount of USDs to be redeemed
    /// @param _minCollAmt minimum expected amount of collateral to be received
    /// @param _deadline expiry time of the transaction
    /// @dev In case where there is not sufficient collateral available in the vault,
    ///      the collateral is withdrawn from the default strategy configured for the collateral.
    function redeem(
        address _collateral,
        uint256 _usdsAmt,
        uint256 _minCollAmt,
        uint256 _deadline
    ) external nonReentrant {
        require(block.timestamp <= _deadline, "Deadline passed");
        _redeem(_collateral, _usdsAmt, _minCollAmt, address(0));
    }

    /// @notice redeem USDs for `_collateral`
    /// @param _collateral address of the collateral
    /// @param _usdsAmt Amount of USDs to be redeemed
    /// @param _minCollAmt minimum expected amount of collateral to be received
    /// @param _deadline expiry time of the transaction
    /// @param _strategy address of the strategy to withdraw excess collateral from
    function redeem(
        address _collateral,
        uint256 _usdsAmt,
        uint256 _minCollAmt,
        uint256 _deadline,
        address _strategy
    ) external nonReentrant {
        require(block.timestamp <= _deadline, "Deadline passed");
        _redeem(_collateral, _usdsAmt, _minCollAmt, _strategy);
    }

    /// @notice Get the expected redeem result
    /// @param _collateral desired collateral address
    /// @param _usdsAmt amount of usds to be redeemed
    /// @return calculatedCollateralAmt expected amount of collateral to be released
    ///                          based on the price calculation
    /// @return usdsBurnAmt expected amount of USDs to be burnt in the process
    /// @return feeAmt amount of USDs collected as fee for redemption
    /// @return vaultAmt amount of Collateral released from Vault
    /// @return strategyAmt amount of Collateral to withdraw from strategy
    function redeemView(
        address _collateral,
        uint256 _usdsAmt
    )
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
        (
            calculatedCollateralAmt,
            usdsBurnAmt,
            feeAmt,
            vaultAmt,
            strategyAmt,

        ) = _redeemView(_collateral, _usdsAmt, address(0));
    }

    function redeemView(
        address _collateral,
        uint256 _usdsAmt,
        address _strategyAddr
    )
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
        (
            calculatedCollateralAmt,
            usdsBurnAmt,
            feeAmt,
            vaultAmt,
            strategyAmt,

        ) = _redeemView(_collateral, _usdsAmt, _strategyAddr);
    }

    /// @notice Rebase USDs to share earned yield with the USDs holders
    function rebase() public {
        uint256 rebaseAmt = IRebaseManager(rebaseManager).fetchRebaseAmt();
        if (rebaseAmt > 0) {
            IUSDs(USDS).rebase(rebaseAmt);
            emit RebasedUSDs(rebaseAmt);
        }
    }

    /// @notice Get the expected mint result (USDs amt, fee)
    /// @param _collateral address of the collateral
    /// @param _collateralAmt amount of collateral
    /// @return Returns the expected USDs mint amount and fee for minting
    function mintView(
        address _collateral,
        uint256 _collateralAmt
    ) public view returns (uint256, uint256) {
        // Get mint configuration
        ICollateralManager.CollateralMintData
            memory collateralMintData = ICollateralManager(collateralManager)
                .getMintParams(_collateral);

        // Fetch the latest price of the collateral
        IOracle.PriceData memory collateralPriceData = IOracle(oracle).getPrice(
            _collateral
        );

        // Downside peg check
        if (
            collateralPriceData.price < collateralMintData.downsidePeg ||
            !collateralMintData.mintAllowed
        ) {
            return (0, 0);
        }

        // Calculate mint fee based on collateral data
        (uint256 feePerc, uint256 feePercPrecision) = IFeeCalculator(
            feeCalculator
        ).getFeeIn(_collateral);

        // Normalize _collateralAmt to be of decimals 18
        uint256 normalizedCollateralAmt = _collateralAmt *
            collateralMintData.conversionFactor;

        // Calculate total USDs amount
        uint256 usdsAmt = normalizedCollateralAmt;
        if (collateralPriceData.price < collateralPriceData.precision) {
            usdsAmt =
                (normalizedCollateralAmt * collateralPriceData.price) /
                collateralPriceData.precision;
        }

        // Calculate the fee amount
        uint256 feeAmt = (usdsAmt * feePerc) / feePercPrecision;
        uint256 toMinterAmt = usdsAmt - feeAmt;

        return (toMinterAmt, feeAmt);
    }

    /// @notice Get the expected redeem result
    /// @param _collateral desired collateral address
    /// @param _usdsAmt amount of usds to be redeemed
    /// @param _strategyAddr address of the strategy to redeem from
    /// @return calculatedCollateralAmt expected amount of collateral to be released
    ///                          based on the price calculation
    /// @return usdsBurnAmt expected amount of USDs to be burnt in the process
    /// @return feeAmt amount of USDs collected as fee for redemption
    /// @return vaultAmt amount of Collateral released from Vault
    /// @return strategyAmt amount of Collateral to withdraw from strategy
    /// @return strategy Strategy to withdraw collateral from
    function _redeemView(
        address _collateral,
        uint256 _usdsAmt,
        address _strategyAddr
    )
        public
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
        ICollateralManager.CollateralRedeemData
            memory collateralRedeemData = ICollateralManager(collateralManager)
                .getRedeemParams(_collateral);

        require(collateralRedeemData.redeemAllowed, "Redeem not allowed");

        IOracle.PriceData memory collateralPriceData = IOracle(oracle).getPrice(
            _collateral
        );
        (uint256 feePerc, uint256 feePercPrecision) = IFeeCalculator(
            feeCalculator
        ).getFeeOut(_collateral);

        feeAmt = (_usdsAmt * feePerc) / feePercPrecision;
        usdsBurnAmt = _usdsAmt - feeAmt;

        // Calculate collateral amount
        calculatedCollateralAmt = usdsBurnAmt;
        if (collateralPriceData.price >= collateralPriceData.precision) {
            // Apply downside peg
            calculatedCollateralAmt =
                (usdsBurnAmt * collateralPriceData.precision) /
                collateralPriceData.price;
        }

        // Normalize collateral amount to be of base decimal
        calculatedCollateralAmt =
            calculatedCollateralAmt /
            collateralRedeemData.conversionFactor;

        vaultAmt = IERC20Upgradeable(_collateral).balanceOf(address(this));

        if (calculatedCollateralAmt > vaultAmt) {
            strategyAmt = calculatedCollateralAmt - vaultAmt;
            // Withdraw from default strategy
            if (_strategyAddr == address(0)) {
                require(
                    collateralRedeemData.defaultStrategy != address(0),
                    "Insufficient collateral"
                );
                strategy = IStrategy(collateralRedeemData.defaultStrategy);
                // Withdraw from specified strategy
            } else {
                require(
                    ICollateralManager(collateralManager).isValidStrategy(
                        _collateral,
                        _strategyAddr
                    ),
                    "Invalid strategy"
                );
                strategy = IStrategy(_strategyAddr);
            }
            require(
                strategy.checkAvailableBalance(_collateral) >= strategyAmt,
                "Insufficient collateral"
            );
        }
    }

    /// @notice mint USDs
    /// @param _collateral address of collateral
    /// @param _collateralAmt amount of collateral to deposit
    /// @param _minUSDSAmt min expected USDs amount to be minted
    function _mint(
        address _collateral,
        uint256 _collateralAmt,
        uint256 _minUSDSAmt
    ) private {
        (uint256 toMinterAmt, uint256 feeAmt) = mintView(
            _collateral,
            _collateralAmt
        );
        require(toMinterAmt >= _minUSDSAmt, "Slippage screwed you");
        require(toMinterAmt > 0, "Mint failed");

        rebase();

        IERC20Upgradeable(_collateral).safeTransferFrom(
            msg.sender,
            address(this),
            _collateralAmt
        );
        IUSDs(USDS).mint(msg.sender, toMinterAmt);
        if (feeAmt > 0) {
            IUSDs(USDS).mint(feeVault, feeAmt);
        }

        emit Minted(
            msg.sender,
            _collateral,
            toMinterAmt,
            _collateralAmt,
            feeAmt
        );
    }

    /// @notice Redeem USDs
    /// @param _collateral address of collateral to receive
    /// @param _usdsAmt amount of USDs to redeem
    /// @param _minCollateralAmt min expected Collateral amount to be received
    /// @param _strategyAddr Address of the strategy to withdraw from
    /// @dev withdraw from strategy is triggered only if vault doesn't have enough funds
    function _redeem(
        address _collateral,
        uint256 _usdsAmt,
        uint256 _minCollateralAmt,
        address _strategyAddr
    ) private {
        (
            uint256 collateralAmt,
            uint256 burnAmt,
            uint256 feeAmt,
            uint256 vaultAmt,
            uint256 strategyAmt,
            IStrategy strategy
        ) = _redeemView(_collateral, _usdsAmt, _strategyAddr);

        if (strategyAmt > 0) {
            // Withdraw from the strategy to VaultCore
            uint256 strategyAmtRecvd = strategy.withdraw(
                address(this),
                _collateral,
                strategyAmt
            );
            // Update collateral amount according to the received amount from the strategy
            strategyAmt = strategyAmtRecvd < strategyAmt
                ? strategyAmtRecvd
                : strategyAmt;
            collateralAmt = vaultAmt + strategyAmt;
        }

        require(collateralAmt >= _minCollateralAmt, "Slippage screwed you");

        // Collect USDs for Redemption
        IERC20Upgradeable(USDS).safeTransferFrom(
            msg.sender,
            address(this),
            _usdsAmt
        );
        if (burnAmt > 0) {
            IUSDs(USDS).burn(burnAmt);
        }
        if (feeAmt > 0) {
            IERC20Upgradeable(USDS).safeTransfer(feeVault, feeAmt);
        }
        // Transfer desired collateral to the user
        IERC20Upgradeable(_collateral).safeTransfer(msg.sender, collateralAmt);
        rebase();
        emit Redeemed(msg.sender, _collateral, burnAmt, collateralAmt, feeAmt);
    }

    function _isNonZeroAddr(address _addr) private pure {
        require(_addr != address(0), "Zero address");
    }
}
