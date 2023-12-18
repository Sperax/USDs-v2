pragma solidity 0.8.19;

interface IStargatePool {
    function totalLiquidity() external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function convertRate() external view returns (uint256);

    function deltaCredit() external view returns (uint256);

    function poolId() external view returns (uint256);

    function token() external view returns (address);
}
