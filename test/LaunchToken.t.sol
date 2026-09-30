// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {LaunchToken} from "../src/LaunchToken.sol";
import {SignalBoard} from "../src/SignalBoard.sol";
import {TestBase, Vm} from "./support/TestBase.sol";

contract LaunchTokenDeploymentHarness {
    function deploy() external returns (LaunchToken) {
        return new LaunchToken{salt: bytes32("launch-token")}();
    }

    function deployApplication() external returns (SignalBoard) {
        return new SignalBoard{salt: bytes32("signal-board")}();
    }
}

/// forge-config: default.fuzz.runs = 1000
contract LaunchTokenTest is TestBase {
    bytes32 private constant TRANSFER = keccak256("Transfer(address,address,uint256)");
    bytes32 private constant APPROVAL = keccak256("Approval(address,address,uint256)");
    uint256 private constant SUPPLY = 1_000_000_000 ether;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant SPENDER = address(0x5EED);

    LaunchToken private token;

    function setUp() public {
        token = new LaunchToken();
    }

    function testMetadataAndWholeSupplyBelongToDeployer() public view {
        assertEq(keccak256(bytes(token.name())), keccak256("Signal Board"));
        assertEq(keccak256(bytes(token.symbol())), keccak256("SIGNAL"));
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.allowance(address(this), ALICE), 0);
    }

    function testFactoryStyleDeploymentMintsToImmediateDeployerAndEmitsMint() public {
        LaunchTokenDeploymentHarness factory = new LaunchTokenDeploymentHarness();
        vm.recordLogs();
        vm.prank(ALICE);
        LaunchToken fresh = factory.deploy();
        assertEq(fresh.balanceOf(address(factory)), SUPPLY);
        assertEq(fresh.balanceOf(ALICE), 0);
        assertEq(fresh.balanceOf(address(this)), 0);
        _assertSingleEvent(address(fresh), TRANSFER, address(0), address(factory), SUPPLY);

        vm.prank(ALICE);
        SignalBoard application = factory.deployApplication();
        assertEq(fresh.balanceOf(address(factory)), SUPPLY);
        assertEq(fresh.balanceOf(address(application)), 0);
        assertEq(fresh.balanceOf(ALICE), 0);
        assertEq(application.totalActive(), 0);
    }

    function testTransferMovesExactAmountAndEmitsTransfer() public {
        vm.recordLogs();
        assertTrue(token.transfer(ALICE, 123 ether));
        assertEq(token.balanceOf(ALICE), 123 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 123 ether);
        assertEq(token.totalSupply(), SUPPLY);
        _assertSingleEvent(address(token), TRANSFER, address(this), ALICE, 123 ether);
    }

    function testEntireSupplyCanMoveWithoutFeeOrWalletLimit() public {
        assertTrue(token.transfer(ALICE, SUPPLY));
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testSelfTransferLeavesBalanceUnchangedAndEmitsTransfer() public {
        vm.recordLogs();
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        _assertSingleEvent(address(token), TRANSFER, address(this), address(this), SUPPLY);
    }

    function testZeroTransferFromEmptyAccountSucceedsAndEmitsTransfer() public {
        vm.recordLogs();
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 0));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
        _assertSingleEvent(address(token), TRANSFER, ALICE, BOB, 0);
    }

    function testInsufficientTransferAndSelfTransferRevertAtomically() public {
        token.transfer(ALICE, 5);
        bytes memory error = abi.encodeWithSelector(LaunchToken.ERC20InsufficientBalance.selector, ALICE, 5, 6);
        _assertRejected(ALICE, abi.encodeCall(token.transfer, (BOB, 6)), error);
        _assertRejected(ALICE, abi.encodeCall(token.transfer, (ALICE, 6)), error);
        assertEq(token.balanceOf(ALICE), 5);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 5);
    }

    function testTransfersRejectZeroReceiverIncludingZeroAmount() public {
        bytes memory error = abi.encodeWithSelector(LaunchToken.ERC20InvalidReceiver.selector, address(0));
        _assertRejected(address(this), abi.encodeCall(token.transfer, (address(0), 1)), error);
        _assertRejected(address(this), abi.encodeCall(token.transfer, (address(0), 0)), error);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
    }

    function testTransfersRejectZeroSenderIncludingZeroAmount() public {
        bytes memory error = abi.encodeWithSelector(LaunchToken.ERC20InvalidSender.selector, address(0));
        _assertRejected(address(0), abi.encodeCall(token.transfer, (ALICE, 0)), error);
        _assertRejected(SPENDER, abi.encodeCall(token.transferFrom, (address(0), ALICE, 0)), error);
    }

    function testApproveOverwritesRevokesAndEmitsApprovalWithoutMovingFunds() public {
        uint256[3] memory amounts = [uint256(100), uint256(25), uint256(0)];
        for (uint256 i; i < amounts.length; ++i) {
            vm.recordLogs();
            assertTrue(token.approve(SPENDER, amounts[i]));
            assertEq(token.allowance(address(this), SPENDER), amounts[i]);
            assertEq(token.allowance(address(this), BOB), 0);
            assertEq(token.balanceOf(address(this)), SUPPLY);
            _assertSingleEvent(address(token), APPROVAL, address(this), SPENDER, amounts[i]);
        }
    }

    function testApprovalNeedsNoBalanceAndCanExceedSupply() public {
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, type(uint256).max));
        assertEq(token.allowance(ALICE, SPENDER), type(uint256).max);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testApproveRejectsZeroSpenderAndApprover() public {
        _assertRejected(
            address(this),
            abi.encodeCall(token.approve, (address(0), 0)),
            abi.encodeWithSelector(LaunchToken.ERC20InvalidSpender.selector, address(0))
        );
        _assertRejected(
            address(0),
            abi.encodeCall(token.approve, (SPENDER, 1)),
            abi.encodeWithSelector(LaunchToken.ERC20InvalidApprover.selector, address(0))
        );
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.allowance(address(0), SPENDER), 0);
    }

    function testTransferFromConsumesOnlyCallersAllowanceAndEmitsTransfer() public {
        token.approve(SPENDER, 30);
        token.approve(BOB, 40);
        vm.recordLogs();
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 12));
        assertEq(token.allowance(address(this), SPENDER), 18);
        assertEq(token.allowance(address(this), BOB), 40);
        assertEq(token.balanceOf(address(this)), SUPPLY - 12);
        assertEq(token.balanceOf(ALICE), 12);
        _assertSingleEvent(address(token), TRANSFER, address(this), ALICE, 12);

        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 18));
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 30);
    }

    function testInfiniteApprovalIsNotConsumed() public {
        token.approve(SPENDER, type(uint256).max);
        vm.startPrank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 7));
        assertTrue(token.transferFrom(address(this), BOB, 11));
        vm.stopPrank();
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY - 18);
        assertEq(token.balanceOf(ALICE), 7);
        assertEq(token.balanceOf(BOB), 11);
    }

    function testMaximumFiniteApprovalIsConsumedAndCanBeReplacedWithUnlimited() public {
        token.approve(SPENDER, type(uint256).max - 1);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max - 2);
        token.approve(SPENDER, type(uint256).max);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        assertEq(token.balanceOf(ALICE), 2);
        assertEq(token.balanceOf(address(this)), SUPPLY - 2);
    }

    /// @dev The unlimited branch skips the allowance check, so the balance check must catch
    /// the maximum amount and the unconsumed allowance must survive the rejection.
    function testUnlimitedAllowanceDoesNotBypassBalanceAtMaximumAmount() public {
        token.approve(SPENDER, type(uint256).max);
        _assertRejected(
            SPENDER,
            abi.encodeCall(token.transferFrom, (address(this), ALICE, type(uint256).max)),
            abi.encodeWithSelector(
                LaunchToken.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        _assertRejected(
            SPENDER,
            abi.encodeCall(token.transferFrom, (address(this), ALICE, SUPPLY + 1)),
            abi.encodeWithSelector(LaunchToken.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, SUPPLY));
        assertEq(token.balanceOf(ALICE), SUPPLY);
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
    }

    function testTransferFromByOwnerStillRequiresItsOwnApproval() public {
        token.approve(SPENDER, SUPPLY);
        _assertRejected(
            address(this),
            abi.encodeCall(token.transferFrom, (address(this), ALICE, 1)),
            abi.encodeWithSelector(LaunchToken.ERC20InsufficientAllowance.selector, address(this), 0, 1)
        );
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.allowance(address(this), SPENDER), SUPPLY);
        token.approve(address(this), 1);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertEq(token.allowance(address(this), address(this)), 0);
        assertEq(token.balanceOf(ALICE), 1);
    }

    function testFuzzFiniteBudgetCanBeExhaustedButNotExceeded(uint256 budgetSeed) public {
        uint256 budget = bound(budgetSeed, 1, SUPPLY - 1);
        token.approve(SPENDER, budget);
        uint256 first = budget / 2;
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, first));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), BOB, budget - first));
        assertEq(token.allowance(address(this), SPENDER), 0);
        _assertRejected(
            SPENDER,
            abi.encodeCall(token.transferFrom, (address(this), ALICE, 1)),
            abi.encodeWithSelector(LaunchToken.ERC20InsufficientAllowance.selector, SPENDER, 0, 1)
        );
        assertEq(token.balanceOf(address(this)), SUPPLY - budget);
        assertEq(token.balanceOf(ALICE), first);
        assertEq(token.balanceOf(BOB), budget - first);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testUnapprovedAndRevokedSpenderCannotTransfer() public {
        bytes memory payload = abi.encodeCall(token.transferFrom, (address(this), ALICE, 1));
        bytes memory error = abi.encodeWithSelector(LaunchToken.ERC20InsufficientAllowance.selector, SPENDER, 0, 1);
        _assertRejected(SPENDER, payload, error);
        token.approve(SPENDER, 1);
        token.approve(SPENDER, 0);
        _assertRejected(SPENDER, payload, error);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.allowance(address(this), SPENDER), 0);
    }

    function testInsufficientAllowanceCannotSpendOthersApprovalOrChangeBalances() public {
        token.approve(SPENDER, 5);
        token.approve(BOB, 100);
        _assertRejected(
            SPENDER,
            abi.encodeCall(token.transferFrom, (address(this), ALICE, 6)),
            abi.encodeWithSelector(LaunchToken.ERC20InsufficientAllowance.selector, SPENDER, 5, 6)
        );
        assertEq(token.allowance(address(this), SPENDER), 5);
        assertEq(token.allowance(address(this), BOB), 100);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function testInsufficientBalancePreservesPreviouslyGrantedAllowance() public {
        token.transfer(ALICE, 5);
        vm.prank(ALICE);
        token.approve(SPENDER, 100);
        _assertRejected(
            SPENDER,
            abi.encodeCall(token.transferFrom, (ALICE, BOB, 6)),
            abi.encodeWithSelector(LaunchToken.ERC20InsufficientBalance.selector, ALICE, 5, 6)
        );
        assertEq(token.allowance(ALICE, SPENDER), 100);
        assertEq(token.balanceOf(ALICE), 5);
        assertEq(token.balanceOf(BOB), 0);
    }

    function testInvalidTransferFromReceiverDoesNotConsumeApproval() public {
        token.approve(SPENDER, 10);
        _assertRejected(
            SPENDER,
            abi.encodeCall(token.transferFrom, (address(this), address(0), 10)),
            abi.encodeWithSelector(LaunchToken.ERC20InvalidReceiver.selector, address(0))
        );
        assertEq(token.allowance(address(this), SPENDER), 10);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
    }

    function testSelfTransferFromConsumesApprovalWithoutChangingBalance() public {
        token.approve(SPENDER, 10);
        vm.recordLogs();
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), address(this), 10));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.allowance(address(this), SPENDER), 0);
        _assertSingleEvent(address(token), TRANSFER, address(this), address(this), 10);
    }

    function testZeroTransferFromNeedsNoApprovalAndEmitsTransfer() public {
        vm.recordLogs();
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 0));
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
        _assertSingleEvent(address(token), TRANSFER, ALICE, BOB, 0);
    }

    function testCommonAdministrativeSelectorsRejectEvenFromDeployer() public {
        string[16] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "issue(uint256)",
            "setOwner(address)",
            "transferOwnership(address)",
            "upgradeTo(address)",
            "initialize(address)",
            "pause()",
            "unpause()",
            "setMinter(address)",
            "owner()",
            "burn(uint256)",
            "burnFrom(address,uint256)",
            "setFee(uint256)",
            "setBlacklist(address,bool)"
        ];
        for (uint256 i; i < signatures.length; ++i) {
            bytes memory data = abi.encodeWithSignature(signatures[i], ALICE, type(uint128).max);
            _assertRejected(address(this), data, "");
            _assertRejected(ALICE, data, "");
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function testDeploymentRejectsETH() public {
        vm.deal(address(this), 1);
        bytes memory creationCode = type(LaunchToken).creationCode;
        address deployed;
        assembly ("memory-safe") {
            deployed := create(1, add(creationCode, 32), mload(creationCode))
        }
        assertEq(deployed, address(0), "constructor accepted ETH");
        assertEq(address(this).balance, 1);
    }

    function testAllFunctionsAndPlainTransfersRejectETH() public {
        vm.deal(address(this), 1 ether);
        bytes[] memory payloads = new bytes[](11);
        payloads[0] = abi.encodeCall(token.transfer, (ALICE, 1));
        payloads[1] = abi.encodeCall(token.approve, (SPENDER, 1));
        payloads[2] = abi.encodeCall(token.transferFrom, (address(this), ALICE, 0));
        payloads[3] = abi.encodeCall(token.totalSupply, ());
        payloads[4] = abi.encodeCall(token.balanceOf, (address(this)));
        payloads[5] = abi.encodeCall(token.allowance, (address(this), SPENDER));
        payloads[6] = abi.encodeCall(token.name, ());
        payloads[7] = abi.encodeCall(token.symbol, ());
        payloads[8] = abi.encodeCall(token.decimals, ());
        payloads[9] = "";
        payloads[10] = hex"deadbeef";
        vm.recordLogs();
        for (uint256 i; i < payloads.length; ++i) {
            (bool accepted,) = address(token).call{value: 1}(payloads[i]);
            assertFalse(accepted, "ETH-bearing call accepted");
        }
        assertEq(vm.getRecordedLogs().length, 0);
        assertEq(address(token).balance, 0);
        assertEq(address(this).balance, 1 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.allowance(address(this), SPENDER), 0);
    }

    function testRuntimeHasNoForbiddenOpcodes() public view {
        bytes memory runtime = address(token).code;
        assertTrue(runtime.length > 0 && runtime.length <= 24_576, "invalid runtime size");
        for (uint256 i; i < runtime.length; ++i) {
            uint8 opcode = uint8(runtime[i]);
            if (opcode >= 0x60 && opcode <= 0x7f) {
                i += opcode - 0x5f;
                continue;
            }
            assertTrue(opcode != 0xf4, "DELEGATECALL");
            assertTrue(opcode != 0xf2, "CALLCODE");
            assertTrue(opcode != 0xff, "SELFDESTRUCT");
        }
    }

    function testFuzzTransfersAndAllowancePreserveSupply(uint256 fundingSeed, uint256 spendSeed, uint256 returnSeed)
        public
    {
        uint256 funding = fundingSeed % (SUPPLY + 1);
        uint256 spend = spendSeed % (funding + 1);
        uint256 returned = returnSeed % (spend + 1);
        assertTrue(token.transfer(ALICE, funding));
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, funding));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, spend));
        vm.prank(BOB);
        assertTrue(token.transfer(address(this), returned));
        assertEq(token.balanceOf(address(this)), SUPPLY - funding + returned);
        assertEq(token.balanceOf(ALICE), funding - spend);
        assertEq(token.balanceOf(BOB), spend - returned);
        assertEq(token.allowance(ALICE, SPENDER), funding - spend);
        assertEq(token.balanceOf(address(this)) + token.balanceOf(ALICE) + token.balanceOf(BOB), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzTransferFromFailurePreservesBalancesAndAllowance(uint256 fundingSeed, uint256 excessSeed) public {
        uint256 funding = fundingSeed % (SUPPLY + 1);
        uint256 requested = funding + 1 + excessSeed % SUPPLY;
        token.transfer(ALICE, funding);
        vm.prank(ALICE);
        token.approve(SPENDER, requested);
        _assertRejected(
            SPENDER,
            abi.encodeCall(token.transferFrom, (ALICE, BOB, requested)),
            abi.encodeWithSelector(LaunchToken.ERC20InsufficientBalance.selector, ALICE, funding, requested)
        );
        assertEq(token.balanceOf(ALICE), funding);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - funding);
        assertEq(token.allowance(ALICE, SPENDER), requested);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function _assertSingleEvent(address emitter, bytes32 signature, address from, address to, uint256 amount) private {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1, "expected exactly one event");
        assertEq(logs[0].emitter, emitter, "event emitter");
        assertEq(logs[0].topics.length, 3, "event topic count");
        assertEq(logs[0].topics[0], signature, "event signature");
        assertEq(logs[0].topics[1], bytes32(uint256(uint160(from))), "event sender/owner");
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(to))), "event receiver/spender");
        assertEq(keccak256(logs[0].data), keccak256(abi.encode(amount)), "event amount");
    }

    function _assertRejected(address caller, bytes memory payload, bytes memory expectedError) private {
        vm.recordLogs();
        vm.prank(caller);
        (bool accepted, bytes memory revertData) = address(token).call(payload);
        assertFalse(accepted, "invalid token call accepted");
        assertEq(keccak256(revertData), keccak256(expectedError), "unexpected revert data");
        assertEq(vm.getRecordedLogs().length, 0, "rejected call emitted event");
    }
}
