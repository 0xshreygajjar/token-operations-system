// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "./AccessControl.sol";
import {IAllowList} from "./IAllowList.sol";

/// @notice Independently administered eligibility registry supplied to the token.
contract AllowList is AccessControl, IAllowList {
    bytes32 public constant REGISTRAR_ROLE = keccak256("REGISTRAR_ROLE");

    mapping(address account => bool) private _allowed;

    event Allowed(address indexed account);
    event Disallowed(address indexed account);

    constructor(address admin) {
        require(admin != address(0), "zero admin");
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(REGISTRAR_ROLE, admin);
    }

    function isAllowed(address account) external view returns (bool) {
        return _allowed[account];
    }

    function allow(address account) external onlyRole(REGISTRAR_ROLE) {
        _allowed[account] = true;
        emit Allowed(account);
    }

    function disallow(address account) external onlyRole(REGISTRAR_ROLE) {
        _allowed[account] = false;
        emit Disallowed(account);
    }
}
