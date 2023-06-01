//SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IUSDs {
    function mint(address _account, uint256 _amount) external;

    function burn(uint256 _amount) external;

    function burnExclFromOutFlow(uint256 _amount) external;

    function changeSupply(uint256 _newTotalSupply) external;

    function mintedViaUsers() external view returns (uint256);

    function burntViaUsers() external view returns (uint256);
}
