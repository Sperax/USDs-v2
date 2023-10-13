// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

/// @title A standard library for errors and constant values
/// @author Sperax Foundation
library Helpers {
    uint16 internal constant MAX_PERCENTAGE = 10000;
    address internal constant SPA = 0x5575552988A3A80504bBaeB1311674fCFd40aD4B;
    address internal constant USDS = 0xD74f5255D557944cf7Dd0E45FF521520002D5748;

    error CustomError(string message);
    error InvalidAddress();
    error GTMaxPercentage(uint256 actual);
    error InvalidAmount();
    error MinSlippageError(uint256 actualAmt, uint256 minExpectedAmt);
    error MaxSlippageError(uint256 actualAmt, uint256 maxExpectedAmt);

    /// @notice A function to check the expiry of transaction's deadline
    /// @param _deadline Deadline specified by the sender of the transaction
    /// @dev Reverts if `block.timestamp` > `_deadline`
    function _checkDeadline(uint256 _deadline) internal view {
        if (block.timestamp > _deadline) revert CustomError("Deadline passed");
    }

    /// @notice Check for non-zero address
    /// @param _addr Address to be validated
    /// @dev Reverts if `_addr` == `address(0)`
    function _isNonZeroAddr(address _addr) internal pure {
        if (_addr == address(0)) revert InvalidAddress();
    }

    /// @notice Check for non-zero mount
    /// @param _amount Amount to be validated
    /// @dev Reverts if `_amount` == `0`
    function _isNonZeroAmt(uint256 _amount) internal pure {
        if (_amount == 0) revert InvalidAmount();
    }

    /// @notice Check for non-zero mount
    /// @param _amount Amount to be validated
    /// @param _err Custom error messages
    /// @dev Reverts if `_amount` == `0` with a CustomError string
    function _isNonZeroAmt(uint256 _amount, string memory _err) internal pure {
        if (_amount == 0) revert CustomError(_err);
    }

    /// @notice A function to check whether the `_percentage` is lesser or equal to `MAX_PERCENTAGE`
    /// @param _percentage The percentage which is to be checked
    /// @dev 1000 == 10% so a valid percentage is between 1 to 10000 (0.01 - 100%)
    function _isLTEMaxPercentage(uint256 _percentage) internal pure {
        if (_percentage > MAX_PERCENTAGE) revert GTMaxPercentage(_percentage);
    }

    /// @notice A function to check whether the `_percentage` is lesser or equal to `MAX_PERCENTAGE`
    /// @param _percentage The percentage which is to be checked
    /// @dev Reverts with a CustomError and a string
    function _isLTEMaxPercentage(
        uint256 _percentage,
        string memory _err
    ) internal pure {
        if (_percentage > MAX_PERCENTAGE) revert CustomError(_err);
    }
}
