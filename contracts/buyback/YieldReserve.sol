// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IVault} from "../interfaces/IVault.sol";
import {IOracle} from "../interfaces/IOracle.sol";

/// @title YieldReserve of USDs protocol
/// @notice The contract allows user's to swap the supported stablecoins against yield earned by USDs protocol
///         It sends USDs to dripper for rebase, and to Buyback Contract for buyback.
/// @author Sperax Foundation
contract YieldReserve is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    address public constant USDS = 0xD74f5255D557944cf7Dd0E45FF521520002D5748;
    uint256 private constant MAX_PERCENTAGE = 10000; // 100%
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
    event DripperAddressUpdated(address newdripper);
    event USDsSent(uint256 toBuyback, uint256 toVault);
    event SrcTokenPermissionUpdated(address indexed token, bool isAllowed);
    event DstTokenPermissionUpdated(address indexed token, bool isAllowed);

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

        //@dev buybackPercentage is initialized to 50%
        updateBuybackPercentage(uint256(5000));
    }

    // OPERATION FUNCTIONS

    /// @notice Swap function to be called by front end
    function swap(
        address srcToken,
        address dstToken,
        uint256 amountIn,
        uint256 minAmountOut
    ) external {
        return swap(srcToken, dstToken, amountIn, minAmountOut, msg.sender);
    }

    // ADMIN FUNCTIONS

    /// @notice A function to allow or disallow a `_token`
    /// @param _token Address of the token
    /// @param _isAllowed If True, allow it to be used as src token / input token else don't allow
    function toggleSrcTokenPermission(
        address _token,
        bool _isAllowed
    ) external onlyOwner {
        require(isAllowedSrc[_token] != _isAllowed, "Already in desired state");
        if (_isAllowed) {
            // Ensure that there is a valid price feed for the _token
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
        require(isAllowedDst[_token] != _isAllowed, "Already in desired state");
        if (_isAllowed) {
            // Ensure that there is a valid price feed for the _token
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
        _isValidAddress(_token);
        _isValidAddress(_receiver);
        _isValidAmount(_amount);
        emit Withdrawn(_token, _receiver, _amount);
        IERC20(_token).safeTransfer(_receiver, _amount);
    }

    /// @notice Set the % of minted USDs sent Buyback
    /// @param _toBuyback % of USDs sent to Buyback
    /// @dev The rest of the USDs is sent to VaultCore
    /// @dev E.g. _toBuyback == 3000 means 30% of the newly
    ///        minted USDs would be sent to Buyback; the rest 70% to VaultCore
    function updateBuybackPercentage(uint256 _toBuyback) public onlyOwner {
        require(_toBuyback <= MAX_PERCENTAGE, "% exceeds 100%");
        require(_toBuyback > 0, "% must be > 0");
        buybackPercentage = _toBuyback;
        emit BuybackPercentageUpdated(buybackPercentage);
    }

    /// @notice Update Buyback contract's address
    /// @param _newBuyBack New address of Buyback contract
    function updateBuybackAddress(address _newBuyBack) public onlyOwner {
        _isValidAddress(_newBuyBack);
        buyback = _newBuyBack;
        emit BuybackAddressUpdated(buyback);
    }

    /// @notice Update Oracle's address
    /// @param _newOracle New address of Oracle
    function updateOracleAddress(address _newOracle) public onlyOwner {
        _isValidAddress(_newOracle);
        oracle = _newOracle;
        emit OracleUpdated(_newOracle);
    }

    /// @notice Update Dripper's address
    /// @param _newDripper New address of Dripper
    function updateDripperAddress(address _newDripper) public onlyOwner {
        _isValidAddress(_newDripper);
        dripper = _newDripper;
        emit DripperAddressUpdated(_newDripper);
    }

    /// @notice Update VaultCore's address
    /// @param _newVault New address of VaultCore
    function updateVaultAddress(address _newVault) public onlyOwner {
        _isValidAddress(_newVault);
        vault = _newVault;
        emit VaultAddressUpdated(_newVault);
    }

    /// @notice Swap allowed src token to allowed dst token.
    /// @param srcToken Source / Input token
    /// @param dstToken Destination / Output token
    /// @param amountIn Input token amount
    /// @param minAmountOut Minimum output tokens expected
    /// @param receiver Receiver of the tokens
    function swap(
        address srcToken,
        address dstToken,
        uint256 amountIn,
        uint256 minAmountOut,
        address receiver
    ) public nonReentrant {
        _isValidAddress(receiver);
        uint256 amountToSend = getTokenBforTokenA(srcToken, amountIn, dstToken);
        require(amountToSend >= minAmountOut, "Slippage more than expected");
        IERC20(srcToken).safeTransferFrom(msg.sender, address(this), amountIn);
        if (srcToken != USDS) {
            // Mint USDs
            IERC20(srcToken).safeApprove(vault, amountIn);
            (uint256 _minUSDSAmt, ) = IVault(vault).mintView(
                srcToken,
                amountIn
            );
            IVault(vault).mint(
                srcToken,
                amountIn,
                _minUSDSAmt,
                block.timestamp + 1200
            );
            // No need to do slippage check as it is our contract
            // and the vault does that.
        }
        IERC20(dstToken).safeTransfer(receiver, amountToSend);
        _sendUSDs();
        emit Swapped(srcToken, dstToken, receiver, amountIn, amountToSend);
    }

    /// @notice A function to get estimated output
    /// @param _tokenA Input token address
    /// @param _amountIn Input amount of _tokenA
    /// @param _tokenB Output token address
    function getTokenBforTokenA(
        address _tokenA,
        uint256 _amountIn,
        address _tokenB
    ) public view returns (uint256) {
        require(isAllowedSrc[_tokenA], "Source token is not allowed");
        require(isAllowedDst[_tokenB], "Destination token is not allowed");
        _isValidAmount(_amountIn);
        // Getting prices from Oracle
        IOracle.PriceData memory tokenAPriceData = IOracle(oracle).getPrice(
            _tokenA
        );
        IOracle.PriceData memory tokenBPriceData = IOracle(oracle).getPrice(
            _tokenB
        );
        // Calculating the value
        uint256 totalUSDvalueIn = (_amountIn * tokenAPriceData.price) /
            tokenAPriceData.precision;
        uint256 tokenBOut = (totalUSDvalueIn * tokenBPriceData.precision) /
            tokenBPriceData.price;
        return tokenBOut;
    }

    // UTILITY FUNCTIONS

    /// @notice Sends USDs to buyback as per buybackPercentage
    ///         and rest to VaultCore for rebase
    function _sendUSDs() private {
        uint256 balance = IERC20(USDS).balanceOf(address(this));

        // Calculating the amount to send to Buyback based on buybackPercentage
        uint256 toBuyback = (balance * buybackPercentage) / MAX_PERCENTAGE;

        // Remaining balance will be sent to Dripper for rebase
        uint256 toDripper = balance - toBuyback;

        emit USDsSent(toBuyback, toDripper);
        if (toBuyback > 0) IERC20(USDS).safeTransfer(buyback, toBuyback);
        if (toDripper > 0) IERC20(USDS).safeTransfer(dripper, toDripper);
    }

    function _isValidAddress(address _address) private pure {
        require(_address != address(0), "Invalid address");
    }

    function _isValidAmount(uint256 _amount) private pure {
        require(_amount > 0, "Invalid amount");
    }
}
