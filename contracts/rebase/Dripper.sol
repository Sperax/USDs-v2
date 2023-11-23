// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Helpers} from "../libraries/Helpers.sol";
import {IDripper} from "../interfaces/IDripper.sol";

/// @title Dripper for USDs protocol
/// @notice Contract to release tokens to a recipient at a steady rate
/// @author Sperax Foundation
/// @dev This contract releases USDs at a steady rate to the Vault for rebasing USDs
contract Dripper is IDripper, Ownable2Step {
    using SafeERC20 for IERC20;

    address public vault; // Address of the contract to get the dripped tokens
    uint256 public dripRate; // Calculated dripping rate
    uint256 public dripDuration; // Duration to drip the available amount
    uint256 public lastCollectTS; // last collection ts

    event Collected(uint256 amount);
    event Recovered(address owner, uint256 amount);
    event VaultUpdated(address vault);
    event DripDurationUpdated(uint256 dripDuration);

    error NothingToRecover();

    constructor(address _vault, uint256 _dripDuration) {
        updateVault(_vault);
        updateDripDuration(_dripDuration);
        lastCollectTS = block.timestamp;
    }

    // Admin functions

    /// @notice Emergency fund recovery function
    /// @param _asset Address of the asset
    /// @dev Transfers the asset to the owner of the contract.
    function recoverTokens(address _asset) external onlyOwner {
        uint256 bal = IERC20(_asset).balanceOf(address(this));
        if (bal == 0) revert NothingToRecover();
        IERC20(_asset).safeTransfer(msg.sender, bal);
        emit Recovered(msg.sender, bal);
    }

    /// @notice Transfers the dripped tokens to the vault
    /// @dev Function also updates the dripRate based on the fund state
    function collect() external returns (uint256) {
        uint256 collectableAmt = getCollectableAmt();
        if (collectableAmt != 0) {
            lastCollectTS = block.timestamp;
            IERC20(Helpers.USDS).safeTransfer(vault, collectableAmt);
            emit Collected(collectableAmt);
        }
        dripRate = IERC20(Helpers.USDS).balanceOf(address(this)) / dripDuration;
        return collectableAmt;
    }

    /// @notice Update the vault address
    /// @param _vault Address of the new vault
    function updateVault(address _vault) public onlyOwner {
        Helpers._isNonZeroAddr(_vault);
        vault = _vault;
        emit VaultUpdated(_vault);
    }

    /// @notice Updates the dripDuration
    /// @param _dripDuration The desired drip duration to be set
    function updateDripDuration(uint256 _dripDuration) public onlyOwner {
        Helpers._isNonZeroAmt(_dripDuration);
        dripDuration = _dripDuration;
        emit DripDurationUpdated(_dripDuration);
    }

    /// @notice Gets the collectible amount of token at current time
    /// @return Returns the collectible amount
    function getCollectableAmt() public view returns (uint256) {
        uint256 timeElapsed = block.timestamp - lastCollectTS;
        uint256 dripped = timeElapsed * dripRate;
        uint256 balance = IERC20(Helpers.USDS).balanceOf(address(this));
        return (dripped > balance) ? balance : dripped;
    }
}
