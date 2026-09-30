# Contract test coverage

The tests use native Foundry cheatcodes through `support/TestBase.sol` and need no
downloaded dependencies, forks, environment variables or FFI. Run `forge build`
and `forge test`. To keep generated build files in the disposable scratch area:

```sh
forge build --out test/scratch/out --cache-path test/scratch/cache
forge test --out test/scratch/out --cache-path test/scratch/cache
```

Fuzz suites specify 1,000 runs in the test source. Both invariant suites specify
256 runs at depth 64 with `fail-on-revert = true`. Expected contract failures are
caught and checked by the handlers; an unexpected handler failure fails the run.
Foundry's handler call statistics show which actions were exercised.

| Suite | Properties and adversarial inputs |
| --- | --- |
| `SignalBoard.t.sol` | Lifecycle, caller isolation, revisions, events, zero writes, empty clears, duplicate clears, nonpayable calls, constructor, EIP-170/forbidden-opcode runtime floor, up to 40 distinct wallets counted once each, and a fuzzed 32-step interleaving of successes and failures for one wallet |
| `SignalBoard.adversarial.t.sol` | Raw bytes32 extremes, static calls, truncated calldata, appended-account spoofing, rejected owner/pause/upgrade calls from deployer and wallet, atomic wallet-batch rollback, independent-call ordering |
| `SignalBoard.invariant.t.sol` | Four actors, random sets/clears/repeated values, rejected zero/ETH calls, exact event account/value/revision, active count and successful-change accounting, a deterministic witness for every handler action, and a ghost-free bound: every active account has a revision and the count never exceeds accounts with history |
| `LaunchToken.t.sol` | Fixed-supply mechanics, transfer/approval events, invalid senders/receivers, allowance exhaustion, finite/infinite boundaries, unlimited allowance at the maximum amount, and atomic failure |
| `LaunchToken.invariant.t.sol` | Four funded/unfunded actors, random transfers/approvals/delegated transfers, revocations, full-balance round trips, overspending, invalid receiver/spender and rollback |

The token's invariant handler accounts for every possible destination in its
finite actor set. Each balance must equal its initial endowment plus gross receipts
minus gross sends. The sum must equal the fixed supply. Approval budgets are
tracked separately from successful delegated spending; failed calls cannot consume
them and unlimited allowances remain unlimited. An explicit handler test exercises
nonzero delegated spending and each rejection action to guard against vacuous setup.

SignalBoard's handler tracks expected signals and successful mutation counts,
including clears and same-value sets. Failed actions leave these ghosts unchanged.
Events are checked independently against the requested action and expected revision.

Passing these tests checks the supplied contracts' behavior. It does not resolve
the approved workflow's prohibition on tokens versus the required launch-token
artifact; that source/authorization conflict is reported separately. Protected
environment-driven deployment checks remain inputs for the verifier. The local
suite does not claim to execute those checks or attest a Sepolia deployment.
