// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "./AccessControl.sol";
import {ERC20Base} from "./ERC20Base.sol";
import {IAllowList} from "./IAllowList.sol";

/// @title SecurityToken
/// @notice Permissioned fund shares.
/// @dev Every public balance route (transfer, transferFrom, mint, burn, recover) enforces its policy
///      explicitly before reaching ERC20Base._update, which is never overridden. Checks run before any
///      state change, so every rejection reverts with no partial effect.
contract SecurityToken is ERC20Base, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant AGENT_ROLE = keccak256("AGENT_ROLE");

    IAllowList public allowlist;
    mapping(address account => bool) public frozen;
    bool public paused;
    mapping(bytes32 caseId => bool) public recoveryUsed;

    event RecoveryExecuted(bytes32 indexed caseId, address indexed from, address indexed to, uint256 amount);

    constructor(address allowlist_) ERC20Base("Fund Share", "FUND") {
        require(allowlist_ != address(0), "zero allowlist");
        allowlist = IAllowList(allowlist_);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        _requireOrdinaryMove(msg.sender, to);
        return super.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        _requireOrdinaryMove(from, to);
        return super.transferFrom(from, to, amount);
    }

    function setAllowlist(address nextAllowlist) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(nextAllowlist != address(0), "zero allowlist");
        allowlist = IAllowList(nextAllowlist);
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        require(!paused, "token paused");
        _requireActiveWallet(to);
        _mint(to, amount);
    }

    /// @dev Redemption stays available while paused.
    function burn(address from, uint256 amount) external onlyRole(AGENT_ROLE) {
        _requireActiveWallet(from);
        _burn(from, amount);
    }

    /// @notice Moves an existing position under a one-time case ID. The source may be held or
    ///         ineligible; the destination must be eligible and not held. Allowed while paused.
    function recover(bytes32 caseId, address from, address to, uint256 amount) external onlyRole(AGENT_ROLE) {
        require(caseId != bytes32(0), "zero case");
        require(!recoveryUsed[caseId], "case used");
        require(amount > 0, "zero amount");
        require(from != address(0), "zero source");
        require(from != to, "same wallet");
        _requireActiveWallet(to);

        recoveryUsed[caseId] = true;
        // Reverts on insufficient balance, which also rolls back the case marker above.
        _update(from, to, amount);
        emit RecoveryExecuted(caseId, from, to, amount);
    }

    function freeze(address account) external onlyRole(AGENT_ROLE) {
        frozen[account] = true;
    }

    function unfreeze(address account) external onlyRole(AGENT_ROLE) {
        frozen[account] = false;
    }

    function pause() external onlyRole(AGENT_ROLE) {
        paused = true;
    }

    function unpause() external onlyRole(AGENT_ROLE) {
        paused = false;
    }

    function _requireOrdinaryMove(address from, address to) private view {
        require(!paused, "token paused");
        _requireActiveWallet(from);
        _requireActiveWallet(to);
    }

    /// @dev A real, currently eligible, unheld wallet.
    function _requireActiveWallet(address account) private view {
        require(account != address(0), "zero address");
        require(!frozen[account], "wallet held");
        require(allowlist.isAllowed(account), "wallet not allowed");
    }
}
