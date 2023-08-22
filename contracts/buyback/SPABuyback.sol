// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {ERC20BurnableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IOracle} from "../interfaces/IOracle.sol";
import {Helpers} from "../libraries/Helpers.sol";

/// @title Buyback contract of the USDs Buyback protocol
/// @notice Give SPA and get USDs
/// @author Sperax Foundation
contract SPABuyback is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20Upgradeable for ERC20BurnableUpgradeable;

    address public veSpaRewarder;
    uint256 public rewardPercentage;
    address public oracle;

    event BoughtBack(
        address indexed receiverOfUSDs,
        address indexed senderOfSPA,
        uint256 spaPrice,
        uint256 spaAmount,
        uint256 usdsAmount
    );
    event Withdrawn(
        address indexed token,
        address indexed receiver,
        uint256 amount
    );
    event SPARewarded(uint256 spaAmount);
    event SPABurned(uint256 spaAmount);
    event RewardPercentageUpdated(
        uint256 oldRewardPercentage,
        uint256 newRewardPercentage
    );
    event VeSpaRewarderUpdated(
        address oldVeSpaRewarder,
        address newVeSpaRewarder
    );
    event OracleUpdated(address newOracle);

    // Disable initialization for the implementation contract
    constructor() {
        _disableInitializers();
    }

    /// @dev Contract initializer
    /// @param _veSpaRewarder Rewarder's address
    /// @param _rewardPercentage Percentage of SPA to be rewarded
    function initialize(
        address _veSpaRewarder,
        uint256 _rewardPercentage
    ) external initializer {
        Helpers._isNonZeroAddr(_veSpaRewarder);
        _isValidRewardPercentage(_rewardPercentage);
        OwnableUpgradeable.__Ownable_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
        veSpaRewarder = _veSpaRewarder;
        rewardPercentage = _rewardPercentage;
    }

    /// @notice Emergency withdrawal function for unexpected situations
    /// @param _token Address of the asset to be withdrawn
    /// @param _receiver Address of the receiver of tokens
    /// @param _amount Amount of tokens to be withdrawn
    function withdraw(
        address _token,
        address _receiver,
        uint256 _amount
    ) external onlyOwner {
        Helpers._isNonZeroAddr(_token);
        Helpers._isNonZeroAddr(_receiver);
        Helpers._isNonZeroAmt(_amount);
        require(_token != Helpers.SPA, "SPA Buyback: Cannot withdraw SPA");
        emit Withdrawn(_token, _receiver, _amount);
        ERC20BurnableUpgradeable(_token).safeTransfer(_receiver, _amount);
    }

    /// @notice Changes the reward percentage
    /// @param _newRewardPercentage New Reward Percentage
    /// @dev Example value for _newRewardPercentage = 5000 for 50%
    function updateRewardPercentage(
        uint256 _newRewardPercentage
    ) external onlyOwner {
        _isValidRewardPercentage(_newRewardPercentage);
        emit RewardPercentageUpdated(rewardPercentage, _newRewardPercentage);
        rewardPercentage = _newRewardPercentage;
    }

    /// @notice Update veSpaRewarder address
    /// @param _newVeSpaRewarder is the address of desired veSpaRewarder
    function updateVeSpaRewarder(address _newVeSpaRewarder) external onlyOwner {
        Helpers._isNonZeroAddr(_newVeSpaRewarder);
        emit VeSpaRewarderUpdated(veSpaRewarder, _newVeSpaRewarder);
        veSpaRewarder = _newVeSpaRewarder;
    }

    /// @notice Update oracle address
    /// @param _newOracle is the address of desired oracle
    function updateOracle(address _newOracle) external onlyOwner {
        Helpers._isNonZeroAddr(_newOracle);
        oracle = _newOracle;
        emit OracleUpdated(_newOracle);
    }

    /// @notice Function to buy USDs for SPA for frontend
    /// @param _spaIn Amount of SPA tokens
    /// @param _minUSDsOut Minimum amount out in USDs
    function buyUSDs(uint256 _spaIn, uint256 _minUSDsOut) external {
        buyUSDs(msg.sender, _spaIn, _minUSDsOut);
    }

    /// @notice Calculates and returns SPA amount required for _usdsAmount
    /// @param _usdsAmount USDs amount the user wants
    /// @return Amount of SPA required
    function getSPAReqdForUSDs(
        uint256 _usdsAmount
    ) external view returns (uint256) {
        Helpers._isNonZeroAmt(_usdsAmount);

        // Getting data from oracle
        (
            uint256 usdsPrice,
            uint256 spaPrice,
            uint256 usdsPricePrecision,
            uint256 spaPricePrecision
        ) = _getOracleData();

        // Calculates the total USDs value
        uint256 totalUsdsValue = (_usdsAmount * usdsPrice) / usdsPricePrecision;

        // Calculates spa amount required
        uint256 spaAmtReqd = (totalUsdsValue * spaPricePrecision) / spaPrice;

        return spaAmtReqd;
    }

    /// @notice Buy USDs for SPA if you want a different receiver
    /// @param _receiver Receiver of USDs
    /// @param _spaIn Amount of SPA tokens
    /// @param _minUSDsOut Minimum amount out in USDs
    function buyUSDs(
        address _receiver,
        uint256 _spaIn,
        uint256 _minUSDsOut
    ) public nonReentrant {
        Helpers._isNonZeroAddr(_receiver);
        (uint256 usdsToSend, uint256 spaPrice) = _getUsdsOutForSpa(_spaIn);
        require(usdsToSend > 0, "SPA Amount too low");
        require(usdsToSend >= _minUSDsOut, "Slippage more than expected");
        require(
            usdsToSend <=
                ERC20BurnableUpgradeable(Helpers.USDS).balanceOf(address(this)),
            "Insufficient USDs balance"
        );
        emit BoughtBack({
            receiverOfUSDs: _receiver,
            senderOfSPA: msg.sender,
            spaPrice: spaPrice,
            spaAmount: _spaIn,
            usdsAmount: usdsToSend
        });
        ERC20BurnableUpgradeable(Helpers.SPA).safeTransferFrom(
            msg.sender,
            address(this),
            _spaIn
        );
        distributeAndBurnSPA();
        ERC20BurnableUpgradeable(Helpers.USDS).safeTransfer(
            _receiver,
            usdsToSend
        );
    }

    /// @notice Sends available SPA in this contract to rewarder based on rewardPercentage and burns the rest
    function distributeAndBurnSPA() public {
        uint256 balance = ERC20BurnableUpgradeable(Helpers.SPA).balanceOf(
            address(this)
        );

        // Calculating the amount to reward based on rewardPercentage
        uint256 toReward = (balance * rewardPercentage) /
            Helpers.MAX_PERCENTAGE;

        // Remaining balance will be burned
        uint256 toBurn = balance - toReward;

        // Transferring SPA tokens
        ERC20BurnableUpgradeable(Helpers.SPA).safeTransfer(
            veSpaRewarder,
            toReward
        );
        emit SPARewarded(toReward);

        // Burning SPA tokens
        ERC20BurnableUpgradeable(Helpers.SPA).burn(toBurn);
        emit SPABurned(toBurn);
    }

    /// @notice Returns the amount of USDS for SPA amount in
    /// @param _spaIn Amount of SPA tokens
    /// @return Amount of USDs user will get
    function getUsdsOutForSpa(uint256 _spaIn) public view returns (uint256) {
        (uint256 usdsOut, ) = _getUsdsOutForSpa(_spaIn);
        return usdsOut;
    }

    /// @notice Returns the amount of USDS for SPA amount in
    /// @param _spaIn Amount of SPA tokens
    /// @return Amount of USDs user will get
    function _getUsdsOutForSpa(
        uint256 _spaIn
    ) private view returns (uint256, uint256) {
        Helpers._isNonZeroAmt(_spaIn);

        // Getting data from oracle
        (
            uint256 usdsPrice,
            uint256 spaPrice,
            uint256 usdsPricePrecision,
            uint256 spaPricePrecision
        ) = _getOracleData();

        // Calculates the total SPA value in USD
        uint256 totalSpaValue = (_spaIn * spaPrice) / spaPricePrecision;

        // Divides SPA Value by USDs price
        uint256 usdsOut = (totalSpaValue * usdsPricePrecision) / usdsPrice;

        return (usdsOut, spaPrice);
    }

    function _getOracleData()
        private
        view
        returns (uint256, uint256, uint256, uint256)
    {
        // Fetches the price for SPA and USDS from oracle
        IOracle.PriceData memory usdsData = IOracle(oracle).getPrice(
            Helpers.USDS
        );
        IOracle.PriceData memory spaData = IOracle(oracle).getPrice(
            Helpers.SPA
        );

        return (
            usdsData.price,
            spaData.price,
            usdsData.precision,
            spaData.precision
        );
    }

    function _isValidRewardPercentage(uint256 _rewardPercentage) private pure {
        Helpers._isNonZeroAmt(_rewardPercentage);
        Helpers._isLTEMaxPercentage(_rewardPercentage);
    }
}
