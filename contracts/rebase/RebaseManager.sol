// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {AccessControlUpgradeable, Initializable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {SafeMathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import {IUSDs} from "../interfaces/IUSDs.sol";
import {IDripper} from "../interfaces/IDripper.sol";

contract RebaseManager is
    Initializable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeMathUpgradeable for uint256;

    bytes32 public constant REBASER_ROLE = keccak256("REBASER_ROLE");
    address public constant USDS = 0xD74f5255D557944cf7Dd0E45FF521520002D5748;

    address public vault;
    address public dripper;

    uint256 public gap;
    uint256 public aprCap;
    uint256 public aprBottom;

    uint256 public lastRebaseTS;

    event RebasedUSDs(uint256 rebaseAmt);
    event DripperChanged(address dripper);
    event GapChanged(uint256 gap);
    event APRChanged(uint256 aprCap, uint256 aprBottom);

    modifier onlyOwner() {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, _msgSender()),
            "Unauthorized caller"
        );
        _;
    }

    function initialize(
        address _vault,
        uint256 _gap,
        uint256 _aprCap,
        uint256 _aprBottom
    ) external initializer {
        __AccessControl_init();
        __ReentrancyGuard_init();
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        vault = _vault;
        gap = _gap;
        aprCap = _aprCap;
        aprBottom = _aprBottom;
        lastRebaseTS = block.timestamp;
    }

    // Admin functions

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

    function rebase() external nonReentrant {
        require(
            hasRole(REBASER_ROLE, _msgSender()) || _msgSender() == vault,
            "Unauthorized caller"
        );
        if (block.timestamp <= lastRebaseTS + gap) {
            return;
        }
        IDripper(dripper).collect();
        uint256 balance = IERC20Upgradeable(USDS).balanceOf(address(this));
        uint256 maxRebaseAmt = _getMaxRebaseAmt();
        uint256 minRebaseAmt = _getMinRebaseAmt();
        uint256 rebaseAmt = (balance > maxRebaseAmt) ? maxRebaseAmt : balance;
        // Skip when not enough USDs to rebase
        if (rebaseAmt == 0 || rebaseAmt < minRebaseAmt) {
            return;
        }
        uint256 usdsOldSupply = IERC20Upgradeable(USDS).totalSupply();
        IUSDs(USDS).burnExclFromOutFlow(rebaseAmt);
        IUSDs(USDS).changeSupply(usdsOldSupply);
        lastRebaseTS = block.timestamp;
        emit RebasedUSDs(rebaseAmt);
    }

    function _getMaxRebaseAmt() private view returns (uint256) {
        // rebaseAmt = principal * (APR_CAP/100) * timeElapsed / 1_year
        uint256 principal = IUSDs(USDS).totalSupply() -
            IUSDs(USDS).nonRebasingSupply();
        uint256 timeElapsed = block.timestamp - lastRebaseTS;
        uint256 maxRebaseAmt = (principal * aprCap * timeElapsed) / 3153600000;
        return maxRebaseAmt;
    }

    function _getMinRebaseAmt() private view returns (uint256) {
        // rebaseAmt = principal * (APR_BOTTOM/100) * timeElapsed / 1_year
        uint256 principal = IUSDs(USDS).totalSupply() -
            IUSDs(USDS).nonRebasingSupply();
        uint256 timeElapsed = block.timestamp - lastRebaseTS;
        uint256 minRebaseAmt = (principal * aprBottom * timeElapsed) /
            3153600000;
        return minRebaseAmt;
    }
}
