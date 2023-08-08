// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

interface IVault {
    function mintBySpecifyingCollateralAmt(
        address collateralAddr,
        uint256 collateralAmtToLock,
        uint256 minUSDsMinted,
        uint256 maxSPAburnt,
        uint256 deadline
    ) external;

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

    function updateFeeVault(address _feeVault) external;

    function updateYieldReceiver(address _yieldReceiver) external;

    function updateCollateralManager(address _collateralManager) external;

    function updateRebaseManager(address _rebaseManager) external;

    function updateFeeCalculator(address _feeCalculator) external;

    function updateOracle(address _oracle) external;

    /// @notice Get the expected mint result (USDs amt, fee)
    /// @param _collateral address of the collateral
    /// @param _collateralAmt amount of collateral
    /// @return Returns the expected USDs mint amount and fee for minting
    function mintView(
        address _collateral,
        uint256 _collateralAmt
    ) external view returns (uint256, uint256);
}
