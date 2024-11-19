// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IfToken {
    function deposit(uint256 assets_, address receiver_, uint256 minAmountOut_) external returns (uint256 shares_);

    function redeem(uint256 shares_, address receiver_, address owner_) external returns (uint256 assets_);

    function asset() external view returns (address asset);

    function previewDeposit(uint256 assets_) external view returns (uint256);

    function previewWithdraw(uint256 shares_) external view returns (uint256);
}
