//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IUSDs {
    function mint(address _account, uint256 _amount) external;

    function burn(uint256 _amount) external;

    function rebase(uint256 _rebaseAmt) external;

    function totalSupply() external view returns (uint256);

    function nonRebasingSupply() external view returns (uint256);

    function creditsBalanceOf(address _account) external view returns (uint256, uint256);
}
