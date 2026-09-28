// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AllowList} from "../src/AllowList.sol";
import {SecurityToken} from "../src/SecurityToken.sol";
import {TestBase} from "./TestBase.sol";

contract SecurityTokenSmokeTest is TestBase {
    SecurityToken private token;
    AllowList private allowlist;

    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant MALLORY = address(0xBAD);

    function setUp() public {
        allowlist = new AllowList(address(this));
        token = new SecurityToken(address(allowlist));
        token.grantRole(token.MINTER_ROLE(), address(this));
        token.grantRole(token.AGENT_ROLE(), address(this));
        allowlist.allow(ALICE);
        allowlist.allow(BOB);
    }

    function test_transferBetweenEligibleWallets() public {
        token.mint(ALICE, 100);

        vm.prank(ALICE);
        token.transfer(BOB, 40);

        assertEq(token.balanceOf(ALICE), 60);
        assertEq(token.balanceOf(BOB), 40);
    }

    function test_ineligibleRecipientIsRejected() public {
        token.mint(ALICE, 100);

        vm.prank(ALICE);
        vm.expectRevert();
        token.transfer(MALLORY, 1);
    }

    function test_directTransferHonoursWalletHold() public {
        token.mint(ALICE, 100);
        token.freeze(ALICE);

        vm.prank(ALICE);
        vm.expectRevert();
        token.transfer(BOB, 1);
    }

    function test_pauseAndUnpauseOrdinaryTransfer() public {
        token.mint(ALICE, 100);
        token.pause();

        vm.prank(ALICE);
        vm.expectRevert();
        token.transfer(BOB, 1);

        token.unpause();
        vm.prank(ALICE);
        token.transfer(BOB, 1);
        assertEq(token.balanceOf(BOB), 1);
    }
}
