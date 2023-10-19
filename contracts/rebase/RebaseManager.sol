// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {IUSDs} from "../interfaces/IUSDs.sol";
import {IDripper} from "../interfaces/IDripper.sol";
import {Helpers} from "../libraries/Helpers.sol";
import {IRebaseManager} from "../interfaces/IRebaseManager.sol";

/// @title Rebase Manager for USDs Protocol
/// @notice This contract handles the configuration and execution of the rebasing mechanism for the USDs stablecoin.
///         It ensures that rebases occur only when certain prerequisites are fulfilled, such as the time gap between rebases and acceptable APR (Annual Percentage Rate) ranges.
/// @dev The Rebase Manager coordinates with the Vault and Dripper contracts to manage the rebase process.
/// @author Sperax Foundation
contract RebaseManager is IRebaseManager, Ownable {
    using SafeMath for uint256;

    uint256 private constant ONE_YEAR = 365 days;

    address public vault; // Address of the vault contract
    address public dripper; // Address of the dripper contract for collecting USDs

    uint256 public gap; // Minimum time gap required between two consecutive rebases
    uint256 public aprCap; // Maximum allowed APR for a rebase
    uint256 public aprBottom; // Minimum allowed APR for a rebase
    uint256 public lastRebaseTS; // Timestamp of the last rebase transaction

    event VaultUpdated(address vault);
    event DripperUpdated(address dripper);
    event GapUpdated(uint256 gap);
    event APRUpdated(uint256 aprBottom, uint256 aprCap);

    error CallerNotVault(address caller);
    error InvalidAPRConfig(uint256 aprBottom, uint256 aprCap);

    modifier onlyVault() {
        if (msg.sender != vault) revert CallerNotVault(msg.sender);
        _;
    }

    /// @notice Constructor to initialize the Rebase Manager
    /// @param _vault Address of the vault contract
    /// @param _dripper Address of the dripper contract for collecting USDs
    /// @param _gap Minimum time gap required between two consecutive rebases
    /// @param _aprCap Maximum allowed APR for a rebase
    /// @param _aprBottom Minimum allowed APR for a rebase
    constructor(
        address _vault,
        address _dripper,
        uint256 _gap,
        uint256 _aprCap, // 1000 = 10%
        uint256 _aprBottom // 800 = 8%
    ) {
        updateVault(_vault);
        updateDripper(_dripper);
        updateGap(_gap);
        updateAPR(_aprBottom, _aprCap);
        lastRebaseTS = block.timestamp;
    }

    /// @notice Get the current amount valid for rebase
    /// @dev Function is called by the vault while rebasing
    /// @return The available amount for rebasing USDs
    function fetchRebaseAmt() external onlyVault returns (uint256) {
        uint256 rebaseFund = getAvailableRebaseAmt();
        // Get the current minimum and maximum amount based on APR config
        (uint256 minRebaseAmt, uint256 maxRebaseAmt) = getMinAndMaxRebaseAmt();

        // Cap the rebase amount
        uint256 rebaseAmt = (rebaseFund > maxRebaseAmt) ? maxRebaseAmt : rebaseFund;

        // Skip if there are insufficient USDs to rebase or insufficient time has elapsed
        if (rebaseAmt < minRebaseAmt || block.timestamp < lastRebaseTS + gap) {
            return 0;
        }

        // Update the rebase timestamp
        lastRebaseTS = block.timestamp;

        // Collect the dripped USDs amount for rebase
        IDripper(dripper).collect();

        return rebaseAmt;
    }

    /// @notice Updates the vault address
    /// @param _newVault Address of the new vault contract
    function updateVault(address _newVault) public onlyOwner {
        Helpers._isNonZeroAddr(_newVault);
        vault = _newVault;
        emit VaultUpdated(_newVault);
    }

    /// @notice Updates the dripper contract for USDs vault
    /// @param _dripper Address of the new dripper contract
    function updateDripper(address _dripper) public onlyOwner {
        Helpers._isNonZeroAddr(_dripper);
        dripper = _dripper;
        emit DripperUpdated(_dripper);
    }

    /// @notice Update the minimum time gap required between two rebases
    /// @param _gap Updated gap time
    function updateGap(uint256 _gap) public onlyOwner {
        gap = _gap;
        emit GapUpdated(_gap);
    }

    /// @notice Update the APR requirements for each rebase
    /// @param _aprCap New maximum APR for a rebase
    /// @param _aprBottom New minimum APR for a rebase
    function updateAPR(uint256 _aprBottom, uint256 _aprCap) public onlyOwner {
        if (_aprCap < _aprBottom) revert InvalidAPRConfig(_aprBottom, _aprCap);
        aprCap = _aprCap;
        aprBottom = _aprBottom;
        emit APRUpdated(_aprBottom, _aprCap);
    }

    /// @notice Gets the current available rebase fund
    /// @return Current balance in the vault plus collectable dripped USDs amount
    function getAvailableRebaseAmt() public view returns (uint256) {
        uint256 collectableAmt = IDripper(dripper).getCollectableAmt();
        uint256 currentBal = IERC20(Helpers.USDS).balanceOf(vault);
        return currentBal + collectableAmt;
    }

    /// @notice Gets the minimum and maximum rebase USDs amount based on the APR config
    /// @return Minimum and maximum rebase amounts
    function getMinAndMaxRebaseAmt() public view returns (uint256, uint256) {
        uint256 principal = IUSDs(Helpers.USDS).totalSupply() - IUSDs(Helpers.USDS).nonRebasingSupply();
        uint256 timeElapsed = block.timestamp - lastRebaseTS;
        uint256 minRebaseAmt = (principal * aprBottom * timeElapsed) / (ONE_YEAR * Helpers.MAX_PERCENTAGE);
        uint256 maxRebaseAmt = (principal * aprCap * timeElapsed) / (ONE_YEAR * Helpers.MAX_PERCENTAGE);
        return (minRebaseAmt, maxRebaseAmt);
    }
}
