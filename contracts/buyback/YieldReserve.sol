// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IVault} from "../interfaces/IVault.sol";
import {IOracle} from "../interfaces/IOracle.sol";
import {Helpers} from "../libraries/Helpers.sol";

/// @title YieldReserve of USDs protocol
/// @notice The contract allows users to swap the supported stable coins against yield earned by USDs protocol
///         It sends USDs to dripper for rebase, and to Buyback Contract for buyback.
/// @author Sperax Foundation
contract YieldReserve is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    address public vault;
    address public oracle;
    address public buyback;
    address public dripper;
    // Percentage of USDs to be sent to Buyback 500 means 50%
    uint256 public buybackPercentage;

    mapping(address => bool) public isAllowedSrc;
    mapping(address => bool) public isAllowedDst;

    event Swapped(
        address indexed srcToken,
        address indexed dstToken,
        address indexed dstReceiver,
        uint256 amountIn,
        uint256 amountOut
    );
    event USDsMintedViaSwapper(
        address indexed collateralAddr,
        uint256 usdsMinted
    );
    event Withdrawn(
        address indexed token,
        address indexed receiver,
        uint256 amount
    );
    event BuybackPercentageUpdated(uint256 toBuyback);
    event BuybackAddressUpdated(address newBuyback);
    event OracleUpdated(address newOracle);
    event VaultAddressUpdated(address newVault);
    event DripperAddressUpdated(address newDripper);
    event USDsSent(uint256 toBuyback, uint256 toVault);
    event SrcTokenPermissionUpdated(address indexed token, bool isAllowed);
    event DstTokenPermissionUpdated(address indexed token, bool isAllowed);

    error InvalidSourceToken();
    error InvalidDestinationToken();
    error AlreadyInDesiredState();

    /// @notice Constructor of the contract
    /// @param _buyback Address of Buyback contract
    /// @param _vault Address of Vault
    /// @param _oracle Address of Oracle
    /// @param _dripper Address of the dripper contract
    constructor(
        address _buyback,
        address _vault,
        address _oracle,
        address _dripper
    ) {
        updateBuybackAddress(_buyback);
        updateVaultAddress(_vault);
        updateOracleAddress(_oracle);
        updateDripperAddress(_dripper);

        /// @dev buybackPercentage is initialized to 50%
        updateBuybackPercentage(uint256(5000));
    }

    // OPERATION FUNCTIONS

    /// @notice Swap function to be called by front end
    /// @param _srcToken Source / Input token
    /// @param _dstToken Destination / Output token
    /// @param _amountIn Input token amount
    /// @param _minAmountOut Minimum output tokens expected
    function swap(
        address _srcToken,
        address _dstToken,
        uint256 _amountIn,
        uint256 _minAmountOut
    ) external {
        return
            swap({
                _srcToken: _srcToken,
                _dstToken: _dstToken,
                _amountIn: _amountIn,
                _minAmountOut: _minAmountOut,
                _receiver: msg.sender
            });
    }

    // ADMIN FUNCTIONS

    /// @notice A function to allow or disallow a `_token`
    /// @param _token Address of the token
    /// @param _isAllowed If True, allow it to be used as src token / input token else don't allow
    function toggleSrcTokenPermission(
        address _token,
        bool _isAllowed
    ) external onlyOwner {
        if (isAllowedSrc[_token] == _isAllowed) revert AlreadyInDesiredState();
        if (_isAllowed) {
            // Ensure that there is a valid price feed for the _token
            //@audit-info same as previous remark
            IOracle(oracle).getPrice(_token);
        }
        isAllowedSrc[_token] = _isAllowed;
        emit SrcTokenPermissionUpdated(_token, _isAllowed);
    }

    /// @notice A function to allow or disallow a `_token`
    /// @param _token Address of the token
    /// @param _isAllowed If True, allow it to be used as src token / input token else don't allow
    function toggleDstTokenPermission(
        address _token,
        bool _isAllowed
    ) external onlyOwner {
        if (isAllowedDst[_token] == _isAllowed) revert AlreadyInDesiredState();
        if (_isAllowed) {
            // Ensure that there is a valid price feed for the _token
            //@audit-info how can we check that there is a price?
            // since we ignore return value by IOracle(oracle).getPrice(_token)
            IOracle(oracle).getPrice(_token);
        }
        isAllowedDst[_token] = _isAllowed;
        emit DstTokenPermissionUpdated(_token, _isAllowed);
    }

    /// @notice Emergency withdrawal function for unexpected situations
    /// @param _token Address of the asset to be withdrawn
    /// @param _receiver Address of the receiver of tokens
    /// @param _amount Amount of tokens to be withdrawn
    function withdraw(
        address _token,
        address _receiver,
        uint256 _amount
    ) external onlyOwner {
        Helpers._isNonZeroAmt(_amount);
        IERC20(_token).safeTransfer(_receiver, _amount);
        emit Withdrawn(_token, _receiver, _amount);
    }

    /// @notice Set the % of minted USDs sent Buyback
    /// @param _toBuyback % of USDs sent to Buyback
    /// @dev The rest of the USDs is sent to VaultCore
    /// @dev E.g. _toBuyback == 3000 means 30% of the newly
    ///        minted USDs would be sent to Buyback; the rest 70% to VaultCore
    function updateBuybackPercentage(uint256 _toBuyback) public onlyOwner {
        Helpers._isNonZeroAmt(_toBuyback);
        Helpers._isLTEMaxPercentage(_toBuyback);
        buybackPercentage = _toBuyback;
        emit BuybackPercentageUpdated(_toBuyback);
    }

    /// @notice Update Buyback contract's address
    /// @param _newBuyBack New address of Buyback contract
    function updateBuybackAddress(address _newBuyBack) public onlyOwner {
        Helpers._isNonZeroAddr(_newBuyBack);
        buyback = _newBuyBack;
        emit BuybackAddressUpdated(_newBuyBack);
    }

    /// @notice Update Oracle's address
    /// @param _newOracle New address of Oracle
    function updateOracleAddress(address _newOracle) public onlyOwner {
        Helpers._isNonZeroAddr(_newOracle);
        oracle = _newOracle;
        emit OracleUpdated(_newOracle);
    }

    /// @notice Update Dripper's address
    /// @param _newDripper New address of Dripper
    function updateDripperAddress(address _newDripper) public onlyOwner {
        Helpers._isNonZeroAddr(_newDripper);
        dripper = _newDripper;
        emit DripperAddressUpdated(_newDripper);
    }

    /// @notice Update VaultCore's address
    /// @param _newVault New address of VaultCore
    function updateVaultAddress(address _newVault) public onlyOwner {
        Helpers._isNonZeroAddr(_newVault);
        vault = _newVault;
        emit VaultAddressUpdated(_newVault);
    }

    /// @notice Swap allowed src token to allowed dst token.
    /// @param _srcToken Source / Input token
    /// @param _dstToken Destination / Output token
    /// @param _amountIn Input token amount
    /// @param _minAmountOut Minimum output tokens expected
    /// @param _receiver Receiver of the tokens
    function swap(
        address _srcToken,
        address _dstToken,
        uint256 _amountIn,
        uint256 _minAmountOut,
        address _receiver
    ) public nonReentrant {
        Helpers._isNonZeroAddr(_receiver);
        uint256 amountToSend = getTokenBForTokenA(
            _srcToken,
            _dstToken,
            _amountIn
        );
        if (amountToSend < _minAmountOut)
            revert Helpers.MinSlippageError(amountToSend, _minAmountOut);
        IERC20(_srcToken).safeTransferFrom(
            msg.sender,
            address(this),
            _amountIn
        );
        if (_srcToken != Helpers.USDS) {
            // Mint USDs
            IERC20(_srcToken).safeApprove(vault, _amountIn);
            (uint256 _minUSDSAmt, ) = IVault(vault).mintView(
                _srcToken,
                _amountIn
            );
            IVault(vault).mint(
                _srcToken,
                _amountIn,
                _minUSDSAmt,
                block.timestamp + 1200
            );
            // No need to do slippage check as it is our contract
            // and the vault does that.
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

    /// @notice A `view` function to get estimated output
    /// @param _srcToken Input token address
    /// @param _dstToken Output token address
    /// @param _amountIn Input amount of _srcToken
    function getTokenBForTokenA(
        address _srcToken,
        address _dstToken,
        uint256 _amountIn
    ) public view returns (uint256) {
        if (!isAllowedSrc[_srcToken]) revert InvalidSourceToken();
        if (!isAllowedDst[_dstToken]) revert InvalidDestinationToken();
        Helpers._isNonZeroAmt(_amountIn);
        // Getting prices from Oracle
        IOracle.PriceData memory tokenAPriceData = IOracle(oracle).getPrice(
            _srcToken
        );
        IOracle.PriceData memory tokenBPriceData = IOracle(oracle).getPrice(
            _dstToken
        );
        // Calculating the value
        uint256 totalUSDValueIn = (_amountIn * tokenAPriceData.price) /
            tokenAPriceData.precision;
        uint256 tokenBOut = (totalUSDValueIn * tokenBPriceData.precision) /
            tokenBPriceData.price;
        return tokenBOut;
    }

    // UTILITY FUNCTIONS

    /// @notice Sends USDs to buyback as per buybackPercentage
    ///         and rest to VaultCore for rebase
    function _sendUSDs() private {
        uint256 balance = IERC20(Helpers.USDS).balanceOf(address(this));

        // Calculating the amount to send to Buyback based on buybackPercentage
        uint256 toBuyback = (balance * buybackPercentage) /
            Helpers.MAX_PERCENTAGE;

        // Remaining balance will be sent to Dripper for rebase
        uint256 toDripper = balance - toBuyback;

        emit USDsSent(toBuyback, toDripper);
        IERC20(Helpers.USDS).safeTransfer(buyback, toBuyback);
        IERC20(Helpers.USDS).safeTransfer(dripper, toDripper);
    }
}
