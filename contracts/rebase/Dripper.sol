// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Helpers} from "../libraries/Helpers.sol";
import {IDripper} from "../interfaces/IDripper.sol";

/// @title Dripper for USDs Protocol.
/// @author Sperax Foundation
/// @notice This contract releases tokens at a steady rate to the Vault contract, for rebasing the USDs stablecoin.
/// @dev The Dripper contract ensures that tokens are released gradually over time, allowing for consistent and controlled distribution.
contract Dripper is IDripper, Ownable {
    using SafeERC20 for IERC20;

    address public vault; // Address of the contract receiving the dripped tokens
    uint256 public dripRate; // Calculated dripping rate
    uint256 public dripDuration; // Duration over which tokens are dripped
    uint256 public lastCollectTS; // Timestamp of the last collection

    event Collected(uint256 amount);
    event Recovered(address owner, uint256 amount);
    event VaultUpdated(address vault);
    event DripDurationUpdated(uint256 dripDuration);

    error NothingToRecover();

    /// @notice Constructor to initialize the Dripper
    /// @param _vault Address of the contract that receives the dripped tokens
    /// @param _dripDuration The duration over which tokens are dripped
    constructor(address _vault, uint256 _dripDuration) {
        updateVault(_vault);
        updateDripDuration(_dripDuration);
        lastCollectTS = block.timestamp;
    }

    // Admin functions

    /// @notice Emergency fund recovery function
    /// @param _asset Address of the asset to recover
    /// @dev Transfers the asset to the owner of the contract.
    function recoverTokens(address _asset) external onlyOwner {
        uint256 bal = IERC20(_asset).balanceOf(address(this));
        if (bal == 0) revert NothingToRecover();
        IERC20(_asset).safeTransfer(msg.sender, bal);
        emit Recovered(msg.sender, bal);
    }

    /// @notice Transfers the dripped tokens to the vault
    /// @dev This function also updates the dripRate based on the fund state
    /// @return The amount of tokens collected and transferred to the vault
    function collect() external returns (uint256) {
        uint256 collectableAmt = getCollectableAmt();
        if (collectableAmt != 0) {
            lastCollectTS = block.timestamp;
            IERC20(Helpers.USDS).safeTransfer(vault, collectableAmt);
            emit Collected(collectableAmt);
        }
        if (IERC20(Helpers.USDS).balanceOf(address(this)) == 0) dripRate = 0;
        return collectableAmt;
    }

    /// @notice Function to be used to send USDs to dripper and update `dripRate`
    /// @param _amount Amount of USDs to be sent form caller to this contract
    function addUSDs(uint256 _amount) external {
        Helpers._isNonZeroAmt(_amount);
        IERC20(Helpers.USDS).safeTransferFrom(msg.sender, address(this), _amount);
        dripRate = IERC20(Helpers.USDS).balanceOf(address(this)) / dripDuration;
    }

    /// @notice Update the vault address
    /// @param _vault Address of the new vault contract
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

    /// @notice Gets the collectible amount of tokens at the current time
    /// @return The amount of tokens that can be collected
    function getCollectableAmt() public view returns (uint256) {
        uint256 timeElapsed = block.timestamp - lastCollectTS;
        uint256 dripped = timeElapsed * dripRate;
        uint256 balance = IERC20(Helpers.USDS).balanceOf(address(this));
        return (dripped > balance) ? balance : dripped;
    }
}
