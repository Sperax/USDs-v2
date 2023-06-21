// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.16;

import {OwnableUpgradeable, Initializable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {SafeERC20Upgradeable, IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

contract Dripper is Initializable, OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address private constant USDS = 0xD74f5255D557944cf7Dd0E45FF521520002D5748;

    address public rebaseManager;
    uint256 public dripRate;
    uint256 public dripDuration;
    uint256 public lastCollectTS;

    event Collected(uint256 amount);
    event RebaseManagerChanged(address rebaseManager);
    event DripDurationChanged(uint256 dripDuration);

    function initialize(
        address _rebaseManager,
        uint256 _dripDuration
    ) external initializer {
        __Ownable_init();
        rebaseManager = _rebaseManager;
        dripDuration = _dripDuration;
        lastCollectTS = block.timestamp;
    }

    // Admin functions

    function setRebaseManager(address _rebaseManager) external onlyOwner {
        require(_rebaseManager != address(0), "Illegal input");
        rebaseManager = _rebaseManager;
        emit RebaseManagerChanged(rebaseManager);
    }

    function setDripDuration(uint256 _dripDuration) external onlyOwner {
        require(_dripDuration > 0, "Illegal input");
        dripDuration = _dripDuration;
        emit DripDurationChanged(dripDuration);
    }

    function collect() public returns (uint256) {
        require(rebaseManager != address(0), "Incomplete config");
        require(
            _msgSender() == rebaseManager || _msgSender() == owner(),
            "Unauthorized caller"
        );
        uint256 collectableAmt = getCollectableAmt();
        if (collectableAmt > 0) {
            IERC20Upgradeable(USDS).safeTransfer(rebaseManager, collectableAmt);
            lastCollectTS = block.timestamp;
            dripRate =
                IERC20Upgradeable(USDS).balanceOf(address(this)) /
                dripDuration;
            emit Collected(collectableAmt);
        }
    }

    function getCollectableAmt() public view returns (uint256) {
        uint256 timeElapsed = block.timestamp - lastCollectTS;
        uint256 dripped = timeElapsed * dripRate;
        uint256 balance = IERC20Upgradeable(USDS).balanceOf(address(this));
        return (dripped > balance) ? balance : dripped;
    }
}
