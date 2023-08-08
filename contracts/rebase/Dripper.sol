// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.16;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Contract to release tokens to a recipient at a steady rate
/// @dev This contract releases USDs at a steady rate to the Vault for rebasing USDs
contract Dripper is Ownable {
    using SafeERC20 for IERC20;

    address public constant USDS = 0xD74f5255D557944cf7Dd0E45FF521520002D5748;

    address public vault; // Address of the contract to get the dripped tokens
    uint256 public dripRate; // Calculated dripping rate
    uint256 public dripDuration; // Duration to drip the available amount
    uint256 public lastCollectTS; // last collection ts

    event Collected(uint256 amount);
    event Recovered(address owner, uint256 amount);
    event VaultUpdated(address vault);
    event DripDurationUpdated(uint256 dripDuration);

    constructor(address _vault, uint256 _dripDuration) {
        _isNonZeroAddr(_vault);
        vault = setVault(_vault);
        dripDuration = setDripDuration(_dripDuration);
        lastCollectTS = block.timestamp;
    }

    // Admin functions

    /// @notice Emergency fund recovery function
    /// @param _asset Address of the asset
    /// @dev Transfers the asset to the owner of the contract.
    function recoverTokens(address _asset) external onlyOwner {
        uint256 bal = IERC20(_asset).balanceOf(address(this));
        require(bal > 0, "Nothing to recover");
        IERC20(_asset).safeTransfer(msg.sender, bal);
        emit Recovered(msg.sender, bal);
    }

    /// @notice Transfers the dripped tokens to the vault
    /// @dev Function also updates the dripRate based on the fund state
    function collect() external returns (uint256) {
        uint256 collectableAmt = getCollectableAmt();
        if (collectableAmt > 0) {
            IERC20(USDS).safeTransfer(vault, collectableAmt);
            lastCollectTS = block.timestamp;
            emit Collected(collectableAmt);
        }
        dripRate = IERC20(USDS).balanceOf(address(this)) / dripDuration;
        return collectableAmt;
    }

    /// @notice Update the vault address
    /// @param _vault Address of the desired vault
    function setVault(address _vault) public onlyOwner returns (address) {
        _isNonZeroAddr(_vault);
        vault = _vault;
        emit VaultUpdated(vault);
        return (vault);
    }

    /// @notice Updates the dripDuration
    /// @param _dripDuration Desired drip duration
    function setDripDuration(
        uint256 _dripDuration
    ) public onlyOwner returns (uint256) {
        require(_dripDuration != 0, "Invalid input");
        dripDuration = _dripDuration;
        emit DripDurationUpdated(dripDuration);
        return dripDuration;
    }

    /// @notice Gets the collectible amount of token at current time
    /// @return Returns the collectible amount
    function getCollectableAmt() public view returns (uint256) {
        uint256 timeElapsed = block.timestamp - lastCollectTS;
        uint256 dripped = timeElapsed * dripRate;
        uint256 balance = IERC20(USDS).balanceOf(address(this));
        return (dripped > balance) ? balance : dripped;
    }

    /// @notice Address input sanity check function
    /// @param _addr Address to be checked
    function _isNonZeroAddr(address _addr) private pure {
        require(_addr != address(0), "Zero address");
    }
}
