// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// @dev The below interfaces are only for testing migration.
interface IOldAaveStrategy {
    function withdrawLPForMigration(address _asset, uint256 _amount) external;

    function withdrawToVault(address _asset, uint256 _amount) external;

    function checkATokenBalance(address _asset) external view returns (uint256);

    function checkBalance(address _asset) external view returns (uint256);

    function checkAvailableBalance(address _asset) external view returns (uint256);
}

interface IOldVault {
    // @notice Migrates funds to newVault
    function migrateFunds(address[] memory _assets, address _newVault) external;

    function updateBuybackAddr(address _newBuyback) external;

    function harvestInterest(address _strategy, address _collateral) external;
}
