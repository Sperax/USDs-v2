//SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IStrategy {
    /**
     * @dev Deposit the given collateral to platform
     * @param _collateral collateral address
     * @param _amount Amount to deposit
     */
    function deposit(address _collateral, uint256 _amount) external;

    /**
     * @dev Withdraw given collateral from Lending platform
     * @param _recipient recipient address
     * @param _collateral collateral address
     * @param _amount Intended amount to withdraw
     * @return amountReceived The actual amount received
     */
    function withdraw(
        address _recipient,
        address _collateral,
        uint256 _amount
    ) external returns (uint256 amountReceived);

    /**
     * @notice Get the amount of a specific asset held in the strategy,
               excluding the interest and any locked liquidity that is not
               available for instant withdrawal
     * @dev Curve: assuming balanced withdrawal
     * @param _asset      Address of the asset
     */
    function checkAvailableBalance(
        address _asset
    ) external view returns (uint256);
}
