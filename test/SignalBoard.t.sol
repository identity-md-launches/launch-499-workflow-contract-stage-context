// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SignalBoard} from "../src/SignalBoard.sol";
import {TestBase, Vm} from "./support/TestBase.sol";

/// @dev Represents a smart contract wallet: the immediate caller owns the signal.
contract SignalBoardWallet {
    SignalBoard private immutable board;

    constructor(SignalBoard board_) {
        board = board_;
    }

    function setSignal(bytes32 value) external {
        board.setSignal(value);
    }

    function clearSignal() external {
        board.clearSignal();
    }
}

contract SignalBoardTest is TestBase {
    bytes32 private constant SIGNAL_CHANGED = keccak256("SignalChanged(address,bytes32,uint256)");
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    bytes32 private constant FIRST = bytes32("hello");
    bytes32 private constant SECOND = bytes32("updated");

    SignalBoard private board;

    function setUp() public {
        board = new SignalBoard();
    }

    function testNoArgumentDeploymentStartsEmptyAndNeedsNoInitialization() public {
        vm.recordLogs();
        SignalBoard fresh = new SignalBoard();
        assertTrue(address(fresh).code.length > 0, "deployment has no runtime");
        assertEq(address(fresh).balance, 0, "deployment retained ETH");
        assertEq(fresh.totalActive(), 0, "deployment has active accounts");
        assertEq(fresh.signalOf(ALICE), bytes32(0), "deployment has a signal");
        assertEq(fresh.revisionOf(ALICE), 0, "deployment has a revision");
        assertEq(vm.getRecordedLogs().length, 0, "deployment emitted change events");

        vm.prank(ALICE);
        fresh.setSignal(FIRST);
        assertEq(fresh.signalOf(ALICE), FIRST, "first use needs initialization");
        assertEq(fresh.revisionOf(ALICE), 1, "first use revision");
        assertEq(fresh.totalActive(), 1, "first use active count");
    }

    function testFirstWriteEmitsAccountValueAndRevision() public {
        vm.recordLogs();
        _set(ALICE, FIRST);
        _assertAccount(ALICE, FIRST, 1);
        assertEq(board.totalActive(), 1, "first write active count");
        _assertSingleChange(ALICE, FIRST, 1);
    }

    function testOverwriteIncrementsRevisionWithoutIncreasingActiveCount() public {
        _set(ALICE, FIRST);
        vm.recordLogs();
        _set(ALICE, SECOND);
        _assertAccount(ALICE, SECOND, 2);
        assertEq(board.totalActive(), 1, "overwrite active count");
        _assertSingleChange(ALICE, SECOND, 2);
    }

    function testSameValueIsASuccessfulRevisionAndEvent() public {
        _set(ALICE, FIRST);
        vm.recordLogs();
        _set(ALICE, FIRST);
        _assertAccount(ALICE, FIRST, 2);
        assertEq(board.totalActive(), 1, "same value active count");
        _assertSingleChange(ALICE, FIRST, 2);
    }

    function testClearPreservesRevisionHistoryAndEmitsZeroValue() public {
        _set(ALICE, FIRST);
        _set(ALICE, SECOND);
        vm.recordLogs();
        _clear(ALICE);
        _assertAccount(ALICE, bytes32(0), 3);
        assertEq(board.totalActive(), 0, "clear active count");
        _assertSingleChange(ALICE, bytes32(0), 3);
    }

    function testWriteAfterClearContinuesRevisionAndRestoresActiveCount() public {
        _set(ALICE, FIRST);
        _clear(ALICE);
        vm.recordLogs();
        _set(ALICE, SECOND);
        _assertAccount(ALICE, SECOND, 3);
        assertEq(board.totalActive(), 1, "write after clear active count");
        _assertSingleChange(ALICE, SECOND, 3);
    }

    function testTwoWalletsHaveIndependentSignalsAndRevisions() public {
        _set(ALICE, FIRST);
        _set(BOB, SECOND);
        _set(ALICE, SECOND);
        assertEq(board.totalActive(), 2, "two active accounts");
        _assertAccount(ALICE, SECOND, 2);
        _assertAccount(BOB, SECOND, 1);

        _clear(ALICE);
        assertEq(board.totalActive(), 1, "clear one of two accounts");
        _assertAccount(ALICE, bytes32(0), 3);
        _assertAccount(BOB, SECOND, 1);

        _clear(BOB);
        assertEq(board.totalActive(), 0, "clear final account");
        _assertAccount(ALICE, bytes32(0), 3);
        _assertAccount(BOB, bytes32(0), 2);
    }

    function testZeroWriteOnEmptyAccountRevertsWithoutChangesOrEvents() public {
        _assertRejected(ALICE, abi.encodeCall(board.setSignal, (bytes32(0))), SignalBoard.ZeroSignal.selector);
        _assertAccount(ALICE, bytes32(0), 0);
        assertEq(board.totalActive(), 0, "rejected empty write active count");
    }

    function testZeroWriteOnActiveAccountPreservesSignalAndRevision() public {
        _set(ALICE, FIRST);
        _set(BOB, SECOND);
        _assertRejected(ALICE, abi.encodeCall(board.setSignal, (bytes32(0))), SignalBoard.ZeroSignal.selector);
        _assertAccount(ALICE, FIRST, 1);
        _assertAccount(BOB, SECOND, 1);
        assertEq(board.totalActive(), 2, "rejected active write active count");
    }

    function testClearingNeverWrittenAccountRevertsWithoutChangesOrEvents() public {
        _set(BOB, SECOND);
        _assertRejected(ALICE, abi.encodeCall(board.clearSignal, ()), SignalBoard.NoSignal.selector);
        _assertAccount(ALICE, bytes32(0), 0);
        _assertAccount(BOB, SECOND, 1);
        assertEq(board.totalActive(), 1, "rejected empty clear active count");
    }

    function testDuplicateClearRevertsAndDoesNotIncrementRevision() public {
        _set(ALICE, FIRST);
        _clear(ALICE);
        _assertRejected(ALICE, abi.encodeCall(board.clearSignal, ()), SignalBoard.NoSignal.selector);
        _assertAccount(ALICE, bytes32(0), 2);
        assertEq(board.totalActive(), 0, "duplicate clear active count");
    }

    function testSmartContractWalletOwnsItsSignalIndependentlyOfCallingWallet() public {
        SignalBoardWallet wallet = new SignalBoardWallet(board);
        _set(ALICE, FIRST);
        vm.recordLogs();
        vm.prank(ALICE);
        wallet.setSignal(SECOND);
        _assertSingleChange(address(wallet), SECOND, 1);
        _assertAccount(ALICE, FIRST, 1);
        _assertAccount(address(wallet), SECOND, 1);
        assertEq(board.totalActive(), 2, "contract wallet active count");

        vm.prank(ALICE);
        wallet.clearSignal();
        _assertAccount(ALICE, FIRST, 1);
        _assertAccount(address(wallet), bytes32(0), 2);
        assertEq(board.totalActive(), 1, "contract wallet clear count");
    }

    function testCallerCannotChooseAnotherAccountsSignalSlot() public {
        _set(ALICE, FIRST);
        vm.startPrank(BOB);
        (bool setAccepted,) = address(board).call(abi.encodeWithSignature("setSignal(address,bytes32)", ALICE, SECOND));
        (bool clearAccepted,) = address(board).call(abi.encodeWithSignature("clearSignal(address)", ALICE));
        vm.stopPrank();
        assertFalse(setAccepted, "arbitrary-account write accepted");
        assertFalse(clearAccepted, "arbitrary-account clear accepted");
        _assertAccount(ALICE, FIRST, 1);
        _assertAccount(BOB, bytes32(0), 0);
        assertEq(board.totalActive(), 1, "arbitrary-account attempts changed count");
    }

    function testAllFunctionsAndPlainTransfersRejectETHWithoutStateChanges() public {
        _set(ALICE, FIRST);
        vm.deal(ALICE, 1 ether);
        bytes[] memory payloads = new bytes[](7);
        payloads[0] = abi.encodeCall(board.setSignal, (SECOND));
        payloads[1] = abi.encodeCall(board.clearSignal, ());
        payloads[2] = abi.encodeCall(board.signalOf, (ALICE));
        payloads[3] = abi.encodeCall(board.revisionOf, (ALICE));
        payloads[4] = abi.encodeCall(board.totalActive, ());
        payloads[5] = bytes("");
        payloads[6] = hex"deadbeef";
        vm.recordLogs();
        for (uint256 i; i < payloads.length; ++i) {
            vm.prank(ALICE);
            (bool accepted,) = address(board).call{value: 1}(payloads[i]);
            assertFalse(accepted, "ETH-bearing call accepted");
        }
        assertEq(vm.getRecordedLogs().length, 0, "ETH-bearing calls emitted events");
        assertEq(address(board).balance, 0, "board accepted ETH");
        assertEq(ALICE.balance, 1 ether, "rejected calls retained ETH");
        _assertAccount(ALICE, FIRST, 1);
        assertEq(board.totalActive(), 1, "ETH-bearing calls changed active count");
    }

    function testDeploymentRejectsETH() public {
        vm.deal(address(this), 1);
        bytes memory creationCode = type(SignalBoard).creationCode;
        address deployed;
        assembly ("memory-safe") {
            deployed := create(1, add(creationCode, 32), mload(creationCode))
        }
        assertEq(deployed, address(0), "constructor accepted ETH");
        assertEq(address(this).balance, 1, "failed constructor retained ETH");
    }

    function testEmptyCalldataAndUnknownSelectorRejectWithoutETH() public {
        (bool emptyAccepted,) = address(board).call("");
        (bool unknownAccepted,) = address(board).call(hex"deadbeef");
        assertFalse(emptyAccepted, "empty calldata accepted");
        assertFalse(unknownAccepted, "unknown selector accepted");
        assertEq(board.totalActive(), 0, "unknown calls changed count");
    }

    function testFuzzLifecyclePreservesArbitraryNonzeroBytes32(address account, bytes32 first, bytes32 second) public {
        vm.assume(first != bytes32(0));
        vm.assume(second != bytes32(0));
        vm.recordLogs();
        _set(account, first);
        _assertAccount(account, first, 1);
        _assertSingleChange(account, first, 1);
        assertEq(board.totalActive(), 1, "fuzz initial active count");

        vm.recordLogs();
        _set(account, second);
        _assertAccount(account, second, 2);
        _assertSingleChange(account, second, 2);
        assertEq(board.totalActive(), 1, "fuzz overwrite active count");

        _clear(account);
        _assertAccount(account, bytes32(0), 3);
        assertEq(board.totalActive(), 0, "fuzz clear active count");
        _set(account, first);
        _assertAccount(account, first, 4);
        assertEq(board.totalActive(), 1, "fuzz rewrite active count");
    }

    function testFuzzDistinctCallersRemainIndependent(address firstAccount, address secondAccount, bytes32 value)
        public
    {
        vm.assume(firstAccount != secondAccount);
        vm.assume(value != bytes32(0));
        _set(firstAccount, value);
        _set(secondAccount, value);
        _clear(secondAccount);
        _assertAccount(firstAccount, value, 1);
        _assertAccount(secondAccount, bytes32(0), 2);
        assertEq(board.totalActive(), 1, "fuzz independent clear count");
        _clear(firstAccount);
        assertEq(board.totalActive(), 0, "fuzz independent final count");
    }

    function testFuzzRejectedZeroWritePreservesAnyCallersState(address account, bytes32 value, bool active) public {
        vm.assume(value != bytes32(0));
        if (active) _set(account, value);
        _assertRejected(account, abi.encodeCall(board.setSignal, (bytes32(0))), SignalBoard.ZeroSignal.selector);
        _assertAccount(account, active ? value : bytes32(0), active ? 1 : 0);
        assertEq(board.totalActive(), active ? 1 : 0, "fuzz rejected zero count");
    }

    function _set(address account, bytes32 value) private {
        vm.prank(account);
        board.setSignal(value);
    }

    function _clear(address account) private {
        vm.prank(account);
        board.clearSignal();
    }

    function _assertAccount(address account, bytes32 value, uint256 revision) private view {
        assertEq(board.signalOf(account), value, "unexpected account signal");
        assertEq(board.revisionOf(account), revision, "unexpected account revision");
    }

    function _assertSingleChange(address account, bytes32 value, uint256 revision) private {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1, "expected exactly one event");
        assertEq(logs[0].emitter, address(board), "event emitter");
        assertEq(logs[0].topics.length, 2, "event topic count");
        assertEq(logs[0].topics[0], SIGNAL_CHANGED, "event signature");
        assertEq(logs[0].topics[1], bytes32(uint256(uint160(account))), "indexed event account");
        assertEq(keccak256(logs[0].data), keccak256(abi.encode(value, revision)), "event value/revision");
    }

    function _assertRejected(address account, bytes memory payload, bytes4 expectedError) private {
        vm.recordLogs();
        vm.prank(account);
        (bool accepted, bytes memory revertData) = address(board).call(payload);
        assertFalse(accepted, "invalid action accepted");
        assertEq(keccak256(revertData), keccak256(abi.encodeWithSelector(expectedError)), "wrong rejection error");
        assertEq(vm.getRecordedLogs().length, 0, "rejected action emitted event");
    }
}
