// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {IUSDs} from "../interfaces/IUSDs.sol";
import {IDripper} from "../interfaces/IDripper.sol";

/// @title RebaseManager
/// @notice Contract handles the configuration for rebase of USDs token
///         Which enables rebase only when the pre-requisites are fulfilled
contract RebaseManager is Ownable {
    using SafeMath for uint256;

    address public constant USDS = 0xD74f5255D557944cf7Dd0E45FF521520002D5748;
    uint256 private constant ONE_YEAR = 365 days;
    uint256 private constant PERC_PRECISION = 10000;

    address public vault; // address of the vault
    address public dripper; // address of the dripper for collecting USDs

    uint256 public gap; // min gap between two consecutive rebases
    uint256 public aprCap; // max allowed APR% for a rebase
    uint256 public aprBottom; // min allowed APR% for a rebase
    uint256 public lastRebaseTS; // timestamp of the last rebase transaction

    event DripperChanged(address dripper);
    event GapChanged(uint256 gap);
    event APRChanged(uint256 aprBottom, uint256 aprCap);

    modifier onlyVault() {
        require(msg.sender == vault, "Unauthorized caller");
        _;
    }

    constructor(
        address _vault,
        address _dripper,
        uint256 _gap,
        uint256 _aprCap, // 1000 = 10%
        uint256 _aprBottom // 800 = 8%
    ) {
        _isValidAddress(_vault);
        _isValidAddress(_dripper);
        vault = _vault;
        dripper = _dripper;
        gap = _gap;
        aprCap = _aprCap;
        aprBottom = _aprBottom;
        lastRebaseTS = block.timestamp;
    }

    /// @notice Updates the dripper for USDs vault
    /// @param _dripper address of the new dripper contract
    function setDripper(address _dripper) external onlyOwner {
        _isValidAddress(_dripper);
        dripper = _dripper;
        emit DripperChanged(dripper);
    }

    /// @notice Update the minimum gap required b/w two rebases
    /// @param _gap updated gap time
    function setGap(uint256 _gap) external onlyOwner {
        gap = _gap;
        emit GapChanged(gap);
    }

    /// @notice Update the APR requirements for each rebase
    /// @param _aprCap new MAX APR for rebase
    /// @param _aprBottom new MIN APR for rebase
    function setAPR(uint256 _aprBottom, uint256 _aprCap) external onlyOwner {
        require(_aprCap >= _aprBottom, "Invalid APR config");
        aprCap = _aprCap;
        aprBottom = _aprBottom;
        emit APRChanged(_aprBottom, _aprCap);
    }

    /// @notice Get the current amount valid for rebase
    /// @dev Function is called by vault while rebasing
    /// @return returns the available amount for rebasing USDs
    function fetchRebaseAmt() external onlyVault returns (uint256) {
        uint256 rebaseFund = getAvailableRebaseAmt();
        // Get the current min and max amount based on APR config
        (uint256 minRebaseAmt, uint256 maxRebaseAmt) = getMinAndMaxRebaseAmt();

        // Cap the rebase amount
        uint256 rebaseAmt = (rebaseFund > maxRebaseAmt)
            ? maxRebaseAmt
            : rebaseFund;

        // Skip if insufficient USDs to rebase or insufficient time has elapsed
        if (rebaseAmt < minRebaseAmt || block.timestamp <= lastRebaseTS + gap) {
            return 0;
        }
        // Collect the dripped USDs amount for rebase
        IDripper(dripper).collect();

        // update the rebase timestamp
        lastRebaseTS = block.timestamp;
        return rebaseAmt;
    }

    /// @notice Gets the current available rebase fund
    /// @return Returns currentBal in vault + collectable dripped USDs amt
    function getAvailableRebaseAmt() public view returns (uint256) {
        uint256 collectableAmt = IDripper(dripper).getCollectableAmt();
        uint256 currentBal = IERC20(USDS).balanceOf(vault);
        return currentBal + collectableAmt;
    }

    /// @notice Gets the min and max rebase USDs amount based on the APR config
    /// @return min and max rebase amount
    function getMinAndMaxRebaseAmt() public view returns (uint256, uint256) {
        uint256 principal = IUSDs(USDS).totalSupply() -
            IUSDs(USDS).nonRebasingSupply();
        uint256 timeElapsed = block.timestamp - lastRebaseTS;
        uint256 minRebaseAmt = (principal * aprBottom * timeElapsed) /
            (ONE_YEAR * PERC_PRECISION);
        uint256 maxRebaseAmt = (principal * aprCap * timeElapsed) /
            (ONE_YEAR * PERC_PRECISION);
        return (minRebaseAmt, maxRebaseAmt);
    }

    function _isValidAddress(address _address) private pure {
        require(_address != address(0), "Invalid Address");
    }
}
