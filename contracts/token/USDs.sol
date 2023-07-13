// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {SafeMathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import {AddressUpgradeable, OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {ERC20Upgradeable, ERC20PermitUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {StableMath} from "../libraries/StableMath.sol";
import {IUSDs} from "../interfaces/IUSDs.sol";

///  NOTE that this is an ERC20 token but the invariant that the sum of
///  balanceOf(x) for all x is not >= totalSupply(). This is a consequence of the
///  rebasing design. Any integrations with USDs should be aware.

/// @title USDs Token Contract on Arbitrum (L2)
/// @dev ERC20 compatible contract for USDs
/// @dev support rebase feature
/// @dev inspired by OUSD: https://github.com/OriginProtocol/origin-dollar/blob/master/contracts/contracts/token/OUSD.sol
/// @author Sperax Foundation
contract USDs is
    ERC20PermitUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    IUSDs
{
    using SafeMathUpgradeable for uint256;
    using StableMath for uint256;

    enum RebaseOptions {
        NotSet,
        OptOut,
        OptIn
    }

    uint256 private constant MAX_SUPPLY = ~uint128(0); // (2^128) - 1
    uint256 private constant RESOLUTION_INCREASE = 1e9;

    uint256 internal _totalSupply; // the total supply of USDs
    uint256[4] private unused1; // @note deprecated variables place holders
    mapping(address => mapping(address => uint256)) private _allowances;
    address public vaultAddress; // the address where (i) all collaterals of USDs protocol reside, e.g. USDT, USDC, ETH, etc and (ii) major actions like USDs minting are initiated
    // an user's balance of USDs is based on her balance of "credits."
    // in a rebase process, her USDs balance will change according to her credit balance and the rebase ratio
    mapping(address => uint256) private _creditBalances;
    uint256 private unused2; // @note deprecated variables place holders
    uint256 public rebasingCreditsPerToken; // the rebase ratio = num of credits / num of USDs
    // Frozen address/credits are non rebasing (value is held in contracts which
    // do not receive yield unless they explicitly opt in)
    uint256 public nonRebasingSupply; // num of USDs that are not affected by rebase
    // @note nonRebasingCreditsPerToken value is set as 1
    mapping(address => uint256) public nonRebasingCreditsPerToken; // the rebase ratio of non-rebasing accounts just before they opt out
    mapping(address => RebaseOptions) public rebaseState; // the rebase state of each account, i.e. opt in or opt out
    address[2] private unused3; // @note deprecated variables place holders
    mapping(address => bool) public isUpgraded;
    bool public paused;

    event TotalSupplyUpdated(
        uint256 totalSupply,
        uint256 rebasingCredits,
        uint256 rebasingCreditsPerToken
    );
    event AccountUpgraded(address account, bool isNonRebasing);
    event Paused(bool isPaused);

    /// @notice Verifies that the caller is the Savings Manager contract
    modifier onlyVault() {
        require(vaultAddress == msg.sender, "Caller is not the Vault");
        _;
    }

    constructor() {
        _disableInitializers();
    }

    /// @notice Mints new USDs tokens, increasing totalSupply.
    /// @param _account the account address the newly minted USDs will be attributed to
    /// @param _amount the amount of USDs that will be minted
    function mint(
        address _account,
        uint256 _amount
    ) external override onlyVault {
        _mint(_account, _amount);
    }

    /// @notice Burns tokens, decreasing totalSupply.
    function burn(uint256 amount) external override {
        _burn(msg.sender, amount);
    }

    /// @notice Add a contract address to the non rebasing exception list. I.e. the
    ///  address's balance will be part of rebases so the account will be exposed
    ///  to upside and downside.
    function rebaseOptIn(address toOptIn) external onlyOwner nonReentrant {
        if (!isUpgraded[toOptIn]) _upgradeAccount(toOptIn);
        require(_isNonRebasingAccount(toOptIn), "Account has not opted out");

        uint256 bal = _balanceOf(toOptIn);

        // Decreasing non rebasing supply
        nonRebasingSupply = nonRebasingSupply - bal;

        // convert the balance to credits
        _creditBalances[toOptIn] = bal.mulTruncateCeil(rebasingCreditsPerToken);

        rebaseState[toOptIn] = RebaseOptions.OptIn;

        // Delete any fixed credits per token
        delete nonRebasingCreditsPerToken[toOptIn];
    }

    /// @notice Remove a contract address to the non rebasing exception list.
    function rebaseOptOut(address toOptOut) external onlyOwner nonReentrant {
        if (!isUpgraded[toOptOut]) _upgradeAccount(toOptOut);
        require(!_isNonRebasingAccount(toOptOut), "Account has not opted in");

        uint256 bal = _balanceOf(toOptOut);
        // Increase non rebasing supply
        nonRebasingSupply = nonRebasingSupply + bal;

        // adjusting credits
        _creditBalances[toOptOut] = bal;

        // Set fixed credits per token
        nonRebasingCreditsPerToken[toOptOut] = 1;

        // Mark explicitly opted out of rebasing
        rebaseState[toOptOut] = RebaseOptions.OptOut;
    }

    /// @notice The rebase function. Modify the supply without minting new tokens. This uses a change in
    ///       the exchange rate between "credits" and USDs tokens to change balances.
    /// @param _rebaseAmt amount of USDs to rebase with.
    function rebase(
        uint256 _rebaseAmt
    ) external override onlyVault nonReentrant {
        uint256 prevTotalSupply = _totalSupply;

        _burn(msg.sender, _rebaseAmt);

        require(_totalSupply > 0, "Cannot increase 0 supply");

        // Compute the existing rebasing credits,
        uint256 rebasingCreds = (_totalSupply - nonRebasingSupply).mulTruncate(
            rebasingCreditsPerToken
        );

        // special case: if the total supply remains the same
        if (_totalSupply == prevTotalSupply) {
            emit TotalSupplyUpdated(
                _totalSupply,
                rebasingCreds,
                rebasingCreditsPerToken
            );
            return;
        }

        // check if the new total supply surpasses the MAX
        _totalSupply = prevTotalSupply > MAX_SUPPLY
            ? MAX_SUPPLY
            : prevTotalSupply;

        // calculate the new rebase ratio, i.e. credits per token
        rebasingCreditsPerToken = rebasingCreds.divPrecisely(
            _totalSupply - nonRebasingSupply
        );

        require(rebasingCreditsPerToken > 0, "Invalid change in supply");

        emit TotalSupplyUpdated(
            _totalSupply,
            rebasingCreds,
            rebasingCreditsPerToken
        );
    }

    /// @notice Upgrades accounts in bulk.
    /// @notice Only owner of the contract can call this.
    /// @param accounts Array of account addr to be upgraded.
    function upgradeAccounts(address[] calldata accounts) external onlyOwner {
        uint256 numAcc = accounts.length;
        for (uint256 i = 0; i < numAcc; ++i) {
            address account = accounts[i];
            if (account != address(0) && !isUpgraded[account])
                _upgradeAccount(account);
        }
    }

    /// @notice change the vault address
    /// @param newVault the new vault address
    function changeVault(address newVault) external onlyOwner {
        vaultAddress = newVault;
    }

    /// @notice Called by the owner to pause | unpause the contract
    /// @param _pause pauseSwitch state.
    function pauseSwitch(bool _pause) external onlyOwner {
        require(paused != _pause, "Already in required state");
        paused = _pause;
        emit Paused(_pause);
    }

    /// @notice Transfer tokens to a specified address.
    /// @param _to the address to transfer to.
    /// @param _value the _amount to be transferred.
    /// @return true on success.
    function transfer(
        address _to,
        uint256 _value
    ) public override returns (bool) {
        require(_to != address(0), "Transfer to zero address");
        require(
            _value <= balanceOf(msg.sender),
            "Transfer greater than balance"
        );

        _executeTransfer(msg.sender, _to, _value);

        emit Transfer(msg.sender, _to, _value);

        return true;
    }

    /// @notice Transfer tokens from one address to another.
    /// @param _from The address you want to send tokens from.
    /// @param _to The address you want to transfer to.
    /// @param _value The _amount of tokens to be transferred.
    function transferFrom(
        address _from,
        address _to,
        uint256 _value
    ) public override returns (bool) {
        require(_to != address(0), "Transfer to zero address");
        require(_value <= balanceOf(_from), "Transfer greater than balance");

        // notice: allowance balnce check depends on "sub" non-negative check
        _allowances[_from][msg.sender] =
            _allowances[_from][msg.sender] -
            _value;

        _executeTransfer(_from, _to, _value);

        emit Transfer(_from, _to, _value);

        return true;
    }

    /// @notice Approve the passed address to spend the specified _amount of tokens on behalf of
    ///  msg.sender. This method is included for ERC20 compatibility.
    ///  increaseAllowance and decreaseAllowance should be used instead.
    ///  Changing an allowance with this method brings the risk that someone may transfer both
    ///  the old and the new allowance - if they are both greater than zero - if a transfer
    ///  transaction is mined before the later approve() call is mined.
    /// @param _spender The address which will spend the funds.
    /// @param _value The _amount of tokens to be spent.
    function approve(
        address _spender,
        uint256 _value
    ) public override returns (bool) {
        _allowances[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);
        return true;
    }

    /// @notice Increase the _amount of tokens that an owner has allowed to a _spender.
    ///  This method should be used instead of approve() to avoid the double approval vulnerability
    ///  described above.
    /// @param _spender The address which will spend the funds.
    /// @param _addedValue The _amount of tokens to increase the allowance by.
    function increaseAllowance(
        address _spender,
        uint256 _addedValue
    ) public override returns (bool) {
        _allowances[msg.sender][_spender] =
            _allowances[msg.sender][_spender] +
            _addedValue;
        emit Approval(msg.sender, _spender, _allowances[msg.sender][_spender]);
        return true;
    }

    /// @notice Decrease the _amount of tokens that an owner has allowed to a _spender.
    /// @param _spender The address which will spend the funds.
    /// @param _subtractedValue The _amount of tokens to decrease the allowance by.
    function decreaseAllowance(
        address _spender,
        uint256 _subtractedValue
    ) public override returns (bool) {
        uint256 oldValue = _allowances[msg.sender][_spender];
        if (_subtractedValue >= oldValue) {
            _allowances[msg.sender][_spender] = 0;
        } else {
            _allowances[msg.sender][_spender] = oldValue - _subtractedValue;
        }
        emit Approval(msg.sender, _spender, _allowances[msg.sender][_spender]);
        return true;
    }

    /// @notice check the current total supply of USDs
    /// @return The total supply of USDs.
    function totalSupply()
        public
        view
        override(ERC20Upgradeable, IUSDs)
        returns (uint256)
    {
        return _totalSupply;
    }

    /// @notice Gets the USDs balance of the specified address.
    /// @param _account Address to query the balance of.
    /// @return A uint256 representing the _amount of base units owned by the
    ///          specified address.
    function balanceOf(
        address _account
    ) public view override returns (uint256) {
        if (!isUpgraded[_account]) {
            uint256 credits = _creditBalances[_account];
            if (credits == 0) return 0;
            return
                (credits * RESOLUTION_INCREASE).divPrecisely(
                    _creditsPerToken(_account)
                );
        }
        return _balanceOf(_account);
    }

    /// @notice Gets the credits balance of the specified address.
    /// @param _account The address to query the balance of.
    /// @return (uint256, uint256) Credit balance and credits per token of the
    ///          address
    function creditsBalanceOf(
        address _account
    ) public view returns (uint256, uint256) {
        if (!isUpgraded[_account]) {
            return (
                _creditBalances[_account] * RESOLUTION_INCREASE,
                _creditsPerToken(_account)
            );
        }
        return (_creditBalances[_account], _creditsPerToken(_account));
    }

    /// @notice Function to check the _amount of tokens that an owner has allowed to a _spender.
    /// @param _owner The address which owns the funds.
    /// @param _spender The address which will spend the funds.
    /// @return The number of tokens still available for the _spender.
    function allowance(
        address _owner,
        address _spender
    ) public view override returns (uint256) {
        return _allowances[_owner][_spender];
    }

    /// @notice Creates `_amount` tokens and assigns them to `_account`, increasing
    ///  the total supply.
    ///
    ///  Emits a {Transfer} event with `from` set to the zero address.
    ///
    ///  Requirements
    ///
    ///  - `to` cannot be the zero address.
    /// @param _account the account address the newly minted USDs will be attributed to
    /// @param _amount the amount of USDs that will be minted
    function _mint(
        address _account,
        uint256 _amount
    ) internal override nonReentrant {
        _isNotPaused();
        require(_account != address(0), "Mint to the zero address");
        if (!isUpgraded[_account]) _upgradeAccount(_account);

        // notice: If the account is non rebasing and doesn't have a set creditsPerToken
        //          then set it i.e. this is a mint from a fresh contract

        // update global stats
        if (_isNonRebasingAccount(_account)) {
            nonRebasingSupply = nonRebasingSupply + _amount;
            _creditBalances[_account] = _creditBalances[_account] + _amount;
        } else {
            uint256 creditAmount = _amount.mulTruncate(rebasingCreditsPerToken);
            _creditBalances[_account] =
                _creditBalances[_account] +
                creditAmount;
        }

        _totalSupply = _totalSupply + _amount;
        // totalMinted = totalMinted.add(_amount);

        require(_totalSupply < MAX_SUPPLY, "Max supply");

        emit Transfer(address(0), _account, _amount);
    }

    /// @notice Destroys `_amount` tokens from `_account`, reducing the
    ///  total supply.
    ///
    ///  Emits a {Transfer} event with `to` set to the zero address.
    ///
    ///  Requirements
    ///
    ///  - `_account` cannot be the zero address.
    ///  - `_account` must have at least `_amount` tokens.
    function _burn(
        address _account,
        uint256 _amount
    ) internal override nonReentrant {
        _isNotPaused();
        require(_account != address(0), "Burn from the zero address");
        if (!isUpgraded[_account]) _upgradeAccount(_account);
        if (_amount == 0) {
            return;
        }

        // Remove from the credit tallies and non-rebasing supply
        if (_isNonRebasingAccount(_account)) {
            nonRebasingSupply = nonRebasingSupply - _amount;
            _creditBalances[_account] = _creditBalances[_account] - _amount;
        } else {
            uint256 creditAmount = _amount.mulTruncate(rebasingCreditsPerToken);
            uint256 currentCredits = _creditBalances[_account];

            // Remove the credits, burning rounding errors
            if (
                currentCredits == creditAmount ||
                currentCredits - 1 == creditAmount
            ) {
                // Handle dust from rounding
                _creditBalances[_account] = 0;
            } else if (currentCredits > creditAmount) {
                _creditBalances[_account] =
                    _creditBalances[_account] -
                    creditAmount;
            } else {
                revert("Remove exceeds balance");
            }
        }

        _totalSupply = _totalSupply - _amount;
        emit Transfer(_account, address(0), _amount);
    }

    /// @notice Update the count of non rebasing credits in response to a transfer
    /// @param _from The address you want to send tokens from.
    /// @param _to The address you want to transfer to.
    /// @param _value Amount of USDs to transfer
    function _executeTransfer(
        address _from,
        address _to,
        uint256 _value
    ) private {
        _isNotPaused();
        if (!isUpgraded[_to]) _upgradeAccount(_to);
        if (!isUpgraded[_from]) _upgradeAccount(_from);

        bool isNonRebasingTo = _isNonRebasingAccount(_to);
        bool isNonRebasingFrom = _isNonRebasingAccount(_from);

        if (isNonRebasingFrom) {
            _creditBalances[_from] = _creditBalances[_from].sub(
                _value,
                "Transfer amount exceeds balance"
            );
            if (!isNonRebasingTo) {
                // Transfer to rebasing account from non-rebasing account
                // Decreasing non-rebasing credits by the amount that was sent
                nonRebasingSupply = nonRebasingSupply.sub(_value);
            }
        } else {
            uint256 creditsDeducted = _value.mulTruncate(
                rebasingCreditsPerToken
            );
            _creditBalances[_from] = _creditBalances[_from].sub(
                creditsDeducted,
                "Transfer amount exceeds balance"
            );
        }

        if (isNonRebasingTo) {
            _creditBalances[_to] = _creditBalances[_to] + _value;

            if (!isNonRebasingFrom) {
                // Transfer to non-rebasing account from rebasing account, credits
                // are removed from the non rebasing tally
                nonRebasingSupply = nonRebasingSupply + _value;
            }
        } else {
            // Credits deducted and credited might be different due to the
            // differing creditsPerToken used by each account
            uint256 creditsCredited = _value.mulTruncateCeil(
                rebasingCreditsPerToken
            );

            _creditBalances[_to] = _creditBalances[_to] + creditsCredited;
        }
    }

    /// @notice Upgrades an individual account
    /// @dev Ensure this function is called for a non upgraded account only!
    /// @param _account Address of the account.
    function _upgradeAccount(address _account) private {
        // Handle special for non-rebasing accounts
        uint256 nrc = nonRebasingCreditsPerToken[_account];
        uint256 credits = _creditBalances[_account];
        isUpgraded[_account] = true;
        if (nrc > 0) {
            // Update data for a nonRebasingAccount.
            // Credit balance now stores the actual balance of the account.
            _creditBalances[_account] = credits == 0
                ? 0
                : credits.divPrecisely(nrc);

            // nonRebasingCreditsPerToken now is just used to validate a nonRebasing acc.
            nonRebasingCreditsPerToken[_account] = 1;
            emit AccountUpgraded(_account, true);
            return;
        }
        if (credits > 0) {
            // Upgrade credit balance for a rebasing account.
            _creditBalances[_account] = credits.mul(RESOLUTION_INCREASE);
        }
        emit AccountUpgraded(_account, false);
    }

    /// @notice Is an account using rebasing accounting or non-rebasing accounting?
    ///       Also, ensure contracts are non-rebasing if they have not opted in.
    /// @param _account Address of the account.
    function _isNonRebasingAccount(address _account) private returns (bool) {
        bool isContract = AddressUpgradeable.isContract(_account);
        if (isContract && rebaseState[_account] == RebaseOptions.NotSet) {
            _ensureRebasingMigration(_account);
        }
        return nonRebasingCreditsPerToken[_account] > 0;
    }

    /// @notice Ensures internal account for rebasing and non-rebasing credits and
    ///       supply is updated following deployment of frozen yield change.
    function _ensureRebasingMigration(address _account) private {
        if (nonRebasingCreditsPerToken[_account] == 0) {
            if (_creditBalances[_account] != 0) {
                // Update non rebasing supply
                uint256 bal = _balanceOf(_account);
                nonRebasingSupply = nonRebasingSupply + bal;
                _creditBalances[_account] = bal;
            }
            nonRebasingCreditsPerToken[_account] = 1;
        }
    }

    /// @notice Calculates balance of account
    /// @dev Function assumes the _account is already upgraded.
    /// @param _account Address of the account.
    function _balanceOf(address _account) private view returns (uint256) {
        uint256 credits = _creditBalances[_account];
        if (credits > 0) {
            if (nonRebasingCreditsPerToken[_account] > 0) {
                return credits;
            }
            return credits.divPrecisely(rebasingCreditsPerToken);
        }
        return 0;
    }

    /// @notice Get the credits per token for an account. Returns a fixed amount
    ///       if the account is non-rebasing.
    /// @param _account Address of the account.
    function _creditsPerToken(address _account) private view returns (uint256) {
        uint256 nrc = nonRebasingCreditsPerToken[_account];
        if (nrc != 0) {
            if (!isUpgraded[_account]) {
                return nrc * RESOLUTION_INCREASE;
            }
            return nrc;
        } else {
            return rebasingCreditsPerToken;
        }
    }

    /// @notice Validates if the contract is not paused.
    function _isNotPaused() private view {
        require(!paused, "Contract paused");
    }
}
