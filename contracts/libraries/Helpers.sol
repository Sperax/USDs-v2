// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

library Helpers {
    uint128 internal constant MAX_PERCENTAGE = 10000;
    address internal constant SPA = 0x5575552988A3A80504bBaeB1311674fCFd40aD4B;
    address internal constant USDS = 0xD74f5255D557944cf7Dd0E45FF521520002D5748;

    error CustomError(string message);
    error InvalidAddress();
    error GTMaxPercentage(uint256 _actual, uint256 _max);
    error InvalidAmount();
    error MinSlippageError(uint256 actualAmt, uint256 minExpectedAmt);
    error MaxSlippageError(uint256 actualAmt, uint256 maxExpectedAmt);

    function _checkDeadline(uint256 _deadline) internal view {
        require(block.timestamp <= _deadline, "Deadline passed");
    }

    /// @notice Check for non-zero address
    /// @param _addr Address to be validated
    function _isNonZeroAddr(address _addr) internal pure {
        if (_addr == address(0)) revert InvalidAddress();
    }

    /// @notice Check for non-zero mount
    /// @param _amount Amount to be validated
    function _isNonZeroAmt(uint256 _amount) internal pure {
        if (_amount == 0) revert InvalidAmount();
    }

    /// @notice Check for non-zero mount
    /// @param _amount Amount to be validated
    function _isNonZeroAmt(uint256 _amount, string memory err) internal pure {
        if (_amount == 0) revert CustomError(err);
    }

    function _isLTEMaxPercentage(uint256 _percentage) internal pure {
        if (_percentage > MAX_PERCENTAGE)
            revert GTMaxPercentage(_percentage, MAX_PERCENTAGE);
    }

    function _isLTEMaxPercentage(
        uint256 _percentage,
        string memory err
    ) internal pure {
        if (_percentage > MAX_PERCENTAGE) revert CustomError(err);
    }
}
