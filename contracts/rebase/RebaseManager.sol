// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {IUSDs} from "../interfaces/IUSDs.sol";
import {IDripper} from "../interfaces/IDripper.sol";

contract RebaseManager is Ownable {
    using SafeMath for uint256;

    address public constant USDS = 0xD74f5255D557944cf7Dd0E45FF521520002D5748;
    uint256 private constant ONE_YEAR = 3153600000;

    address public vault;
    address public dripper;

    uint256 public gap;
    uint256 public aprCap;
    uint256 public aprBottom;
    uint256 public lastRebaseTS;

    event DripperChanged(address dripper);
    event GapChanged(uint256 gap);
    event APRChanged(uint256 aprCap, uint256 aprBottom);

    modifier onlyVault() {
        require(msg.sender == vault, "Unauthorized caller");
        _;
    }

    constructor(
        address _vault,
        uint256 _gap,
        uint256 _aprCap,
        uint256 _aprBottom
    ) {
        vault = _vault;
        gap = _gap;
        aprCap = _aprCap;
        aprBottom = _aprBottom;
        lastRebaseTS = block.timestamp;
    }

    function setDripper(address _dripper) external onlyOwner {
        require(_dripper != address(0), "Illegal input");
        dripper = _dripper;
        emit DripperChanged(dripper);
    }

    function setGap(uint256 _gap) external onlyOwner {
        gap = _gap;
        emit GapChanged(gap);
    }

    function setAPR(uint256 _aprCap, uint256 _aprBottom) external onlyOwner {
        aprCap = _aprCap;
        aprBottom = _aprBottom;
        emit APRChanged(_aprCap, _aprBottom);
    }

    function fetchRebaseAmt() external onlyVault returns (uint256) {
        uint256 rebaseableAmt = getRebaseableAmt();
        (uint256 minRebaseAmt, uint256 maxRebaseAmt) = getMinAndMaxRebaseAmt();
        uint256 rebaseAmt = (rebaseableAmt > maxRebaseAmt)
            ? maxRebaseAmt
            : rebaseableAmt;
        // Skip if insufficient USDs to rebase or insufficient time has elapsed
        if (rebaseAmt < minRebaseAmt || block.timestamp <= lastRebaseTS + gap) {
            return 0;
        }
        IDripper(dripper).collect();
        lastRebaseTS = block.timestamp;
        return rebaseAmt;
    }

    function getRebaseableAmt() public view returns (uint256) {
        uint256 collectableAmt = IDripper(dripper).getCollectableAmt();
        uint256 currBalance = IERC20(USDS).balanceOf(vault);
        return currBalance + collectableAmt;
    }

    function getMinAndMaxRebaseAmt() public view returns (uint256, uint256) {
        uint256 principal = IUSDs(USDS).totalSupply() -
            IUSDs(USDS).nonRebasingSupply();
        uint256 timeElapsed = block.timestamp - lastRebaseTS;
        uint256 minRebaseAmt = (principal * aprBottom * timeElapsed) / ONE_YEAR;
        uint256 maxRebaseAmt = (principal * aprCap * timeElapsed) / ONE_YEAR;
        return (minRebaseAmt, maxRebaseAmt);
    }
}
