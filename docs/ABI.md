# Contract ABIs and integration

The machine-readable ABI is [`abi/SignalBoard.json`](abi/SignalBoard.json), generated from `src/SignalBoard.sol:SignalBoard` with the pinned Foundry configuration. Regenerate it after changing the contract:

```sh
forge inspect src/SignalBoard.sol:SignalBoard abi --json > docs/abi/SignalBoard.json
```

There are no constructor arguments. The implicit constructor is nonpayable and may be absent from Solidity's ABI export. All callable methods below reject ETH, including reads invoked as transactions.

| Signature | Mutability / return | Meaning |
| --- | --- | --- |
| `setSignal(bytes32 value)` | nonpayable / none | Publish or replace the caller's nonzero signal. |
| `clearSignal()` | nonpayable / none | Clear the caller's active signal. |
| `signalOf(address)` | view / `bytes32` | Current signal; zero means empty. |
| `revisionOf(address)` | view / `uint256` | Number of successful changes, including clears. |
| `totalActive()` | view / `uint256` | Number of accounts whose current signal is nonzero. |

Errors: `ZeroSignal()` rejects zero writes; `NoSignal()` rejects empty clears. Neither has arguments. Solidity checked arithmetic can produce `Panic(uint256)` on overflow; no state or logs persist from a reverted transaction.

Event: `SignalChanged(address indexed account, bytes32 value, uint256 revision)`. Topic 0 is `keccak256("SignalChanged(address,bytes32,uint256)")`; topic 1 is the ABI-padded account. The unindexed data contains `value` then `revision`. The revision is the new, post-change value. Clears have `value = 0`; repeated identical nonzero writes still emit a new revision. Use big integers for counters rather than JavaScript `Number`.

## Text and wallet integration

For the website, encode a nonempty UTF-8 string into **at most 32 bytes**, then right-pad with zero bytes to exactly 32. Limit encoded bytes, not characters; reject oversized text instead of truncating multi-byte sequences. Reject NUL characters in text input so padding can be removed unambiguously, and reject an all-zero result. Some library string-to-bytes32 helpers reserve a byte for a terminator and support only 31 bytes; encode explicitly if the site offers the full 32-byte limit.

Decode display text by trimming trailing zero bytes, then using strict UTF-8 decoding. External clients may store any nonzero bytes, including invalid UTF-8 and embedded zeros; display the raw hex when text cannot be represented safely. Treat text as untrusted and render it using text nodes, not HTML.

Use the attested Sepolia deployment address and ABI. For writes, recheck wallet account and chain ID `11155111`, send zero ETH, and refresh signal/revision/count after the receipt confirms. Account/network changes must invalidate stale form state. Rejected signatures, reverted transactions, RPC failures, and replaced/dropped transactions need distinct useful status text. Read-only account inspection must work through a public Sepolia RPC without wallet connection.

## Bounded event history

Use the actual deployment block from the deployment service. Query only the attested contract's `SignalChanged` logs, optionally filtering the indexed account. For a recent list, capture a head block and work backward from it in capped chunks (for example, at most 2,000 blocks each), clamping every range to the deployment block. Bound requests and displayed results per page (for example, five chunks and 50 entries), retaining both a block cursor and an intra-block/log cursor if a range exceeds the page limit. Expose pagination even when a scanned page contains no events; never scan the entire deployment history in one unbounded request.

Sort by block number, transaction index, and log index. Deduplicate by block hash / transaction hash / log index. Handle provider range limits by shrinking the chunk, and reconcile recent pages on reorgs; do not treat pending or orphaned logs as confirmed state. Paginated history is not a complete list of accounts. Read current storage again when the UI needs authoritative current values.

## LaunchToken ABI

The machine-readable ABI is [`abi/LaunchToken.json`](abi/LaunchToken.json). Regenerate it with:

```sh
forge inspect src/LaunchToken.sol:LaunchToken abi --json > docs/abi/LaunchToken.json
```

The constructor is nonpayable, has no arguments, and mints exactly `10^27` minor units to its caller. No initialization follows deployment. SignalBoard has no token dependency and its UI needs no token calls.

| Signature | Mutability / return | Meaning |
| --- | --- | --- |
| `name()` | view / `string` | `Signal Board` |
| `symbol()` | view / `string` | `SIGNAL` |
| `decimals()` | view / `uint8` | `18` |
| `totalSupply()` | view / `uint256` | Constant `1000000000000000000000000000` |
| `balanceOf(address)` | view / `uint256` | Balance in minor units. |
| `allowance(address owner, address spender)` | view / `uint256` | Current spending allowance in minor units. |
| `transfer(address to, uint256 value)` | nonpayable / `bool` | Transfer caller's tokens; returns true on success. |
| `approve(address spender, uint256 value)` | nonpayable / `bool` | Replace allowance; returns true on success. |
| `transferFrom(address from, address to, uint256 value)` | nonpayable / `bool` | Spend caller's allowance and transfer; returns true on success. |

Events are `Transfer(address indexed from, address indexed to, uint256 value)` and `Approval(address indexed owner, address indexed spender, uint256 value)`. Creation emits `Transfer` from the zero address for the entire supply. Zero-value transfers and self-transfers emit events. Finite allowance decreases on `transferFrom` without emitting `Approval`; maximum `uint256` allowance stays unchanged. Even an owner calling `transferFrom` for its own tokens needs allowance for positive amounts; `transfer` requires none.

Errors are `ERC20InvalidSender(address sender)`, `ERC20InvalidReceiver(address receiver)`, `ERC20InvalidApprover(address approver)`, `ERC20InvalidSpender(address spender)`, `ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed)`, and `ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed)`. Zero senders, recipients, approvers, and spenders are rejected. `transferFrom` checks allowance before transfer validity, so insufficient allowance may be the first error even if the recipient is zero. Reverts restore all balances and allowances and retain no events. Unknown selectors, empty calls, and ETH-bearing calls revert.

Deployment restrictions, the product/launch-token authorization conflict, and service responsibilities are recorded in the [README](../README.md).
