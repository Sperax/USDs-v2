// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/// @title A standard library for errors and constant values
/// @author Sperax Foundation
library Helpers {
    // Constants
    uint16 internal constant MAX_PERCENTAGE = 10000;
    address internal constant SPA = 0x2b6bD6c795554600F50a306166D13b2dc4201564;
    address internal constant USDS = 0x7160654d6a254d28EaDa2E5A107ED46081DDB222;

    // Errors
    error CustomError(string message);
    error InvalidAddress();
    error GTMaxPercentage(uint256 actual);
    error InvalidAmount();
    error MinSlippageError(uint256 actualAmt, uint256 minExpectedAmt);
    error MaxSlippageError(uint256 actualAmt, uint256 maxExpectedAmt);

    /// @notice Checks the expiry of a transaction's deadline
    /// @param _deadline Deadline specified by the sender of the transaction
    /// @dev Reverts if the current block's timestamp is greater than `_deadline`
    function _checkDeadline(uint256 _deadline) internal view {
        if (block.timestamp > _deadline) revert CustomError("Deadline passed");
    }

    /// @notice Checks for a non-zero address
    /// @param _addr Address to be validated
    /// @dev Reverts if `_addr` is equal to `address(0)`
    function _isNonZeroAddr(address _addr) internal pure {
        if (_addr == address(0)) revert InvalidAddress();
    }

    /// @notice Checks for a non-zero amount
    /// @param _amount Amount to be validated
    /// @dev Reverts if `_amount` is equal to `0`
    function _isNonZeroAmt(uint256 _amount) internal pure {
        if (_amount == 0) revert InvalidAmount();
    }

    /// @notice Checks for a non-zero amount with a custom error message
    /// @param _amount Amount to be validated
    /// @param _err Custom error message
    /// @dev Reverts if `_amount` is equal to `0` with the provided custom error message
    function _isNonZeroAmt(uint256 _amount, string memory _err) internal pure {
        if (_amount == 0) revert CustomError(_err);
    }

    /// @notice Checks whether the `_percentage` is less than or equal to `MAX_PERCENTAGE`
    /// @param _percentage The percentage to be checked
    /// @dev Reverts if `_percentage` is greater than `MAX_PERCENTAGE`
    function _isLTEMaxPercentage(uint256 _percentage) internal pure {
        if (_percentage > MAX_PERCENTAGE) revert GTMaxPercentage(_percentage);
    }

    /// @notice Checks whether the `_percentage` is less than or equal to `MAX_PERCENTAGE` with a custom error message
    /// @param _percentage The percentage to be checked
    /// @param _err Custom error message
    /// @dev Reverts with the provided custom error message if `_percentage` is greater than `MAX_PERCENTAGE`
    function _isLTEMaxPercentage(uint256 _percentage, string memory _err) internal pure {
        if (_percentage > MAX_PERCENTAGE) revert CustomError(_err);
    }
}
