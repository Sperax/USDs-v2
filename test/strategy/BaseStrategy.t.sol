// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

contract BaseStrategy {
    event VaultUpdated(address newVaultAddr);
    event YieldReceiverUpdated(address newYieldReceiver);
    event PTokenAdded(address indexed asset, address pToken);
    event PTokenRemoved(address indexed asset, address pToken);
    event Deposit(address indexed asset, address pToken, uint256 amount);
    event Withdrawal(address indexed asset, address pToken, uint256 amount);
    event SlippageUpdated(uint16 depositSlippage, uint16 withdrawSlippage);
    event HarvestIncentiveCollected(address indexed token, address indexed harvestor, uint256 amount);
    event HarvestIncentiveRateUpdated(uint16 newRate);
    event InterestCollected(address indexed asset, address indexed recipient, uint256 amount);
    event RewardTokenCollected(address indexed rwdToken, address indexed recipient, uint256 amount);

    error CallerNotVault(address caller);
    error CallerNotVaultOrOwner(address caller);
    error PTokenAlreadySet(address collateral, address pToken);
    error InvalidIndex();
    error CollateralNotSupported(address asset);
    error InvalidAssetLpPair(address asset, address lpToken);
    error CollateralAllocated(address asset);
}
