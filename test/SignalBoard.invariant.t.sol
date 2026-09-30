// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SignalBoard} from "../src/SignalBoard.sol";
import {TestBase, Vm} from "./support/TestBase.sol";

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
        vm.recordLogs();
        vm.prank(actor(index));
        (bool success, bytes memory result) = address(board).call(abi.encodeCall(board.setSignal, (value)));
        if (value == bytes32(0)) {
            _assertError(success, result, SignalBoard.ZeroSignal.selector);
        } else {
            require(success, "nonzero set failed");
            expectedSignal[index] = value;
            ++expectedRevision[index];
            ++successfulSets;
            _assertChange(index, value);
        }
    }

    function clear(uint8 actorSeed) external {
        uint256 index = actorSeed % 4;
        vm.recordLogs();
        vm.prank(actor(index));
        (bool success, bytes memory result) = address(board).call(abi.encodeCall(board.clearSignal, ()));
        if (expectedSignal[index] == bytes32(0)) {
            _assertError(success, result, SignalBoard.NoSignal.selector);
        } else {
            require(success, "active clear failed");
            expectedSignal[index] = bytes32(0);
            ++expectedRevision[index];
            ++successfulClears;
            _assertChange(index, bytes32(0));
        }
    }

    function rejectZero(uint8 actorSeed) external {
        vm.recordLogs();
        vm.prank(actor(actorSeed % 4));
        (bool success, bytes memory result) = address(board).call(abi.encodeCall(board.setSignal, (bytes32(0))));
        _assertError(success, result, SignalBoard.ZeroSignal.selector);
    }

    /// @dev Repeated writes are mutations even when the value does not change.
    function repeatValue(uint8 actorSeed) external {
        uint256 index = actorSeed % 4;
        bytes32 value = expectedSignal[index];
        if (value == bytes32(0)) value = bytes32(uint256(1));
        vm.recordLogs();
        vm.prank(actor(index));
        board.setSignal(value);
        expectedSignal[index] = value;
        ++expectedRevision[index];
        ++successfulSets;
        _assertChange(index, value);
    }

    function rejectETH(uint8 actorSeed, bool clearCall) external {
        address account = actor(actorSeed % 4);
        vm.deal(account, 1);
        vm.recordLogs();
        vm.prank(account);
        (bool success, bytes memory result) = address(board).call{value: 1}(
            clearCall ? abi.encodeCall(board.clearSignal, ()) : abi.encodeCall(board.setSignal, (bytes32(uint256(1))))
        );
        assertFalse(success, "ETH-bearing mutation succeeded");
        assertEq(result.length, 0, "nonpayable rejection data");
        assertEq(vm.getRecordedLogs().length, 0, "rejected ETH call emitted a change");
        assertEq(account.balance, 1, "rejected call kept caller ETH");
        assertEq(address(board).balance, 0, "board retained sent ETH");
    }

    function actor(uint256 index) public pure returns (address) {
        return address(uint160(0x1000 + index));
    }

    function _assertError(bool success, bytes memory result, bytes4 selector) private {
        require(!success, "invalid action succeeded");
        require(keccak256(result) == keccak256(abi.encodeWithSelector(selector)), "unexpected revert");
        assertEq(vm.getRecordedLogs().length, 0, "rejected action emitted a change");
    }

    function _assertChange(uint256 index, bytes32 value) private {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1, "each successful mutation emits once");
        assertEq(logs[0].emitter, address(board), "wrong change emitter");
        assertEq(logs[0].topics.length, 2, "wrong change topic count");
        assertEq(logs[0].topics[0], keccak256("SignalChanged(address,bytes32,uint256)"));
        assertEq(logs[0].topics[1], bytes32(uint256(uint160(actor(index)))), "wrong changed account");
        assertEq(keccak256(logs[0].data), keccak256(abi.encode(value, expectedRevision[index])), "wrong change data");
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 64
/// forge-config: default.invariant.fail-on-revert = true
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

    /// @dev Witness every handler action and both clear branches without relying on random selection.
    function testHandlerExercisesLifecycleAndEveryFailureAction() public {
        handler.clear(0);
        handler.set(0, bytes32(0));
        handler.rejectZero(0);
        handler.rejectETH(0, false);
        handler.rejectETH(0, true);
        invariant_signalsAndRevisionsMatchSuccessfulActions();
        invariant_totalActiveEqualsNonzeroSignals();

        handler.set(0, bytes32(uint256(1)));
        handler.repeatValue(0);
        handler.set(0, bytes32(type(uint256).max));
        handler.set(1, bytes32("peer"));
        handler.set(0, bytes32(0));
        handler.rejectZero(0);
        handler.rejectETH(0, false);
        handler.rejectETH(0, true);
        assertEq(board.signalOf(handler.actor(0)), bytes32(type(uint256).max));
        assertEq(board.revisionOf(handler.actor(0)), 3);
        assertEq(board.totalActive(), 2);
        invariant_signalsAndRevisionsMatchSuccessfulActions();
        invariant_totalActiveEqualsNonzeroSignals();

        handler.clear(0);
        handler.clear(0);
        handler.repeatValue(0);
        assertEq(board.revisionOf(handler.actor(0)), 5);
        assertEq(board.totalActive(), 2);
        invariant_signalsAndRevisionsMatchSuccessfulActions();
        invariant_totalActiveEqualsNonzeroSignals();

        handler.clear(0);
        handler.clear(1);
        assertEq(handler.successfulSets(), 5);
        assertEq(handler.successfulClears(), 3);
        assertEq(board.revisionOf(handler.actor(0)), 6);
        assertEq(board.revisionOf(handler.actor(1)), 2);
        assertEq(board.totalActive(), 0);
        invariant_signalsAndRevisionsMatchSuccessfulActions();
        invariant_totalActiveEqualsNonzeroSignals();
        invariant_activeAccountsHaveHistoryAndBoundTheCount();
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

    /// @dev Independent of the handler's ghosts: a nonzero signal can only exist behind a
    /// recorded change, and the active count can never exceed the accounts with history.
    function invariant_activeAccountsHaveHistoryAndBoundTheCount() public view {
        uint256 touched;
        for (uint256 i; i < 4; ++i) {
            address account = handler.actor(i);
            uint256 revision = board.revisionOf(account);
            if (board.signalOf(account) != bytes32(0)) {
                assertTrue(revision >= 1, "active account without a recorded change");
            }
            if (revision > 0) ++touched;
        }
        assertTrue(board.totalActive() <= touched, "more active accounts than accounts with history");
        assertEq(address(board).balance, 0, "board holds ETH");
    }
}
