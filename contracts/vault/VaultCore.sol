// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {AccessControlUpgradeable, Initializable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {SafeERC20Upgradeable, IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20MetadataUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import {IFeeCalculator} from "./interfaces/IFeeCalculator.sol";
import {IUSDs} from "./interfaces/IUSDs.sol";
import {IOracle} from "./interfaces/IOracle.sol";
import {ICollateralManager} from "./interfaces/ICollateralManager.sol";
import {IStrategy} from "../strategies/interfaces/IStrategy.sol";

contract VaultCore is
    Initializable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    bytes32 public constant REBASER_ROLE = keccak256("REBASER_ROLE");
    bytes32 public constant ALLOCATOR_ROLE = keccak256("ALLOCATOR_ROLE");
    bytes32 public constant HARVESTOR_ROLE = keccak256("HARVESTOR_ROLE");

    address public constant USDS = 0xD74f5255D557944cf7Dd0E45FF521520002D5748;

    address public feeVault;
    address public yieldReceiver;
    address public collateralManager;
    address public feeCalculator;
    address public oracle;

    event FeeVaultChanged(address newFeeManager);
    event YieldReceiverChanged(address newYieldReceiver);
    event CollateralManagerChanged(address newCollateralManagerChanged);
    event FeeCalculatorChanged(address newFeeCalculator);
    event OracleChanged(address newOracle);
    event Rebased(uint256 rebasedAmount);
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

    modifier onlyOwner() {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, _msgSender()),
            "Unauthorized caller"
        );
        _;
    }

    function updateFeeVault(address _feeVault) external onlyOwner {
        require(_feeVault != address(0), "Illegal input");
        feeVault = _feeVault;
        emit FeeVaultChanged(feeVault);
    }

    function updateYieldReceiver(address _yieldReceiver) external onlyOwner {
        require(_yieldReceiver != address(0), "Illegal input");
        yieldReceiver = _yieldReceiver;
        emit YieldReceiverChanged(yieldReceiver);
    }

    function updateCollateralManager(
        address _collateralManager
    ) external onlyOwner {
        require(_collateralManager != address(0), "Illegal input");
        collateralManager = _collateralManager;
        emit CollateralManagerChanged(collateralManager);
    }

    function updateFeeCalculator(address _feeCalculator) external onlyOwner {
        require(_feeCalculator != address(0), "Illegal input");
        feeCalculator = _feeCalculator;
        emit FeeCalculatorChanged(yieldReceiver);
    }

    function updateOracle(address _oracle) external onlyOwner {
        require(_oracle != address(0), "Illegal input");
        oracle = _oracle;
        emit OracleChanged(oracle);
    }

    function rebase(uint256 _amount) external nonReentrant {
        require(hasRole(REBASER_ROLE, _msgSender()), "Unauthorized caller");
        require(
            _amount <= IERC20Upgradeable(USDS).balanceOf(address(this)),
            "Insufficient USDs"
        );
        require(_amount > 0, "Invalid input");

        uint256 usdsOldSupply = IERC20Upgradeable(USDS).totalSupply();
        IUSDs(USDS).burnExclFromOutFlow(_amount);
        IUSDs(USDS).changeSupply(usdsOldSupply);

        emit Rebased(_amount);
    }

    function allocate(
        address _collateral,
        address _strategy,
        uint256 _amount
    ) external nonReentrant {
        require(hasRole(ALLOCATOR_ROLE, _msgSender()), "Unauthorized caller");
        require(
            ICollateralManager(collateralManager).validateAllocation(
                _collateral,
                _strategy,
                _amount
            ),
            "Allocation not allowed"
        );

        IStrategy(_strategy).deposit(_collateral, _amount);
    }

    function mint(
        address _collateral,
        uint256 _collateralAmt,
        uint256 _minUSDSAmt,
        uint256 _deadline
    ) external nonReentrant returns (uint256) {
        require(block.timestamp <= _deadline, "Deadline passed");
        uint256 mintedUSDSAmt = _mint(_collateral, _collateralAmt, _minUSDSAmt);
        return mintedUSDSAmt;
    }

    /// @dev This function is for backward compatibility
    function mintBySpecifyingCollateralAmt(
        address _collateral,
        uint256 _collateralAmt,
        uint256 _minUSDSAmt,
        // solhint-disable-next-line no-unused-vars
        uint256 _deprecated,
        uint256 _deadline
    ) external nonReentrant {
        require(block.timestamp <= _deadline, "Deadline passed");

        _mint(_collateral, _collateralAmt, _minUSDSAmt);
    }

    function redeem(
        address _collateral,
        uint256 _usdsAmt,
        uint256 _minCollAmt,
        uint256 _deadline
    ) external returns (uint256) {
        require(block.timestamp <= _deadline, "Deadline passed");

        uint256 redeemedCollateralAmt = _redeem(
            _collateral,
            _usdsAmt,
            _minCollAmt,
            address(0)
        );
        return redeemedCollateralAmt;
    }

    function redeem(
        address _collateral,
        uint256 _usdsAmt,
        uint256 _minCollAmt,
        uint256 _deadline,
        address _strategy
    ) external returns (uint256) {
        require(block.timestamp <= _deadline, "Deadline passed");

        uint256 redeemedCollateralAmt = _redeem(
            _collateral,
            _usdsAmt,
            _minCollAmt,
            _strategy
        );
        return redeemedCollateralAmt;
    }

    function mintView(
        address _collateral,
        uint256 _collateralAmt
    ) public view returns (uint256, uint256) {
        IOracle.PriceData memory collateralPriceData = IOracle(oracle).getPrice(
            _collateral
        );
        (uint256 feePerc, uint256 feePercPrecision) = IFeeCalculator(
            feeCalculator
        ).getFeeIn(_collateral);

        // Normalize _collateralAmt to be of decimals 18
        uint256 normalizedCollateralAmt = _collateralAmt *
            (10 ** (18 - IERC20MetadataUpgradeable(_collateral).decimals()));
        // Calculate total USDs amount
        uint256 usdsAmt;
        if (collateralPriceData.price > collateralPriceData.precision) {
            usdsAmt = normalizedCollateralAmt;
        } else {
            usdsAmt =
                (normalizedCollateralAmt * collateralPriceData.price) /
                collateralPriceData.precision;
        }
        uint256 feeAmt = (usdsAmt * feePerc) / feePercPrecision;
        uint256 toMinterAmt = usdsAmt - feeAmt;

        return (toMinterAmt, feeAmt);
    }

    function redeemView(
        address _collateral,
        uint256 _usdsAmt
    ) public view returns (uint256, uint256, uint256) {
        IOracle.PriceData memory collateralPriceData = IOracle(oracle).getPrice(
            _collateral
        );
        (uint256 feePerc, uint256 feePercPrecision) = IFeeCalculator(
            feeCalculator
        ).getFeeOut(_collateral);

        uint256 feeAmt = (_usdsAmt * feePerc) / feePercPrecision;
        uint256 burnAmt = _usdsAmt - feeAmt;

        // Calculate collateral amount
        uint256 collateralAmt;
        if (collateralPriceData.price < collateralPriceData.precision) {
            // Apply downside peg
            collateralAmt = burnAmt;
        } else {
            collateralAmt =
                (burnAmt * collateralPriceData.precision) /
                collateralPriceData.price;
        }
        // Normalize collateral amount to be of decimals 18
        uint8 collateralDecimals = IERC20MetadataUpgradeable(_collateral)
            .decimals();
        if (collateralDecimals != 18) {
            collateralAmt = collateralAmt / (10 ** (18 - collateralDecimals));
        }

        return (collateralAmt, burnAmt, feeAmt);
    }

    function _mint(
        address _collateral,
        uint256 _collateralAmt,
        uint256 _minUSDSAmt
    ) private returns (uint256) {
        ICollateralManager.CollateralMintData
            memory collateralMintData = ICollateralManager(collateralManager)
                .getMintParams(_collateral);
        require(collateralMintData.mintAllowed, "Mint not allowed");

        (uint256 toMinterAmt, uint256 feeAmt) = mintView(
            _collateral,
            _collateralAmt
        );
        require(toMinterAmt >= _minUSDSAmt, "Slippage screwed you");

        IERC20Upgradeable(_collateral).safeTransferFrom(
            msg.sender,
            address(this),
            _collateralAmt
        );
        if (toMinterAmt > 0) {
            IUSDs(USDS).mint(msg.sender, toMinterAmt);
        }
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
        return toMinterAmt;
    }

    function _redeem(
        address _collateral,
        uint256 _usdsAmt,
        uint256 _minCollateralAmt,
        address _strategyAddr
    ) private returns (uint256) {
        ICollateralManager.CollateralRedeemData
            memory collateralRedeemData = ICollateralManager(collateralManager)
                .getRedeemParams(_collateral);
        require(collateralRedeemData.redeemAllowed, "Redeem not allowed");

        (uint256 collateralAmt, uint256 burnAmt, uint256 feeAmt) = redeemView(
            _collateral,
            _usdsAmt
        );
        uint256 vaultAmt = IERC20Upgradeable(_collateral).balanceOf(
            address(this)
        );
        if (collateralAmt > vaultAmt) {
            uint256 strategyAmt = collateralAmt - vaultAmt;
            IStrategy strategy;
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
                ICollateralManager(collateralManager).isValidStrategy(
                    _collateral,
                    _strategyAddr
                );
                strategy = IStrategy(_strategyAddr);
            }
            require(
                strategy.checkAvailableBalance(_collateral) >= strategyAmt,
                "Insufficient collateral"
            );
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

        if (collateralAmt > 0) {
            IERC20Upgradeable(_collateral).safeTransferFrom(
                address(this),
                msg.sender,
                collateralAmt
            );
        }
        if (burnAmt > 0) {
            IERC20Upgradeable(USDS).safeTransferFrom(
                address(this),
                msg.sender,
                burnAmt
            );
            IUSDs(USDS).burn(burnAmt);
        }
        if (feeAmt > 0) {
            IERC20Upgradeable(USDS).safeTransferFrom(
                msg.sender,
                feeVault,
                feeAmt
            );
        }

        emit Redeemed(msg.sender, _collateral, burnAmt, collateralAmt, feeAmt);
        return collateralAmt;
    }
}
