// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {LaunchToken} from "src/LaunchToken.sol";
import {TestBase, Vm} from "./support/TestBase.sol";

/// @dev All destinations belong to a finite actor set. Ghosts track gross movements and
/// approval budgets, independently of contract storage and emitted events.
contract LaunchTokenHandler is TestBase {
    uint256 public constant SUPPLY = 1_000_000_000 ether;
    LaunchToken public immutable token;
    uint256[4] public received;
    uint256[4] public sent;
    uint256[4][4] public approved;
    uint256[4][4] public spent;

    constructor() {
        token = new LaunchToken();
        for (uint256 i; i < 4; ++i) {
            assertTrue(token.transfer(actor(i), endowment(i)), "initial funding failed");
        }
    }

    function actor(uint256 index) public pure returns (address) {
        require(index < 4, "unknown actor");
        return address(uint160(0x10000 + index));
    }

    function endowment(uint256 index) public pure returns (uint256) {
        return index == 0 ? SUPPLY / 2 : (index < 3 ? SUPPLY / 4 : 0);
    }

    function expectedBalance(uint256 index) public view returns (uint256) {
        return endowment(index) + received[index] - sent[index];
    }

    function expectedAllowance(uint256 owner, uint256 spender) public view returns (uint256) {
        return approved[owner][spender] == type(uint256).max
            ? type(uint256).max
            : approved[owner][spender] - spent[owner][spender];
    }

    function transfer(uint8 fromSeed, uint8 toSeed, uint256 amountSeed) external {
        uint256 from = fromSeed % 4;
        _transfer(from, toSeed % 4, _amount(amountSeed, expectedBalance(from)));
    }

    function approve(uint8 ownerSeed, uint8 spenderSeed, uint256 amountSeed, uint8 modeSeed) external {
        uint256 mode = modeSeed % 5;
        uint256 amount = mode == 0
            ? 0
            : mode == 1
                ? type(uint256).max
                : mode == 2 ? type(uint256).max - 1 : mode == 3 ? SUPPLY + 1 : bound(amountSeed, 0, SUPPLY);
        _approve(ownerSeed % 4, spenderSeed % 4, amount);
    }

    function transferFrom(uint8 ownerSeed, uint8 spenderSeed, uint8 toSeed, uint256 amountSeed) external {
        uint256 owner = ownerSeed % 4;
        uint256 spender = spenderSeed % 4;
        uint256 to = toSeed % 4;
        uint256 available = expectedBalance(owner);
        uint256 budget = expectedAllowance(owner, spender);
        uint256 amount = _amount(amountSeed, available < budget ? available : budget);
        vm.recordLogs();
        vm.prank(actor(spender));
        assertTrue(token.transferFrom(actor(owner), actor(to), amount), "authorized transferFrom failed");
        sent[owner] += amount;
        received[to] += amount;
        if (approved[owner][spender] != type(uint256).max) spent[owner][spender] += amount;
        _assertEvent(keccak256("Transfer(address,address,uint256)"), owner, to, amount);
    }

    /// @dev Overspending must fail even for a self-transfer and even at uint256.max.
    function rejectOverspend(uint8 fromSeed, uint8 toSeed, bool maximum) external {
        uint256 from = fromSeed % 4;
        uint256 available = expectedBalance(from);
        uint256 amount = maximum ? type(uint256).max : available + 1;
        _reject(
            actor(from),
            abi.encodeCall(token.transfer, (actor(toSeed % 4), amount)),
            abi.encodeWithSelector(LaunchToken.ERC20InsufficientBalance.selector, actor(from), available, amount)
        );
    }

    /// @dev Revoke a previously finite or infinite approval, then prove it is unusable.
    function revokeAndReject(uint8 ownerSeed, uint8 spenderSeed, uint8 toSeed) external {
        uint256 owner = ownerSeed % 4;
        uint256 spender = spenderSeed % 4;
        _approve(owner, spender, 0);
        _reject(
            actor(spender),
            abi.encodeCall(token.transferFrom, (actor(owner), actor(toSeed % 4), 1)),
            abi.encodeWithSelector(LaunchToken.ERC20InsufficientAllowance.selector, actor(spender), 0, 1)
        );
    }

    /// @dev Sufficient approval with insufficient funds exercises rollback of allowance consumption.
    function rejectBalanceAfterApproval(uint8 ownerSeed, uint8 spenderSeed, uint8 toSeed, bool unlimited) external {
        uint256 owner = ownerSeed % 4;
        uint256 spender = spenderSeed % 4;
        uint256 available = expectedBalance(owner);
        uint256 amount = available + 1;
        _approve(owner, spender, unlimited ? type(uint256).max : amount);
        _reject(
            actor(spender),
            abi.encodeCall(token.transferFrom, (actor(owner), actor(toSeed % 4), amount)),
            abi.encodeWithSelector(LaunchToken.ERC20InsufficientBalance.selector, actor(owner), available, amount)
        );
    }

    function rejectZeroReceiver(uint8 ownerSeed, uint8 spenderSeed, uint256 amountSeed, bool delegated) external {
        uint256 owner = ownerSeed % 4;
        uint256 spender = spenderSeed % 4;
        uint256 amount = _amount(amountSeed, expectedBalance(owner));
        if (delegated) _approve(owner, spender, amount);
        bytes memory payload = delegated
            ? abi.encodeCall(token.transferFrom, (actor(owner), address(0), amount))
            : abi.encodeCall(token.transfer, (address(0), amount));
        _reject(
            actor(delegated ? spender : owner),
            payload,
            abi.encodeWithSelector(LaunchToken.ERC20InvalidReceiver.selector, address(0))
        );
    }

    function rejectZeroSpender(uint8 ownerSeed, uint256 amount) external {
        _reject(
            actor(ownerSeed % 4),
            abi.encodeCall(token.approve, (address(0), amount)),
            abi.encodeWithSelector(LaunchToken.ERC20InvalidSpender.selector, address(0))
        );
    }

    function roundTrip(uint8 fromSeed, uint8 toSeed, uint256 amountSeed) external {
        uint256 from = fromSeed % 4;
        uint256 to = toSeed % 4;
        uint256 fromBefore = expectedBalance(from);
        uint256 toBefore = expectedBalance(to);
        uint256 amount = _amount(amountSeed, fromBefore);
        _transfer(from, to, amount);
        _transfer(to, from, amount);
        assertEq(token.balanceOf(actor(from)), fromBefore, "round trip lost sender funds");
        assertEq(token.balanceOf(actor(to)), toBefore, "round trip gained recipient funds");
    }

    function _amount(uint256 seed, uint256 maximum) private pure returns (uint256) {
        // Explicitly exercise empty, one-unit and full-balance operations during random sequences.
        if (seed % 4 == 0) return 0;
        if (seed % 4 == 1) return maximum == 0 ? 0 : 1;
        if (seed % 4 == 2) return maximum;
        return bound(seed, 0, maximum);
    }

    function _transfer(uint256 from, uint256 to, uint256 amount) private {
        vm.recordLogs();
        vm.prank(actor(from));
        assertTrue(token.transfer(actor(to), amount), "funded transfer failed");
        sent[from] += amount;
        received[to] += amount;
        _assertEvent(keccak256("Transfer(address,address,uint256)"), from, to, amount);
        assertEq(token.balanceOf(actor(from)), expectedBalance(from), "sender ledger mismatch");
        assertEq(token.balanceOf(actor(to)), expectedBalance(to), "recipient ledger mismatch");
    }

    function _approve(uint256 owner, uint256 spender, uint256 amount) private {
        vm.recordLogs();
        vm.prank(actor(owner));
        assertTrue(token.approve(actor(spender), amount), "approval failed");
        approved[owner][spender] = amount;
        spent[owner][spender] = 0;
        _assertEvent(keccak256("Approval(address,address,uint256)"), owner, spender, amount);
    }

    function _reject(address caller, bytes memory payload, bytes memory expectedError) private {
        vm.recordLogs();
        vm.prank(caller);
        (bool success, bytes memory result) = address(token).call(payload);
        assertFalse(success, "invalid action accepted");
        assertEq(keccak256(result), keccak256(expectedError), "wrong rejection error");
        assertEq(vm.getRecordedLogs().length, 0, "rejected action emitted events");
        // Failed calls leave every ghost untouched; the global invariants check all balances/approvals.
    }

    function _assertEvent(bytes32 signature, uint256 from, uint256 to, uint256 amount) private {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1, "action must emit exactly once");
        assertEq(logs[0].emitter, address(token), "wrong event emitter");
        assertEq(logs[0].topics.length, 3, "wrong topic count");
        assertEq(logs[0].topics[0], signature, "wrong event signature");
        assertEq(logs[0].topics[1], bytes32(uint256(uint160(actor(from)))), "wrong event sender");
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(actor(to)))), "wrong event receiver");
        assertEq(keccak256(logs[0].data), keccak256(abi.encode(amount)), "wrong event amount");
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 64
/// forge-config: default.invariant.fail-on-revert = true
contract LaunchTokenInvariantTest is TestBase {
    LaunchTokenHandler private handler;
    LaunchToken private token;
    address[] private targets;

    function setUp() public {
        handler = new LaunchTokenHandler();
        token = handler.token();
        targets.push(address(handler));
    }

    function targetContracts() public view returns (address[] memory) {
        return targets;
    }

    function invariant_supplyEqualsSumOfActorBalances() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            sum += token.balanceOf(handler.actor(i));
        }
        assertEq(token.totalSupply(), 1_000_000_000 ether, "fixed supply changed");
        assertEq(sum, token.totalSupply(), "tokens created, destroyed or leaked");
        assertEq(token.balanceOf(address(0)), 0, "zero address received tokens");
        assertEq(token.balanceOf(address(handler)), 0, "handler retained tokens");
        assertEq(token.balanceOf(address(token)), 0, "token siphoned funds");
    }

    function invariant_eachBalanceMatchesInitialFundsPlusNetTransfers() public view {
        for (uint256 i; i < 4; ++i) {
            assertEq(token.balanceOf(handler.actor(i)), handler.expectedBalance(i), "actor ledger mismatch");
        }
    }

    function invariant_onlyAuthorizedSpendingConsumesAllowance() public view {
        for (uint256 i; i < 4; ++i) {
            for (uint256 j; j < 4; ++j) {
                assertEq(
                    token.allowance(handler.actor(i), handler.actor(j)),
                    handler.expectedAllowance(i, j),
                    "approval budget mismatch"
                );
            }
            assertEq(token.allowance(handler.actor(i), address(0)), 0, "zero spender approved");
        }
    }

    /// @dev Deterministic witness that every action is usable and delegated transfers move value.
    function testHandlerExercisesFundedDelegationAndEveryFailureAction() public {
        handler.approve(0, 1, 0, 1);
        handler.transferFrom(0, 1, 3, 1);
        assertEq(token.balanceOf(handler.actor(3)), 1);
        handler.approve(0, 1, 10, 4);
        handler.transferFrom(0, 1, 3, 3);
        assertEq(token.allowance(handler.actor(0), handler.actor(1)), 7);
        handler.transfer(3, 2, 1);
        handler.roundTrip(2, 3, 2);
        handler.rejectOverspend(0, 0, true);
        handler.rejectOverspend(0, 3, false);
        handler.revokeAndReject(0, 1, 3);
        handler.rejectBalanceAfterApproval(0, 1, 3, false);
        handler.rejectBalanceAfterApproval(0, 1, 3, true);
        handler.rejectZeroReceiver(0, 1, 2, true);
        handler.rejectZeroReceiver(0, 1, 0, false);
        handler.rejectZeroSpender(0, type(uint256).max);
        invariant_supplyEqualsSumOfActorBalances();
        invariant_eachBalanceMatchesInitialFundsPlusNetTransfers();
        invariant_onlyAuthorizedSpendingConsumesAllowance();
    }
}
