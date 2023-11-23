// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {IUSDs} from "../interfaces/IUSDs.sol";
import {IDripper} from "../interfaces/IDripper.sol";
import {Helpers} from "../libraries/Helpers.sol";
import {IRebaseManager} from "../interfaces/IRebaseManager.sol";

/// @title RebaseManager for USDs protocol
/// @author Sperax Foundation
/// @notice Contract handles the configuration for rebase of USDs token
///         Which enables rebase only when the pre-requisites are fulfilled
contract RebaseManager is IRebaseManager, Ownable2Step {
    using SafeMath for uint256;

    uint256 private constant ONE_YEAR = 365 days;

    address public vault; // address of the vault
    address public dripper; // address of the dripper for collecting USDs

    uint256 public gap; // min gap between two consecutive rebases
    uint256 public aprCap; // max allowed APR% for a rebase
    uint256 public aprBottom; // min allowed APR% for a rebase
    uint256 public lastRebaseTS; // timestamp of the last rebase transaction

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
    /// @dev Function is called by vault while rebasing
    /// @return returns the available amount for rebasing USDs
    function fetchRebaseAmt() external onlyVault returns (uint256) {
        uint256 rebaseFund = getAvailableRebaseAmt();
        // Get the current min and max amount based on APR config
        (uint256 minRebaseAmt, uint256 maxRebaseAmt) = getMinAndMaxRebaseAmt();

        // Cap the rebase amount
        uint256 rebaseAmt = (rebaseFund > maxRebaseAmt) ? maxRebaseAmt : rebaseFund;

        // Skip if insufficient USDs to rebase or insufficient time has elapsed
        if (rebaseAmt < minRebaseAmt || block.timestamp < lastRebaseTS + gap) {
            return 0;
        }

        // update the rebase timestamp
        lastRebaseTS = block.timestamp;

        // Collect the dripped USDs amount for rebase
        IDripper(dripper).collect();

        return rebaseAmt;
    }

    /// @notice Updates the vault address
    /// @param _newVault Address of the new vault
    function updateVault(address _newVault) public onlyOwner {
        Helpers._isNonZeroAddr(_newVault);
        vault = _newVault;
        emit VaultUpdated(_newVault);
    }

    /// @notice Updates the dripper for USDs vault
    /// @param _dripper address of the new dripper contract
    function updateDripper(address _dripper) public onlyOwner {
        Helpers._isNonZeroAddr(_dripper);
        dripper = _dripper;
        emit DripperUpdated(_dripper);
    }

    /// @notice Update the minimum gap required b/w two rebases
    /// @param _gap updated gap time
    function updateGap(uint256 _gap) public onlyOwner {
        gap = _gap;
        emit GapUpdated(_gap);
    }

    /// @notice Update the APR requirements for each rebase
    /// @param _aprCap new MAX APR for rebase
    /// @param _aprBottom new MIN APR for rebase
    function updateAPR(uint256 _aprBottom, uint256 _aprCap) public onlyOwner {
        if (_aprCap < _aprBottom) revert InvalidAPRConfig(_aprBottom, _aprCap);
        aprCap = _aprCap;
        aprBottom = _aprBottom;
        emit APRUpdated(_aprBottom, _aprCap);
    }

    /// @notice Gets the current available rebase fund
    /// @return Returns currentBal in vault + collectable dripped USDs amt
    function getAvailableRebaseAmt() public view returns (uint256) {
        uint256 collectableAmt = IDripper(dripper).getCollectableAmt();
        uint256 currentBal = IERC20(Helpers.USDS).balanceOf(vault);
        return currentBal + collectableAmt;
    }

    /// @notice Gets the min and max rebase USDs amount based on the APR config
    /// @return min and max rebase amount
    function getMinAndMaxRebaseAmt() public view returns (uint256, uint256) {
        uint256 principal = IUSDs(Helpers.USDS).totalSupply() - IUSDs(Helpers.USDS).nonRebasingSupply();
        uint256 timeElapsed = block.timestamp - lastRebaseTS;
        uint256 minRebaseAmt = (principal * aprBottom * timeElapsed) / (ONE_YEAR * Helpers.MAX_PERCENTAGE);
        uint256 maxRebaseAmt = (principal * aprCap * timeElapsed) / (ONE_YEAR * Helpers.MAX_PERCENTAGE);
        return (minRebaseAmt, maxRebaseAmt);
    }
}
