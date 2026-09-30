// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SignalBoard} from "src/SignalBoard.sol";
import {TestBase, Vm} from "./support/TestBase.sol";

contract SignalBoardAtomicWallet {
    SignalBoard private immutable board;

    constructor(SignalBoard board_) {
        board = board_;
    }

    function set(bytes32 value) external {
        board.setSignal(value);
    }

    function setThenFail(bytes32 value, bool duplicateClear) external {
        board.setSignal(value);
        if (duplicateClear) {
            board.clearSignal();
            board.clearSignal();
        } else {
            board.setSignal(bytes32(0));
        }
    }
}

/// forge-config: default.fuzz.runs = 1000
contract SignalBoardAdversarialTest is TestBase {
    SignalBoard private board;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);

    function setUp() public {
        board = new SignalBoard();
        vm.prank(BOB);
        board.setSignal(bytes32("peer"));
    }

    function testRawBytes32ExtremesArePreservedExactly() public {
        bytes32[4] memory values = [
            bytes32(uint256(1)), bytes32(uint256(1) << 255), bytes32(type(uint256).max), bytes32(unicode"signal 🌍")
        ];
        for (uint256 i; i < values.length; ++i) {
            vm.recordLogs();
            vm.prank(ALICE);
            board.setSignal(values[i]);
            assertEq(board.signalOf(ALICE), values[i], "signal was truncated or transformed");
            assertEq(board.revisionOf(ALICE), i + 1, "edge write lost a revision");
            assertEq(board.totalActive(), 2, "overwrite counted as another account");
            Vm.Log[] memory logs = vm.getRecordedLogs();
            assertEq(logs.length, 1);
            assertEq(keccak256(logs[0].data), keccak256(abi.encode(values[i], i + 1)));
        }
        _assertPeer();
    }

    function testReadOnlyCallsWorkAndStaticMutationsFailAtomically() public {
        board.setSignal(bytes32("original"));
        (bool readable, bytes memory result) =
            address(board).staticcall(abi.encodeCall(board.signalOf, (address(this))));
        assertTrue(readable, "read-only access failed");
        assertEq(abi.decode(result, (bytes32)), bytes32("original"));
        // Cap subcall gas so an exceptional SSTORE halt cannot consume the test's whole budget.
        (bool setAccepted,) =
            address(board).staticcall{gas: 100_000}(abi.encodeCall(board.setSignal, (bytes32("replacement"))));
        (bool clearAccepted,) = address(board).staticcall{gas: 100_000}(abi.encodeCall(board.clearSignal, ()));
        assertFalse(setAccepted, "static set changed state");
        assertFalse(clearAccepted, "static clear changed state");
        assertEq(board.signalOf(address(this)), bytes32("original"));
        assertEq(board.revisionOf(address(this)), 1);
        assertEq(board.totalActive(), 2);
        _assertPeer();
    }

    function testFuzzTruncatedSetCalldataCannotCreateOrOverwrite(uint8 lengthSeed, bool active) public {
        if (active) {
            vm.prank(ALICE);
            board.setSignal(bytes32("original"));
        }
        bytes memory valid = abi.encodeCall(board.setSignal, (bytes32(type(uint256).max)));
        bytes memory truncated = new bytes(bound(lengthSeed, 0, valid.length - 1));
        for (uint256 i; i < truncated.length; ++i) {
            truncated[i] = valid[i];
        }
        vm.recordLogs();
        vm.prank(ALICE);
        (bool accepted, bytes memory result) = address(board).call(truncated);
        assertFalse(accepted, "truncated ABI argument accepted");
        assertEq(result.length, 0, "unexpected ABI rejection data");
        assertEq(vm.getRecordedLogs().length, 0, "malformed call emitted a change");
        assertEq(board.signalOf(ALICE), active ? bytes32("original") : bytes32(0));
        assertEq(board.revisionOf(ALICE), active ? 1 : 0);
        assertEq(board.totalActive(), active ? 2 : 1);
        _assertPeer();
    }

    function testFuzzRevertingWalletBatchRestoresAllPriorState(bytes32 value, bool active, bool duplicateClear) public {
        value = bytes32(bound(uint256(value), 1, type(uint256).max));
        SignalBoardAtomicWallet wallet = new SignalBoardAtomicWallet(board);
        if (active) wallet.set(bytes32("original"));
        (bool accepted, bytes memory result) =
            address(wallet).call(abi.encodeCall(wallet.setThenFail, (value, duplicateClear)));
        assertFalse(accepted, "invalid batch succeeded");
        bytes4 selector = duplicateClear ? SignalBoard.NoSignal.selector : SignalBoard.ZeroSignal.selector;
        assertEq(keccak256(result), keccak256(abi.encodeWithSelector(selector)), "wrong batch failure");
        assertEq(board.signalOf(address(wallet)), active ? bytes32("original") : bytes32(0));
        assertEq(board.revisionOf(address(wallet)), active ? 1 : 0);
        assertEq(board.totalActive(), active ? 2 : 1);
        _assertPeer();

        wallet.set(value);
        assertEq(board.signalOf(address(wallet)), value);
        assertEq(board.revisionOf(address(wallet)), active ? 2 : 1, "failed batch advanced revision");
        assertEq(board.totalActive(), 2, "failed batch leaked active count");
    }

    function testFuzzIndependentWritesCommute(bytes32 aliceValue, bytes32 bobValue) public {
        aliceValue = bytes32(bound(uint256(aliceValue), 1, type(uint256).max));
        bobValue = bytes32(bound(uint256(bobValue), 1, type(uint256).max));
        SignalBoard left = new SignalBoard();
        SignalBoard right = new SignalBoard();
        vm.prank(ALICE);
        left.setSignal(aliceValue);
        vm.prank(BOB);
        left.setSignal(bobValue);
        vm.prank(BOB);
        right.setSignal(bobValue);
        vm.prank(ALICE);
        right.setSignal(aliceValue);
        assertEq(left.signalOf(ALICE), right.signalOf(ALICE), "peer order changed Alice's signal");
        assertEq(left.signalOf(BOB), right.signalOf(BOB), "peer order changed Bob's signal");
        assertEq(left.revisionOf(ALICE), right.revisionOf(ALICE), "peer order changed Alice's revision");
        assertEq(left.revisionOf(BOB), right.revisionOf(BOB), "peer order changed Bob's revision");
        assertEq(left.totalActive(), right.totalActive(), "peer order changed active count");
        assertEq(left.totalActive(), 2);
    }

    function _assertPeer() private view {
        assertEq(board.signalOf(BOB), bytes32("peer"), "another account's signal changed");
        assertEq(board.revisionOf(BOB), 1, "another account's revision changed");
    }
}
