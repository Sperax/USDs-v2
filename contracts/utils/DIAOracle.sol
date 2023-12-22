// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface IDiaOracle {
    function getValue(string memory key) external view returns (uint128 price, uint128 lastUpdateTime);
}

/// @title Oracle contract of USDs protocol
/// @dev providing SPA prices (from Uniswap V3 pools and DIA oracle)
/// @author Sperax Inc
contract DIAOracle is Ownable {
    struct TokenData {
        address token;
        string key;
    }

    address public constant DIA_ORACLE = 0x771B5669b9994E8cfAB45D605D2044d260CBb061;

    mapping(address => string) public feedKey;

    constructor(TokenData[] memory data) {
        for (uint256 i = 0; i < data.length; i++) {
            feedKey[data[i].token] = data[i].key;
        }
    }

    function setTokenFeed(TokenData calldata data) external {
        feedKey[data.token] = data.key;
    }

    /// @notice Get SPA price
    /// @dev SPA price is a weighted combination of DIA SPA price and Uni SPA
    ///      price
    /// @return uint256 SPA price with precision SPA_PRICE_PRECISION (10^18)
    function getPrice(address _token) external view returns (uint256, uint256) {
        // calculate weighted DIA USDsPerSPA
        (uint128 diaPrice,) = IDiaOracle(DIA_ORACLE).getValue(feedKey[_token]);

        return (diaPrice, 1e8);
    }
}
