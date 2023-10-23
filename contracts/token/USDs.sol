// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {SafeMathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import {
    AddressUpgradeable, OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {
    ERC20Upgradeable,
    ERC20PermitUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {StableMath} from "../libraries/StableMath.sol";
import {Helpers} from "../libraries/Helpers.sol";
import {IUSDs} from "../interfaces/IUSDs.sol";

///  NOTE that this is an ERC20 token but the invariant that the sum of
///  balanceOf(x) for all x is not >= totalSupply(). This is a consequence of the
///  rebasing design. Any integrations with USDs should be aware.

/// @title USDs Token Contract on Arbitrum (L2)
/// @dev ERC20 compatible contract for USDs
/// @dev support rebase feature
/// @dev inspired by OUSD: https://github.com/OriginProtocol/origin-dollar/blob/master/contracts/contracts/token/OUSD.sol
/// @author Sperax Foundation
contract USDs is ERC20PermitUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable, IUSDs {
    // @todo validate upgrade with Openzeppelin's upgradeValidation lib
    using SafeMathUpgradeable for uint256;
    using StableMath for uint256;

    enum RebaseOptions {
        NotSet,
        OptOut,
        OptIn
    }

    uint256 private constant MAX_SUPPLY = ~uint128(0); // (2^128) - 1
    // solhint-disable var-name-mixedcase
    uint256 internal _totalSupply; // the total supply of USDs
    uint256[4] private _deprecated_vars; // totalMinted, totalBurnt, mintedViaGateway, burntViaGateway
    mapping(address => mapping(address => uint256)) private _allowances;
    address public vault; // the address where (i) all collaterals of USDs protocol reside, e.g. USDT, USDC, ETH, etc and (ii) major actions like USDs minting are initiated
    // an user's balance of USDs is based on her balance of "credits."
    // in a rebase process, her USDs balance will change according to her credit balance and the rebase ratio
    mapping(address => uint256) private _creditBalances;
    uint256 private _deprecated_rebasingCredits;
    uint256 public rebasingCreditsPerToken; // the rebase ratio = num of credits / num of USDs
    // Frozen address/credits are non rebasing (value is held in contracts which
    // do not receive yield unless they explicitly opt in)
    uint256 public nonRebasingSupply; // num of USDs that are not affected by rebase
    // @note nonRebasingCreditsPerToken value is set as 1 for each account
    mapping(address => uint256) public nonRebasingCreditsPerToken; // the rebase ratio of non-rebasing accounts just before they opt out
    mapping(address => RebaseOptions) public rebaseState; // the rebase state of each account, i.e. opt in or opt out
    address[2] private _deprecated_gatewayAddr;
    mapping(address => bool) private _deprecated_isUpgraded;
    bool public paused;
    // solhint-enable var-name-mixedcase

    event TotalSupplyUpdated(uint256 totalSupply, uint256 rebasingCredits, uint256 rebasingCreditsPerToken);
    event Paused(bool isPaused);
    event VaultUpdated(address newVault);

    error CallerNotVault(address caller);
    error ContractPaused();
    error IsAlreadyRebasingAccount(address account);
    error IsAlreadyNonRebasingAccount(address account);
    error CannotIncreaseZeroSupply();
    error InvalidRebase();
    error TransferToZeroAddr();
    error TransferGreaterThanBal(uint256 val, uint256 bal);
    error MintToZeroAddr();
    error MaxSupplyReached(uint256 totalSupply);

    /// @notice Verifies that the caller is the Savings Manager contract
    modifier onlyVault() {
        if (msg.sender != vault) revert CallerNotVault(msg.sender);
        _;
    }

    constructor() {
        _disableInitializers();
    }

    /// @notice Mints new USDs tokens, increasing totalSupply.
    /// @param _account the account address the newly minted USDs will be attributed to
    /// @param _amount the amount of USDs that will be minted
    function mint(address _account, uint256 _amount) external override onlyVault nonReentrant {
        _mint(_account, _amount);
    }

    /// @notice Burns tokens, decreasing totalSupply.
    /// @param _amount amount to burn
    function burn(uint256 _amount) external override nonReentrant {
        _burn(msg.sender, _amount);
    }

    /// @notice Voluntary opt-in for rebase
    /// @dev Useful for smart-contract wallets
    function rebaseOptIn() external {
        _rebaseOptIn(msg.sender);
    }

    /// @notice Voluntary opt-out from rebase
    function rebaseOptOut() external {
        _rebaseOptOut(msg.sender);
    }

    /// @notice Adds `_account` to rebasing account list
    /// @param _account Address of the desired account
    function rebaseOptIn(address _account) external onlyOwner {
        _rebaseOptIn(_account);
    }

    /// @notice Adds `_account` to non-rebasing account list
    /// @param _account Address of the desired account
    function rebaseOptOut(address _account) external onlyOwner {
        _rebaseOptOut(_account);
    }

    /// @notice The rebase function. Modify the supply without minting new tokens. This uses a change in
    ///       the exchange rate between "credits" and USDs tokens to change balances.
    /// @param _rebaseAmt amount of USDs to rebase with.
    function rebase(uint256 _rebaseAmt) external override onlyVault nonReentrant {
        uint256 prevTotalSupply = _totalSupply;

        _burn(msg.sender, _rebaseAmt);

        if (_totalSupply == 0) revert CannotIncreaseZeroSupply();

        // Compute the existing rebasing credits,
        uint256 rebasingCredits = (_totalSupply - nonRebasingSupply).mulTruncate(rebasingCreditsPerToken);

        // special case: if the total supply remains the same
        if (_totalSupply == prevTotalSupply) {
            emit TotalSupplyUpdated(_totalSupply, rebasingCredits, rebasingCreditsPerToken);
            return;
        }

        // check if the new total supply surpasses the MAX
        _totalSupply = prevTotalSupply > MAX_SUPPLY ? MAX_SUPPLY : prevTotalSupply;

        // calculate the new rebase ratio, i.e. credits per token
        rebasingCreditsPerToken = rebasingCredits.divPrecisely(_totalSupply - nonRebasingSupply);

        if (rebasingCreditsPerToken == 0) revert InvalidRebase();

        emit TotalSupplyUpdated(_totalSupply, rebasingCredits, rebasingCreditsPerToken);
    }

    /// @notice change the vault address
    /// @param _newVault the new vault address
    function updateVault(address _newVault) external onlyOwner {
        Helpers._isNonZeroAddr(_newVault);
        vault = _newVault;
        emit VaultUpdated(_newVault);
    }

    /// @notice Called by the owner to pause | unpause the contract
    /// @param _pause pauseSwitch state.
    function pauseSwitch(bool _pause) external onlyOwner {
        paused = _pause;
        emit Paused(_pause);
    }

    /// @notice Transfer tokens to a specified address.
    /// @param _to the address to transfer to.
    /// @param _value the _amount to be transferred.
    /// @return true on success.
    function transfer(address _to, uint256 _value) public override returns (bool) {
        if (_to == address(0)) revert TransferToZeroAddr();
        uint256 bal = balanceOf(msg.sender);
        if (_value > bal) revert TransferGreaterThanBal(_value, bal);

        _executeTransfer(msg.sender, _to, _value);

        emit Transfer(msg.sender, _to, _value);

        return true;
    }

    /// @notice Transfer tokens from one address to another.
    /// @param _from The address you want to send tokens from.
    /// @param _to The address you want to transfer to.
    /// @param _value The _amount of tokens to be transferred.
    /// @return true on success.
    function transferFrom(address _from, address _to, uint256 _value) public override returns (bool) {
        if (_to == address(0)) revert TransferToZeroAddr();
        uint256 bal = balanceOf(_from);
        if (_value > bal) revert TransferGreaterThanBal(_value, bal);

        // notice: allowance balance check depends on "sub" non-negative check

        _allowances[_from][msg.sender] = _allowances[_from][msg.sender].sub(_value, "Insufficient allowance");

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
    /// @return true on success.
    function approve(address _spender, uint256 _value) public override returns (bool) {
        _allowances[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);
        return true;
    }

    /// @notice Increase the _amount of tokens that an owner has allowed to a _spender.
    ///  This method should be used instead of approve() to avoid the double approval vulnerability
    ///  described above.
    /// @param _spender The address which will spend the funds.
    /// @param _addedValue The _amount of tokens to increase the allowance by.
    /// @return true on success.
    function increaseAllowance(address _spender, uint256 _addedValue) public override returns (bool) {
        _allowances[msg.sender][_spender] = _allowances[msg.sender][_spender] + _addedValue;
        emit Approval(msg.sender, _spender, _allowances[msg.sender][_spender]);
        return true;
    }

    /// @notice Decrease the _amount of tokens that an owner has allowed to a _spender.
    /// @param _spender The address which will spend the funds.
    /// @param _subtractedValue The _amount of tokens to decrease the allowance by.
    /// @return true on success.
    function decreaseAllowance(address _spender, uint256 _subtractedValue) public override returns (bool) {
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
    function totalSupply() public view override(ERC20Upgradeable, IUSDs) returns (uint256) {
        return _totalSupply;
    }

    /// @notice Gets the USDs balance of the specified address.
    /// @param _account Address to query the balance of.
    /// @return A uint256 representing the _amount of base units owned by the
    ///          specified address.
    function balanceOf(address _account) public view override returns (uint256) {
        return _balanceOf(_account);
    }

    /// @notice Gets the credits balance of the specified address.
    /// @param _account The address to query the balance of.
    /// @return (uint256, uint256) Credit balance and credits per token of the
    ///          address
    function creditsBalanceOf(address _account) public view returns (uint256, uint256) {
        return (_creditBalances[_account], _creditsPerToken(_account));
    }

    /// @notice Function to check the _amount of tokens that an owner has allowed to a _spender.
    /// @param _owner The address which owns the funds.
    /// @param _spender The address which will spend the funds.
    /// @return The number of tokens still available for the _spender.
    function allowance(address _owner, address _spender) public view override returns (uint256) {
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
    function _mint(address _account, uint256 _amount) internal override {
        _isNotPaused();
        if (_account == address(0)) revert MintToZeroAddr();

        // notice: If the account is non rebasing and doesn't have a set creditsPerToken
        //          then set it i.e. this is a mint from a fresh contract
        // creditAmount for non-rebasing accounts = _amount
        uint256 creditAmount = _amount;

        // update global stats
        if (_isNonRebasingAccount(_account)) {
            nonRebasingSupply = nonRebasingSupply + _amount;
        } else {
            creditAmount = _amount.mulTruncate(rebasingCreditsPerToken);
        }
        // update credit balance for the account
        _creditBalances[_account] = _creditBalances[_account] + creditAmount;

        _totalSupply = _totalSupply + _amount;

        if (_totalSupply > MAX_SUPPLY) revert MaxSupplyReached(_totalSupply);

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
    function _burn(address _account, uint256 _amount) internal override {
        _isNotPaused();
        if (_amount == 0) {
            return;
        }
        /// For non-rebasing accounts credit amount = _amount
        uint256 creditAmount = _amount;

        // Remove from the credit tallies and non-rebasing supply
        if (_isNonRebasingAccount(_account)) {
            nonRebasingSupply = nonRebasingSupply - _amount;
        } else {
            creditAmount = _amount.mulTruncate(rebasingCreditsPerToken);
        }

        _creditBalances[_account] = _creditBalances[_account].sub(creditAmount, "Insufficient balance");

        _totalSupply = _totalSupply - _amount;
        emit Transfer(_account, address(0), _amount);
    }

    /// @notice Update the count of non rebasing credits in response to a transfer
    /// @param _from The address you want to send tokens from.
    /// @param _to The address you want to transfer to.
    /// @param _value Amount of USDs to transfer
    function _executeTransfer(address _from, address _to, uint256 _value) private {
        _isNotPaused();
        bool isNonRebasingTo = _isNonRebasingAccount(_to);
        bool isNonRebasingFrom = _isNonRebasingAccount(_from);
        uint256 creditAmount = _value.mulTruncate(rebasingCreditsPerToken);

        if (isNonRebasingFrom) {
            _creditBalances[_from] = _creditBalances[_from].sub(_value, "Transfer amount exceeds balance");
            if (!isNonRebasingTo) {
                // Transfer to rebasing account from non-rebasing account
                // Decreasing non-rebasing supply by the amount that was sent
                nonRebasingSupply = nonRebasingSupply.sub(_value);
            }
        } else {
            // updating credit balance for rebasing account
            _creditBalances[_from] = _creditBalances[_from].sub(creditAmount, "Transfer amount exceeds balance");
        }

        if (isNonRebasingTo) {
            _creditBalances[_to] = _creditBalances[_to] + _value;

            if (!isNonRebasingFrom) {
                // Transfer to non-rebasing account from rebasing account,
                // Increasing non-rebasing supply by the amount that was sent
                nonRebasingSupply = nonRebasingSupply + _value;
            }
        } else {
            // updating credit balance for rebasing account
            _creditBalances[_to] = _creditBalances[_to] + creditAmount;
        }
    }

    /// @notice Add a contract address to the non rebasing exception list. I.e. the
    ///  address's balance will be part of rebases so the account will be exposed
    ///  to upside and downside.
    function _rebaseOptIn(address _account) private {
        if (!_isNonRebasingAccount(_account)) {
            revert IsAlreadyRebasingAccount(_account);
        }

        uint256 bal = _balanceOf(_account);

        // Decreasing non rebasing supply
        nonRebasingSupply = nonRebasingSupply - bal;

        // convert the balance to credits
        _creditBalances[_account] = bal.mulTruncate(rebasingCreditsPerToken);

        rebaseState[_account] = RebaseOptions.OptIn;

        // Delete any fixed credits per token
        delete nonRebasingCreditsPerToken[_account];
    }

    /// @notice Remove a contract address to the non rebasing exception list.
    function _rebaseOptOut(address _account) private {
        if (_isNonRebasingAccount(_account)) {
            revert IsAlreadyNonRebasingAccount(_account);
        }

        uint256 bal = _balanceOf(_account);
        // Increase non rebasing supply
        nonRebasingSupply = nonRebasingSupply + bal;

        // adjusting credits
        _creditBalances[_account] = bal;

        // Set fixed credits per token
        nonRebasingCreditsPerToken[_account] = 1;

        // Mark explicitly opted out of rebasing
        rebaseState[_account] = RebaseOptions.OptOut;
    }

    /// @notice Is an account using rebasing accounting or non-rebasing accounting?
    ///       Also, ensure contracts are non-rebasing if they have not opted in.
    /// @param _account Address of the account.
    function _isNonRebasingAccount(address _account) private returns (bool) {
        bool isContract = AddressUpgradeable.isContract(_account);
        if (isContract && rebaseState[_account] == RebaseOptions.NotSet) {
            _ensureNonRebasingMigration(_account);
            return true;
        }
        return nonRebasingCreditsPerToken[_account] != 0;
    }

    /// @notice Ensures internal account for rebasing and non-rebasing credits and
    ///       supply is updated following deployment of frozen yield change.
    /// @param _account Address of the account.
    function _ensureNonRebasingMigration(address _account) private {
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
        if (credits != 0) {
            if (nonRebasingCreditsPerToken[_account] != 0) {
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
            return nrc;
        } else {
            return rebasingCreditsPerToken;
        }
    }

    /// @notice Validates if the contract is not paused.
    function _isNotPaused() private view {
        if (paused) revert ContractPaused();
    }
}
