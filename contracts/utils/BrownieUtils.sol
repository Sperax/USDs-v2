// SPDX-License-Identifier: UNLICENSED
/* solhint-disable */
pragma solidity 0.8.19;

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ERC20, ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
// @note This file is only for facilitating contract imports for brownie script

contract PA is ProxyAdmin {}

// @note For testnet deployment
// !! not to be used for production
contract CustomERC20 is ERC20, ERC20Burnable, Ownable {
    uint8 private _decimals;

    constructor(string memory _name, string memory _symbol, uint8 _d) ERC20(_name, _symbol) {
        _decimals = _d;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(uint256 _amount) public onlyOwner {
        _mint(msg.sender, _amount);
    }

    function mint(address _account, uint256 _amount) public onlyOwner {
        _mint(_account, _amount);
    }
}

contract TUP is TransparentUpgradeableProxy {
    constructor(address _logic, address admin_, bytes memory _data)
        payable
        TransparentUpgradeableProxy(_logic, admin_, _data)
    {}
}
