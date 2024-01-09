// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IVault} from "../interfaces/IVault.sol";
import {IOracle} from "../interfaces/IOracle.sol";
import {Helpers} from "../libraries/Helpers.sol";
import {IDripper} from "../interfaces/IDripper.sol";

/// @title YieldReserve of USDs Protocol.
/// @author Sperax Foundation
/// @notice This contract allows users to swap supported stable-coins for yield earned by the USDs protocol.
/// It sends USDs to the Dripper contract for rebase and to the Buyback Contract for buyback.
contract YieldReserve is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    struct TokenData {
        bool srcAllowed;
        bool dstAllowed;
        uint160 conversionFactor;
    }

    // Addresses of key contracts
    address public vault; // Address of the Vault contract
    address public oracle; // Address of the Oracle contract
    address public buyback; // Address of the Buyback contract
    address public dripper; // Address of the Dripper contract

    // Percentage of USDs to be sent to Buyback (e.g., 5000 for 50%)
    uint256 public buybackPercentage;

    mapping(address => TokenData) public tokenData;

    // Events
    event Swapped(
        address indexed srcToken,
        address indexed dstToken,
        address indexed dstReceiver,
        uint256 amountIn,
        uint256 amountOut
    );
    event USDsMintedViaSwapper(address indexed collateralAddr, uint256 usdsMinted);
    event Withdrawn(address indexed token, address indexed receiver, uint256 amount);
    event BuybackPercentageUpdated(uint256 toBuyback);
    event BuybackUpdated(address newBuyback);
    event OracleUpdated(address newOracle);
    event VaultUpdated(address newVault);
    event DripperUpdated(address newDripper);
    event USDsSent(uint256 toBuyback, uint256 toVault);
    event SrcTokenPermissionUpdated(address indexed token, bool isAllowed);
    event DstTokenPermissionUpdated(address indexed token, bool isAllowed);

    // Custom error messages
    error InvalidSourceToken();
    error InvalidDestinationToken();
    error AlreadyInDesiredState();
    error TokenPriceFeedMissing();

    /// @notice Constructor of the YieldReserve contract.
    /// @param _buyback Address of the Buyback contract.
    /// @param _vault Address of the Vault.
    /// @param _oracle Address of the Oracle.
    /// @param _dripper Address of the Dripper contract.
    constructor(address _buyback, address _vault, address _oracle, address _dripper) {
        updateBuyback(_buyback);
        updateVault(_vault);
        updateOracle(_oracle);
        updateDripper(_dripper);

        // Initialize buybackPercentage to 50%
        updateBuybackPercentage(5000);
    }

    // OPERATION FUNCTIONS

    /// @notice Swap function to be called by frontend users.
    /// @param _srcToken Source/Input token.
    /// @param _dstToken Destination/Output token.
    /// @param _amountIn Input token amount.
    /// @param _minAmountOut Minimum output tokens expected.
    function swap(address _srcToken, address _dstToken, uint256 _amountIn, uint256 _minAmountOut) external {
        return swap({
            _srcToken: _srcToken,
            _dstToken: _dstToken,
            _amountIn: _amountIn,
            _minAmountOut: _minAmountOut,
            _receiver: msg.sender
        });
    }

    // ADMIN FUNCTIONS

    /// @notice Allow or disallow a specific `token` for use as a source/input token.
    /// @param _token Address of the token to be allowed or disallowed.
    /// @param _isAllowed If set to `true`, the token will be allowed as a source/input token; otherwise, it will be disallowed.
    function toggleSrcTokenPermission(address _token, bool _isAllowed) external onlyOwner {
        TokenData storage data = tokenData[_token];
        if (data.srcAllowed == _isAllowed) revert AlreadyInDesiredState();
        if (_isAllowed) {
            if (!IOracle(oracle).priceFeedExists(_token)) {
                revert TokenPriceFeedMissing();
            }
            if (data.conversionFactor == 0) {
                data.conversionFactor = uint160(10 ** (18 - ERC20(_token).decimals()));
            }
        }
        data.srcAllowed = _isAllowed;
        emit SrcTokenPermissionUpdated(_token, _isAllowed);
    }

    /// @notice Allow or disallow a specific `token` for use as a destination/output token.
    /// @dev Reverts if caller is not owner.
    /// @param _token Address of the token to be allowed or disallowed.
    /// @param _isAllowed If set to `true`, the token will be allowed as a destination/output token; otherwise, it will be disallowed.
    function toggleDstTokenPermission(address _token, bool _isAllowed) external onlyOwner {
        TokenData storage data = tokenData[_token];
        if (data.dstAllowed == _isAllowed) revert AlreadyInDesiredState();
        if (_isAllowed) {
            if (!IOracle(oracle).priceFeedExists(_token)) {
                revert TokenPriceFeedMissing();
            }
            if (data.conversionFactor == 0) {
                data.conversionFactor = uint160(10 ** (18 - ERC20(_token).decimals()));
            }
        }
        data.dstAllowed = _isAllowed;
        emit DstTokenPermissionUpdated(_token, _isAllowed);
    }

    /// @notice Emergency withdrawal function for unexpected situations.
    /// @param _token Address of the asset to be withdrawn.
    /// @param _receiver Address of the receiver of tokens.
    /// @param _amount Amount of tokens to be withdrawn.
    function withdraw(address _token, address _receiver, uint256 _amount) external onlyOwner {
        Helpers._isNonZeroAmt(_amount);
        IERC20(_token).safeTransfer(_receiver, _amount);
        emit Withdrawn(_token, _receiver, _amount);
    }

    /// @notice Set the percentage of newly minted USDs to be sent to the Buyback contract.
    /// @dev Reverts if caller is not owner.
    /// @param _toBuyback The percentage of USDs sent to Buyback (e.g., 3000 for 30%).
    /// @dev The remaining USDs are sent to VaultCore for rebase.
    function updateBuybackPercentage(uint256 _toBuyback) public onlyOwner {
        Helpers._isNonZeroAmt(_toBuyback);
        Helpers._isLTEMaxPercentage(_toBuyback);
        buybackPercentage = _toBuyback;
        emit BuybackPercentageUpdated(_toBuyback);
    }

    /// @notice Update the address of the Buyback contract.
    /// @dev Reverts if caller is not owner.
    /// @param _newBuyBack New address of the Buyback contract.
    function updateBuyback(address _newBuyBack) public onlyOwner {
        Helpers._isNonZeroAddr(_newBuyBack);
        buyback = _newBuyBack;
        emit BuybackUpdated(_newBuyBack);
    }

    /// @notice Update the address of the Oracle contract.
    /// @dev Reverts if caller is not owner.
    /// @param _newOracle New address of the Oracle contract.
    function updateOracle(address _newOracle) public onlyOwner {
        Helpers._isNonZeroAddr(_newOracle);
        oracle = _newOracle;
        emit OracleUpdated(_newOracle);
    }

    /// @notice Update the address of the Dripper contract.
    /// @dev Reverts if caller is not owner.
    /// @param _newDripper New address of the Dripper contract.
    function updateDripper(address _newDripper) public onlyOwner {
        Helpers._isNonZeroAddr(_newDripper);
        dripper = _newDripper;
        emit DripperUpdated(_newDripper);
    }

    /// @notice Update the address of the VaultCore contract.
    /// @dev Reverts if caller is not owner.
    /// @param _newVault New address of the VaultCore contract.
    function updateVault(address _newVault) public onlyOwner {
        Helpers._isNonZeroAddr(_newVault);
        vault = _newVault;
        emit VaultUpdated(_newVault);
    }

    /// @notice Swap allowed source token for allowed destination token.
    /// @dev Reverts if caller is not owner.
    /// @param _srcToken Source/Input token.
    /// @param _dstToken Destination/Output token.
    /// @param _amountIn Input token amount.
    /// @param _minAmountOut Minimum output tokens expected.
    /// @param _receiver Receiver of the tokens.
    function swap(address _srcToken, address _dstToken, uint256 _amountIn, uint256 _minAmountOut, address _receiver)
        public
        nonReentrant
    {
        Helpers._isNonZeroAddr(_receiver);
        uint256 amountToSend = getTokenBForTokenA(_srcToken, _dstToken, _amountIn);
        if (amountToSend < _minAmountOut) {
            revert Helpers.MinSlippageError(amountToSend, _minAmountOut);
        }
        IERC20(_srcToken).safeTransferFrom(msg.sender, address(this), _amountIn);
        if (_srcToken != Helpers.USDS) {
            // Mint USDs
            IERC20(_srcToken).forceApprove(vault, _amountIn);
            IVault(vault).mint(_srcToken, _amountIn, 0, block.timestamp);
            // No need to do a slippage check as it is our contract, and the vault does that.
        }
        IERC20(_dstToken).safeTransfer(_receiver, amountToSend);
        _sendUSDs();
        emit Swapped({
            srcToken: _srcToken,
            dstToken: _dstToken,
            dstReceiver: _receiver,
            amountIn: _amountIn,
            amountOut: amountToSend
        });
    }

    /// @notice Get an estimate of the output token amount for a given input token amount.
    /// @dev Reverts if caller is not owner.
    /// @param _srcToken Input token address.
    /// @param _dstToken Output token address.
    /// @param _amountIn Input amount of _srcToken.
    /// @return Estimated output token amount.
    function getTokenBForTokenA(address _srcToken, address _dstToken, uint256 _amountIn)
        public
        view
        returns (uint256)
    {
        TokenData storage srcTokenData = tokenData[_srcToken];
        TokenData storage dstTokenData = tokenData[_dstToken];
        if (!srcTokenData.srcAllowed) revert InvalidSourceToken();
        if (!dstTokenData.dstAllowed) revert InvalidDestinationToken();
        Helpers._isNonZeroAmt(_amountIn);
        // Getting prices from Oracle
        IOracle.PriceData memory tokenAPriceData = IOracle(oracle).getPrice(_srcToken);
        IOracle.PriceData memory tokenBPriceData = IOracle(oracle).getPrice(_dstToken);
        // Calculating the value
        return (
            (_amountIn * srcTokenData.conversionFactor * tokenAPriceData.price * tokenBPriceData.precision)
                / (tokenBPriceData.price * tokenAPriceData.precision * dstTokenData.conversionFactor)
        );
    }

    // UTILITY FUNCTIONS

    /// @notice Distributes USDs to the Buyback and Dripper contracts based on buybackPercentage.
    /// @dev Sends a portion of the USDs balance to the Buyback contract and the remaining to the Dripper contract for rebase.
    function _sendUSDs() private {
        uint256 balance = IERC20(Helpers.USDS).balanceOf(address(this));

        // Calculate the amount to send to Buyback based on buybackPercentage
        uint256 toBuyback = (balance * buybackPercentage) / Helpers.MAX_PERCENTAGE;

        // The remaining balance is sent to the Dripper for rebase
        uint256 toDripper = balance - toBuyback;

        emit USDsSent(toBuyback, toDripper);
        IERC20(Helpers.USDS).safeTransfer(buyback, toBuyback);
        if (toDripper != 0) {
            IERC20(Helpers.USDS).forceApprove(dripper, toDripper);
            IDripper(dripper).addUSDs(toDripper);
        }
    }
}
