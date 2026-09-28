// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AllowList} from "../src/AllowList.sol";
import {SecurityToken} from "../src/SecurityToken.sol";
import {TestBase} from "./TestBase.sol";

/// @dev Extra cheatcodes not exposed by the supplied TestBase.
interface VmLogs {
    struct Log {
        bytes32[] topics;
        bytes data;
        address emitter;
    }

    function recordLogs() external;
    function getRecordedLogs() external returns (Log[] memory);
}

/// @notice Behavioural acceptance tests for TOK-01 .. TOK-07.
/// @dev Negative tests pair each rejection with a control showing the same call succeeds once the
///      single violated condition is lifted, so a revert for an unrelated reason cannot pass them.
contract SecurityTokenPolicyTest is TestBase {
    VmLogs private constant vmLogs = VmLogs(address(vm));

    bytes32 private constant TRANSFER_SIG = keccak256("Transfer(address,address,uint256)");
    bytes32 private constant RECOVERY_SIG = keccak256("RecoveryExecuted(bytes32,address,address,uint256)");
    bytes32 private constant CASE_A = keccak256("case-A");
    bytes32 private constant CASE_B = keccak256("case-B");

    address private constant MINTER = address(0x111);
    address private constant AGENT = address(0x222);
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant CAROL = address(0xCA201);
    address private constant SPENDER = address(0x5BE7D);

    SecurityToken private token;
    AllowList private allowlist;
    bytes32 private minterRole;
    bytes32 private agentRole;

    function setUp() public {
        allowlist = new AllowList(address(this));
        token = new SecurityToken(address(allowlist));
        minterRole = token.MINTER_ROLE();
        agentRole = token.AGENT_ROLE();
        token.grantRole(minterRole, MINTER);
        token.grantRole(agentRole, AGENT);
        allowlist.allow(ALICE);
        allowlist.allow(BOB);
        allowlist.allow(CAROL);

        vm.prank(MINTER);
        token.mint(ALICE, 100);
    }

    // ------------------------------------------------------------------ helpers

    function _freeze(address account) private {
        vm.prank(AGENT);
        token.freeze(account);
    }

    function _unfreeze(address account) private {
        vm.prank(AGENT);
        token.unfreeze(account);
    }

    function _pause() private {
        vm.prank(AGENT);
        token.pause();
    }

    function _approveSpender(uint256 amount) private {
        vm.prank(ALICE);
        token.approve(SPENDER, amount);
    }

    function _assertPositions(uint256 alice, uint256 bob, uint256 supply) private view {
        assertEq(token.balanceOf(ALICE), alice);
        assertEq(token.balanceOf(BOB), bob);
        assertEq(token.totalSupply(), supply);
    }

    // ------------------------------------------------------------------ TOK-01 current eligibility

    function test_TOK01_revokedSenderCannotTransfer() public {
        allowlist.disallow(ALICE);
        vm.expectRevert();
        vm.prank(ALICE);
        token.transfer(BOB, 1);
        _assertPositions(100, 0, 100);

        allowlist.allow(ALICE);
        vm.prank(ALICE);
        token.transfer(BOB, 1);
        _assertPositions(99, 1, 100);
    }

    function test_TOK01_revokedRecipientCannotReceiveTransfer() public {
        allowlist.disallow(BOB);
        vm.expectRevert();
        vm.prank(ALICE);
        token.transfer(BOB, 1);
        _assertPositions(100, 0, 100);
    }

    function test_TOK01_revokedOwnerCannotSendThroughTransferFrom() public {
        _approveSpender(50);
        allowlist.disallow(ALICE);
        vm.expectRevert();
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 10);
        _assertPositions(100, 0, 100);
        assertEq(token.allowance(ALICE, SPENDER), 50);

        allowlist.allow(ALICE);
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 10);
        _assertPositions(90, 10, 100);
    }

    function test_TOK01_revokedRecipientCannotReceiveThroughTransferFrom() public {
        _approveSpender(50);
        allowlist.disallow(BOB);
        vm.expectRevert();
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 10);
        _assertPositions(100, 0, 100);
    }

    function test_TOK01_issuanceRequiresEligibleDestination() public {
        address outsider = address(0xBAD);
        vm.expectRevert();
        vm.prank(MINTER);
        token.mint(outsider, 5);
        assertEq(token.balanceOf(outsider), 0);
        assertEq(token.totalSupply(), 100);
    }

    function test_TOK01_redemptionRequiresEligibleSource() public {
        allowlist.disallow(ALICE);
        vm.expectRevert();
        vm.prank(AGENT);
        token.burn(ALICE, 10);
        _assertPositions(100, 0, 100);

        allowlist.allow(ALICE);
        vm.prank(AGENT);
        token.burn(ALICE, 10);
        _assertPositions(90, 0, 90);
    }

    // ------------------------------------------------------------------ TOK-02 operational holds

    function test_TOK02_heldRecipientCannotReceiveTransfer() public {
        _freeze(BOB);
        vm.expectRevert();
        vm.prank(ALICE);
        token.transfer(BOB, 1);
        _assertPositions(100, 0, 100);
    }

    function test_TOK02_heldOwnerCannotSendThroughTransferFrom() public {
        _approveSpender(50);
        _freeze(ALICE);
        vm.expectRevert();
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 10);
        _assertPositions(100, 0, 100);
        assertEq(token.allowance(ALICE, SPENDER), 50);

        _unfreeze(ALICE);
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 10);
        _assertPositions(90, 10, 100);
    }

    function test_TOK02_heldRecipientCannotReceiveThroughTransferFrom() public {
        _approveSpender(50);
        _freeze(BOB);
        vm.expectRevert();
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 10);
        _assertPositions(100, 0, 100);
    }

    function test_TOK02_issuanceToHeldWalletRejected() public {
        _freeze(BOB);
        vm.expectRevert();
        vm.prank(MINTER);
        token.mint(BOB, 5);
        _assertPositions(100, 0, 100);

        _unfreeze(BOB);
        vm.prank(MINTER);
        token.mint(BOB, 5);
        _assertPositions(100, 5, 105);
    }

    function test_TOK02_redemptionFromHeldWalletRejected() public {
        _freeze(ALICE);
        vm.expectRevert();
        vm.prank(AGENT);
        token.burn(ALICE, 10);
        _assertPositions(100, 0, 100);
    }

    function test_TOK02_holdAndAllowlistAreIndependent() public {
        // Held but still allowlisted: rejected.
        _freeze(ALICE);
        assertTrue(allowlist.isAllowed(ALICE));
        vm.expectRevert();
        vm.prank(ALICE);
        token.transfer(BOB, 1);

        // Released from hold but revoked: still rejected.
        _unfreeze(ALICE);
        allowlist.disallow(ALICE);
        assertTrue(!token.frozen(ALICE));
        vm.expectRevert();
        vm.prank(ALICE);
        token.transfer(BOB, 1);

        // Both controls satisfied: accepted.
        allowlist.allow(ALICE);
        vm.prank(ALICE);
        token.transfer(BOB, 1);
        _assertPositions(99, 1, 100);
    }

    // ------------------------------------------------------------------ TOK-03 register halt

    function test_TOK03_pauseBlocksTransferFrom() public {
        _approveSpender(50);
        _pause();
        vm.expectRevert();
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 10);
        _assertPositions(100, 0, 100);
        assertEq(token.allowance(ALICE, SPENDER), 50);
    }

    function test_TOK03_pauseBlocksIssuance() public {
        _pause();
        vm.expectRevert();
        vm.prank(MINTER);
        token.mint(BOB, 5);
        _assertPositions(100, 0, 100);
    }

    function test_TOK03_redemptionAvailableWhilePaused() public {
        _pause();
        vm.prank(AGENT);
        token.burn(ALICE, 40);
        _assertPositions(60, 0, 60);
    }

    function test_TOK03_recoveryAvailableWhilePaused() public {
        _pause();
        vm.prank(AGENT);
        token.recover(CASE_A, ALICE, BOB, 40);
        _assertPositions(60, 40, 100);
    }

    function test_TOK03_unpauseDoesNotRestoreOtherwiseInvalidOperations() public {
        _freeze(ALICE);
        _pause();
        vm.prank(AGENT);
        token.unpause();

        vm.expectRevert();
        vm.prank(ALICE);
        token.transfer(BOB, 1);
        _assertPositions(100, 0, 100);
    }

    // ------------------------------------------------------------------ TOK-04 case-tracked recovery

    function test_TOK04_recoversHeldIneligiblePositionAndEmitsEvents() public {
        _freeze(ALICE);
        allowlist.disallow(ALICE);
        assertTrue(!token.recoveryUsed(CASE_A));

        vmLogs.recordLogs();
        vm.prank(AGENT);
        token.recover(CASE_A, ALICE, BOB, 70);
        VmLogs.Log[] memory logs = vmLogs.getRecordedLogs();

        _assertPositions(30, 70, 100);
        assertTrue(token.recoveryUsed(CASE_A));

        uint256 transfers;
        uint256 recoveries;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter != address(token)) continue;
            bytes32 sig = logs[i].topics[0];
            if (sig == TRANSFER_SIG) {
                transfers++;
                assertTrue(logs[i].topics[1] == bytes32(uint256(uint160(ALICE))));
                assertTrue(logs[i].topics[2] == bytes32(uint256(uint160(BOB))));
                assertEq(abi.decode(logs[i].data, (uint256)), 70);
            } else if (sig == RECOVERY_SIG) {
                recoveries++;
                assertTrue(logs[i].topics[1] == CASE_A);
                assertTrue(logs[i].topics[2] == bytes32(uint256(uint160(ALICE))));
                assertTrue(logs[i].topics[3] == bytes32(uint256(uint160(BOB))));
                assertEq(abi.decode(logs[i].data, (uint256)), 70);
            }
        }
        assertEq(transfers, 1);
        assertEq(recoveries, 1);
    }

    function test_TOK04_usedCaseIsRejectedForAnyLaterCall() public {
        vm.prank(AGENT);
        token.recover(CASE_A, ALICE, BOB, 10);

        // Same case, different parameters that would otherwise be valid.
        vm.expectRevert();
        vm.prank(AGENT);
        token.recover(CASE_A, BOB, CAROL, 5);
        vm.expectRevert();
        vm.prank(AGENT);
        token.recover(CASE_A, ALICE, BOB, 10);
        _assertPositions(90, 10, 100);

        vm.prank(AGENT);
        token.recover(CASE_B, BOB, CAROL, 5);
        assertEq(token.balanceOf(CAROL), 5);
    }

    function test_TOK04_onlyAgentMayRecover() public {
        address[3] memory callers = [address(this), MINTER, ALICE];
        for (uint256 i = 0; i < callers.length; i++) {
            vm.expectRevert();
            vm.prank(callers[i]);
            token.recover(CASE_A, ALICE, BOB, 10);
        }
        _assertPositions(100, 0, 100);
        assertTrue(!token.recoveryUsed(CASE_A));
    }

    function test_TOK04_rejectsZeroCaseAndZeroAmount() public {
        vm.expectRevert();
        vm.prank(AGENT);
        token.recover(bytes32(0), ALICE, BOB, 10);
        assertTrue(!token.recoveryUsed(bytes32(0)));

        vm.expectRevert();
        vm.prank(AGENT);
        token.recover(CASE_A, ALICE, BOB, 0);
        assertTrue(!token.recoveryUsed(CASE_A));
        _assertPositions(100, 0, 100);
    }

    function test_TOK04_rejectsSameSourceAndDestination() public {
        vm.expectRevert();
        vm.prank(AGENT);
        token.recover(CASE_A, ALICE, ALICE, 10);
        assertTrue(!token.recoveryUsed(CASE_A));
        _assertPositions(100, 0, 100);
    }

    function test_TOK04_destinationMustBeEligibleAndNotHeld() public {
        allowlist.disallow(BOB);
        vm.expectRevert();
        vm.prank(AGENT);
        token.recover(CASE_A, ALICE, BOB, 10);

        allowlist.allow(BOB);
        _freeze(BOB);
        vm.expectRevert();
        vm.prank(AGENT);
        token.recover(CASE_A, ALICE, BOB, 10);
        _assertPositions(100, 0, 100);
        assertTrue(!token.recoveryUsed(CASE_A));

        _unfreeze(BOB);
        vm.prank(AGENT);
        token.recover(CASE_A, ALICE, BOB, 10);
        _assertPositions(90, 10, 100);
    }

    function test_TOK04_failedRecoveryDoesNotConsumeCase() public {
        vm.expectRevert();
        vm.prank(AGENT);
        token.recover(CASE_A, ALICE, BOB, 101); // insufficient balance
        assertTrue(!token.recoveryUsed(CASE_A));
        _assertPositions(100, 0, 100);

        vm.prank(AGENT);
        token.recover(CASE_A, ALICE, BOB, 100);
        assertTrue(token.recoveryUsed(CASE_A));
        _assertPositions(0, 100, 100);
    }

    // ------------------------------------------------------------------ TOK-05 supply and zero address

    function test_TOK05_holderCannotBurnByTransferToZero() public {
        vm.expectRevert();
        vm.prank(ALICE);
        token.transfer(address(0), 40);
        _assertPositions(100, 0, 100);
    }

    function test_TOK05_spenderCannotBurnByTransferFromToZero() public {
        _approveSpender(type(uint256).max);
        vm.expectRevert();
        vm.prank(SPENDER);
        token.transferFrom(ALICE, address(0), 40);
        _assertPositions(100, 0, 100);
    }

    function test_TOK05_transferFromZeroSourceRejected() public {
        vm.expectRevert();
        vm.prank(SPENDER);
        token.transferFrom(address(0), BOB, 0);
        _assertPositions(100, 0, 100);
    }

    function test_TOK05_recoveryRejectsZeroEndpoints() public {
        vm.expectRevert();
        vm.prank(AGENT);
        token.recover(CASE_A, ALICE, address(0), 10);
        vm.expectRevert();
        vm.prank(AGENT);
        token.recover(CASE_A, address(0), BOB, 10);
        _assertPositions(100, 0, 100);
        assertTrue(!token.recoveryUsed(CASE_A));
    }

    function test_TOK05_onlyMinterIncreasesAndOnlyAgentDecreasesSupply() public {
        address[3] memory nonMinters = [address(this), AGENT, ALICE];
        for (uint256 i = 0; i < nonMinters.length; i++) {
            vm.expectRevert();
            vm.prank(nonMinters[i]);
            token.mint(BOB, 1);
        }
        address[3] memory nonAgents = [address(this), MINTER, ALICE];
        for (uint256 i = 0; i < nonAgents.length; i++) {
            vm.expectRevert();
            vm.prank(nonAgents[i]);
            token.burn(ALICE, 1);
        }
        _assertPositions(100, 0, 100);
    }

    function testFuzz_TOK05_recoveryPreservesSupply(uint256 minted, uint256 moved) public {
        minted = minted % (type(uint256).max - 100) + 1;
        moved = moved % minted + 1;
        vm.prank(MINTER);
        token.mint(BOB, minted);
        uint256 supply = token.totalSupply();

        vm.prank(AGENT);
        token.recover(CASE_A, BOB, CAROL, moved);

        assertEq(token.totalSupply(), supply);
        assertEq(token.balanceOf(BOB), minted - moved);
        assertEq(token.balanceOf(CAROL), moved);
    }

    // ------------------------------------------------------------------ TOK-06 authority and administration

    function test_TOK06_deploymentGrantsOnlyAdminRole() public {
        SecurityToken fresh = new SecurityToken(address(allowlist));
        assertTrue(fresh.hasRole(fresh.DEFAULT_ADMIN_ROLE(), address(this)));
        assertTrue(!fresh.hasRole(minterRole, address(this)));
        assertTrue(!fresh.hasRole(agentRole, address(this)));

        vm.expectRevert();
        fresh.mint(ALICE, 1);
        assertEq(fresh.totalSupply(), 0);
    }

    function test_TOK06_deploymentRejectsZeroAllowlist() public {
        vm.expectRevert();
        new SecurityToken(address(0));
    }

    function test_TOK06_allowlistReplacementIsAdminOnlyAndNonZero() public {
        AllowList replacement = new AllowList(address(this));
        replacement.allow(ALICE);

        vm.expectRevert();
        token.setAllowlist(address(0));
        assertTrue(address(token.allowlist()) == address(allowlist));

        address[2] memory nonAdmins = [AGENT, MINTER];
        for (uint256 i = 0; i < nonAdmins.length; i++) {
            vm.expectRevert();
            vm.prank(nonAdmins[i]);
            token.setAllowlist(address(replacement));
        }
        assertTrue(address(token.allowlist()) == address(allowlist));

        token.setAllowlist(address(replacement));
        assertTrue(address(token.allowlist()) == address(replacement));
        // BOB is not on the replacement list, so the new registry governs immediately.
        vm.expectRevert();
        vm.prank(ALICE);
        token.transfer(BOB, 1);
    }

    function test_TOK06_roleAdministrationIsAdminOnly() public {
        vm.expectRevert();
        vm.prank(AGENT);
        token.grantRole(minterRole, ALICE);
        assertTrue(!token.hasRole(minterRole, ALICE));

        vm.expectRevert();
        vm.prank(MINTER);
        token.revokeRole(agentRole, AGENT);
        assertTrue(token.hasRole(agentRole, AGENT));

        token.revokeRole(agentRole, AGENT);
        assertTrue(!token.hasRole(agentRole, AGENT));
    }

    function test_TOK06_holdsAndHaltsAreAgentPowers() public {
        address[3] memory nonAgents = [address(this), MINTER, ALICE];
        for (uint256 i = 0; i < nonAgents.length; i++) {
            vm.expectRevert();
            vm.prank(nonAgents[i]);
            token.freeze(BOB);
            vm.expectRevert();
            vm.prank(nonAgents[i]);
            token.pause();
        }
        assertTrue(!token.frozen(BOB));
        assertTrue(!token.paused());

        _pause();
        for (uint256 i = 0; i < nonAgents.length; i++) {
            vm.expectRevert();
            vm.prank(nonAgents[i]);
            token.unpause();
        }
        assertTrue(token.paused());
    }

    // ------------------------------------------------------------------ TOK-07 route consistency and atomicity

    function test_TOK07_rejectedTransferFromDoesNotSpendAllowance() public {
        _approveSpender(30);
        allowlist.disallow(BOB);
        vm.expectRevert();
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 30);
        assertEq(token.allowance(ALICE, SPENDER), 30);
        _assertPositions(100, 0, 100);
    }

    function test_TOK07_unlimitedAllowanceDoesNotBypassPolicy() public {
        _approveSpender(type(uint256).max);
        address outsider = address(0xBAD);
        vm.expectRevert();
        vm.prank(SPENDER);
        token.transferFrom(ALICE, outsider, 1);
        assertEq(token.balanceOf(outsider), 0);

        _pause();
        vm.expectRevert();
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 1);
        _assertPositions(100, 0, 100);
    }

    function test_TOK07_rejectedOperationsLeaveNoTrace() public {
        _approveSpender(50);
        _freeze(BOB);

        vmLogs.recordLogs();
        vm.prank(ALICE);
        (bool ok,) = address(token).call(abi.encodeCall(SecurityToken.transfer, (BOB, 1)));
        assertTrue(!ok);
        vm.prank(SPENDER);
        (ok,) = address(token).call(abi.encodeCall(SecurityToken.transferFrom, (ALICE, BOB, 10)));
        assertTrue(!ok);
        vm.prank(MINTER);
        (ok,) = address(token).call(abi.encodeCall(SecurityToken.mint, (BOB, 10)));
        assertTrue(!ok);
        vm.prank(AGENT);
        (ok,) = address(token).call(abi.encodeCall(SecurityToken.recover, (CASE_A, ALICE, BOB, 10)));
        assertTrue(!ok);
        VmLogs.Log[] memory logs = vmLogs.getRecordedLogs();

        assertEq(logs.length, 0);
        _assertPositions(100, 0, 100);
        assertEq(token.allowance(ALICE, SPENDER), 50);
        assertTrue(!token.recoveryUsed(CASE_A));
    }
}
