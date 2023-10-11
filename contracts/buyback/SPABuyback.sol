// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {ERC20BurnableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IOracle} from "../interfaces/IOracle.sol";
import {Helpers} from "../libraries/Helpers.sol";

/// @title SPABuyback of USDs Protocol
/// @notice This contract allows users to exchange SPA tokens for USDs tokens.
/// @dev Users can provide SPA tokens and receive USDs tokens in return based on the current exchange rate.
/// @dev A percentage of the provided SPA tokens are distributed as rewards, and the rest are burned.
/// @dev The contract is owned by an owner who can perform administrative functions.
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
    event RewardPercentageUpdated(uint256 newRewardPercentage);
    event VeSpaRewarderUpdated(address newVeSpaRewarder);
    event OracleUpdated(address newOracle);

    error CannotWithdrawSPA();
    error InsufficientUSDsBalance(uint256 toSend, uint256 bal);

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
    /// @dev Can only be called by the owner
    function withdraw(
        address _token,
        address _receiver,
        uint256 _amount
    ) external onlyOwner {
        Helpers._isNonZeroAddr(_token);
        Helpers._isNonZeroAddr(_receiver);
        Helpers._isNonZeroAmt(_amount);
        if (_token == Helpers.SPA) revert CannotWithdrawSPA();
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
        rewardPercentage = _newRewardPercentage;
        emit RewardPercentageUpdated(_newRewardPercentage);
    }

    /// @notice Update veSpaRewarder address
    /// @param _newVeSpaRewarder is the address of desired veSpaRewarder
    function updateVeSpaRewarder(address _newVeSpaRewarder) external onlyOwner {
        Helpers._isNonZeroAddr(_newVeSpaRewarder);
        veSpaRewarder = _newVeSpaRewarder;
        emit VeSpaRewarderUpdated(_newVeSpaRewarder);
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

        // Calculates spa amount required
        uint256 spaAmtRequired = (_usdsAmount * usdsPrice * spaPricePrecision) /
            (spaPrice * usdsPricePrecision);

        return spaAmtRequired;
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
        // Get quote based on current prices
        (uint256 usdsToSend, uint256 spaPrice) = _getUsdsOutForSpa(_spaIn);
        Helpers._isNonZeroAmt(usdsToSend, "SPA Amount too low");

        if (usdsToSend < _minUSDsOut)
            revert Helpers.MinSlippageError(usdsToSend, _minUSDsOut);

        uint256 usdsBal = ERC20BurnableUpgradeable(Helpers.USDS).balanceOf(
            address(this)
        );

        if (usdsToSend > usdsBal)
            revert InsufficientUSDsBalance(usdsToSend, usdsBal);

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

        // Transferring SPA tokens
        ERC20BurnableUpgradeable(Helpers.SPA).safeTransfer(
            veSpaRewarder,
            toReward
        );
        emit SPARewarded(toReward);

        // Remaining balance will be burned
        uint256 toBurn = balance - toReward;
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

        // Divides SPA Value by USDs price
        uint256 usdsOut = (_spaIn * spaPrice * usdsPricePrecision) /
            (usdsPrice * spaPricePrecision);

        return (usdsOut, spaPrice);
    }

    /// @dev Retrieves price data from the oracle contract for SPA and USDS tokens.
    /// @return The price of USDS in SPA, the price of SPA in USDS, and their respective precisions.
    function _getOracleData()
        private
        view
        returns (uint256, uint256, uint256, uint256)
    {
        // Fetches the price for SPA and USDS from the oracle contract
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

    /// @dev Checks if the provided reward percentage is valid.
    /// @param _rewardPercentage The reward percentage to validate.
    /// @dev The reward percentage must be a non-zero value and should not exceed the maximum percentage value.
    function _isValidRewardPercentage(uint256 _rewardPercentage) private pure {
        Helpers._isNonZeroAmt(_rewardPercentage);
        Helpers._isLTEMaxPercentage(_rewardPercentage);
    }
}
