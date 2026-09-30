// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SignalBoard} from "../src/SignalBoard.sol";
import {TestBase} from "./support/TestBase.sol";

/// @dev Finite actors allow the invariant to enumerate every possible active account.
contract SignalBoardHandler is TestBase {
    SignalBoard public immutable board;
    bytes32[4] public expectedSignal;
    uint256[4] public expectedRevision;
    uint256 public successfulSets;
    uint256 public successfulClears;

    constructor(SignalBoard board_) {
        board = board_;
    }

    function set(uint8 actorSeed, bytes32 value) external {
        uint256 index = actorSeed % 4;
        vm.prank(actor(index));
        (bool success, bytes memory result) = address(board).call(abi.encodeCall(board.setSignal, (value)));
        if (value == bytes32(0)) {
            _assertError(success, result, SignalBoard.ZeroSignal.selector);
        } else {
            require(success, "nonzero set failed");
            expectedSignal[index] = value;
            ++expectedRevision[index];
            ++successfulSets;
        }
    }

    function clear(uint8 actorSeed) external {
        uint256 index = actorSeed % 4;
        vm.prank(actor(index));
        (bool success, bytes memory result) = address(board).call(abi.encodeCall(board.clearSignal, ()));
        if (expectedSignal[index] == bytes32(0)) {
            _assertError(success, result, SignalBoard.NoSignal.selector);
        } else {
            require(success, "active clear failed");
            expectedSignal[index] = bytes32(0);
            ++expectedRevision[index];
            ++successfulClears;
        }
    }

    function rejectZero(uint8 actorSeed) external {
        vm.prank(actor(actorSeed % 4));
        (bool success, bytes memory result) = address(board).call(abi.encodeCall(board.setSignal, (bytes32(0))));
        _assertError(success, result, SignalBoard.ZeroSignal.selector);
    }

    function actor(uint256 index) public pure returns (address) {
        return address(uint160(0x1000 + index));
    }

    function _assertError(bool success, bytes memory result, bytes4 selector) private pure {
        require(!success, "invalid action succeeded");
        require(keccak256(result) == keccak256(abi.encodeWithSelector(selector)), "unexpected revert");
    }
}

contract SignalBoardInvariantTest is TestBase {
    SignalBoard private board;
    SignalBoardHandler private handler;
    address[] private targets;

    function setUp() public {
        board = new SignalBoard();
        handler = new SignalBoardHandler(board);
        targets.push(address(handler));
    }

    /// @dev Native Foundry invariant targeting; no external test library is needed.
    function targetContracts() public view returns (address[] memory) {
        return targets;
    }

    function invariant_signalsAndRevisionsMatchSuccessfulActions() public view {
        uint256 revisions;
        for (uint256 i; i < 4; ++i) {
            address account = handler.actor(i);
            assertEq(board.signalOf(account), handler.expectedSignal(i));
            assertEq(board.revisionOf(account), handler.expectedRevision(i));
            revisions += board.revisionOf(account);
        }
        assertEq(revisions, handler.successfulSets() + handler.successfulClears());
    }

    function invariant_totalActiveEqualsNonzeroSignals() public view {
        uint256 active;
        for (uint256 i; i < 4; ++i) {
            if (handler.expectedSignal(i) != bytes32(0)) ++active;
        }
        assertEq(board.totalActive(), active);
        assertTrue(board.totalActive() <= 4);
        assertEq(board.signalOf(address(handler)), bytes32(0));
        assertEq(board.revisionOf(address(handler)), 0);
    }
}
