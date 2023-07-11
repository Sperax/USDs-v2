// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

interface IVault {
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
    ) external;

    /// @notice Get the expected mint result (USDs amt, fee)
    /// @param _collateral address of the collateral
    /// @param _collateralAmt amount of collateral
    /// @return Returns the expected USDs mint amount and fee for minting
    function mintView(
        address _collateral,
        uint256 _collateralAmt
    ) external view returns (uint256, uint256);
}
