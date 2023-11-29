// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IVault {
    function mintBySpecifyingCollateralAmt(
        address _collateral,
        uint256 _collateralAmt,
        uint256 _minUSDSAmt,
        uint256 _maxSPAburnt,
        uint256 _deadline
    ) external;

    /// @notice mint USDs by depositing collateral
    /// @param _collateral address of the collateral
    /// @param _collateralAmt amount of collateral to mint USDs with
    /// @param _minUSDSAmt minimum expected amount of USDs to be minted
    /// @param _deadline the expiry time of the transaction
    function mint(address _collateral, uint256 _collateralAmt, uint256 _minUSDSAmt, uint256 _deadline) external;

    function redeem(address _collateral, uint256 _usdsAmt, uint256 _minCollAmt, uint256 _deadline, address _strategy)
        external;

    function redeem(address _collateral, uint256 _usdsAmt, uint256 _minCollAmt, uint256 _deadline) external;

    function redeemFull(address _collateral, uint256 _minCollAmt, uint256 _deadline, address _strategy) external;

    function rebase() external;

    function allocate(address _collateral, address _strategy, uint256 _amount) external;

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
    function mintView(address _collateral, uint256 _collateralAmt) external view returns (uint256, uint256);

    function redeemView(address _collateral, uint256 _usdsAmt, address _strategyAddr)
        external
        view
        returns (
            uint256 calculatedCollateralAmt,
            uint256 usdsBurnAmt,
            uint256 feeAmt,
            uint256 vaultAmt,
            uint256 strategyAmt
        );

    function redeemView(address _collateral, uint256 _usdsAmt)
        external
        view
        returns (
            uint256 calculatedCollateralAmt,
            uint256 usdsBurnAmt,
            uint256 feeAmt,
            uint256 vaultAmt,
            uint256 strategyAmt
        );

    function feeVault() external view returns (address);

    function yieldReceiver() external view returns (address);

    function collateralManager() external view returns (address);

    function feeCalculator() external view returns (address);

    function oracle() external view returns (address);

    function rebaseManager() external view returns (address);
}
