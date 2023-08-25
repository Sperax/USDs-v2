pragma solidity 0.8.16;

//@audit-issue (CRITICAL) Need to change Interface Name to IStrategiesVault since
// the actual naming is interfering with the one on  interfaces/IVault.sol
interface IVault {
    function yieldReceiver() external view returns (address);
}
