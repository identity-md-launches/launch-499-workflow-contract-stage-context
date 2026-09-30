# Signal Board — Sepolia demo

SignalBoard lets each account publish one public `bytes32` signal. This contract-stage contribution includes SignalBoard, the LaunchToken artifact required by the current output check, deterministic unit tests, fuzz and stateful invariant tests, exported ABIs, and integration/deployment documentation. It has no external dependencies. The approved release forbids creating, minting or deploying any ERC-20, launch token, liquidity pool or token allocation. The mandatory token artifact and that release authorization remain incompatible; the conflict below must be resolved before admission or deployment.

## Build and check

With Foundry and Solidity **0.8.26** installed:

```sh
forge build
forge test
forge fmt --check
```

`foundry.toml` pins the compiler, Cancun EVM, optimizer (200 runs), and `bytecode_hash = "none"`. Tests need neither a network nor environment variables. FFI and filesystem cheatcode access are disabled. The test helpers are local ordinary source files; no dependency download or submodule is required. Build outputs under `out/` and `cache/` are generated files.

## Behavior and assumptions

### SignalBoard

- `setSignal(bytes32)` stores a nonzero value for `msg.sender`. A first write or a write after clearing increases `totalActive`; overwriting an active signal does not. Repeating the same value is a successful write.
- `clearSignal()` removes only `msg.sender`'s active signal. Clearing an empty signal reverts with `NoSignal()`; setting zero reverts with `ZeroSignal()`.
- `revisionOf(account)` starts at zero and increases once per successful set or clear, including same-value writes. Clearing preserves the revision history. Failed calls leave state unchanged and emit no change event.
- Each success emits `SignalChanged(address indexed account, bytes32 value, uint256 revision)`. A clear emits zero as the new value. `signalOf(account)` returns zero for an empty slot, and `totalActive()` counts nonzero slots.
- All arithmetic is checked. At the theoretical `uint256` revision limit the next change reverts atomically instead of wrapping. No timestamps, randomness, external calls, or account enumeration affect state transitions.
- The direct caller owns its slot. A smart wallet can participate; an intermediary contract writes its own slot, not the transaction origin's. There is no relayer authorization, signature delegation, or method taking an account to edit.
- Signals and historical events are public and permanent in chain history. Clearing changes current state; it does not erase past messages. Arbitrary nonzero bytes are accepted; UTF-8 validation belongs to the site.

There are no owners, admins, upgrade/pause powers, payable entry points, fallback/receive functions, or funds-handling operations. Normal ETH-bearing calls and deployments fail. ETH forcibly credited by the EVM cannot be prevented or withdrawn and has no effect on signal accounting.

The tests cover lifecycle transitions, event payloads, caller isolation, invalid actions, ETH rejection, arbitrary callers/values, and model-based action sequences across multiple accounts. Invariant checks compare every signal and revision with independently tracked successful actions and recount active slots. Local tests and contributor review do not replace the pipeline's independent review of accepted source and manifest. Slither and Mythril are not part of the checks run here.

### LaunchToken

`src/LaunchToken.sol:LaunchToken` is the previously accepted ERC-20 named **Signal Board**, symbol **SIGNAL**, with **18 decimals** and a fixed supply of **1,000,000,000 tokens (`10^27` minor units)**. Its argument-free, nonpayable constructor credits the entire supply to `msg.sender` and emits the standard mint `Transfer` event. Factory deployment credits the factory, not the external caller or SignalBoard. No initialization follows deployment.

Transfers move exactly the specified amount with no fees. Zero-amount transfers and self-transfers are supported; zero-address recipients are rejected. `approve` replaces an allowance (zero revokes it), and `transferFrom` consumes finite allowance. A maximum `uint256` allowance remains unchanged when spent. Transfers emit `Transfer`; approvals emit `Approval`, but spending allowance does not. Failed calls revert all balance and allowance changes. Clients changing an existing nonzero approval should first revoke it and confirm that transaction before approving a new amount because of the standard allowance-replacement ordering risk.

There is no mint function, burn function, owner, pause, blocklist, fee, upgrade, permit, payable function, or external call. Tokens sent to contracts that cannot transfer them out may be stranded; there is no recovery administrator. SignalBoard neither uses nor requires token holdings, transfers, or approvals. Restored token tests cover supply, events, transfers, allowances, invalid calls, conservation, and factory deployment. The source, tests and ABI are restored unchanged from the accepted version; including them repairs the missing-artifact check but does not implement the approved token-free release.

## Deployment parameters and responsibilities

| Parameter | SignalBoard | LaunchToken |
| --- | --- | --- |
| Network / authorization | Ethereum Sepolia, chain ID `11155111` only | Deployment not authorized; see conflict below |
| Artifact | `src/SignalBoard.sol:SignalBoard` | `src/LaunchToken.sol:LaunchToken` |
| Constructor arguments | None (`[]`) | None (`[]`) |
| Deployment ETH | `0` | `0` |
| Initialization | None | None |
| Owner / roles / dependencies | None | None |
| Initial supply recipient | Not applicable | Constructor caller |
| ABI | [`docs/abi/SignalBoard.json`](docs/abi/SignalBoard.json) | [`docs/abi/LaunchToken.json`](docs/abi/LaunchToken.json) |

The bytecode is chain-neutral for local testing; the Sepolia-only restriction must be enforced by the manifest, admission/deployment service, and website. No mainnet deployment is authorized. Constructors grant no administrative roles to their caller, so factory deployment does not strand a privileged role.

The manifest assignment owns `launch.json`. Services own source publication, policy and signed artifact linkage, attestation, admission, deployment, and the resulting `imd-deployment.json`. The independent reviewer checks accepted source and the final manifest before release. These service outcomes are not prerequisites for this contract contribution, and no addresses or deployment attestations are fabricated here. No transactions are broadcast by this project.

**Release authorization and admission:** revision finding `b88bd05a340299ca34e8b78036eb42e71702f9bf2d99d3982ce1b35d21e49890` was reproduced against the accepted source with `testFactoryStyleDeploymentMintsToImmediateDeployerAndEmitsMint`: calling the local factory as `address(0xA11CE)` minted `10^27` units to the factory, emitted `Transfer(address(0), factory, 10^27)`, and gave the external caller zero. Subsequent SignalBoard deployment left that supply intact. Removing LaunchToken caused the reported output check to fail. This repair restores its accepted source, tests and ABI unchanged and preserves SignalBoard's implementation, tests and ABI. The finding is disputed as a source-only repair under the current mandatory-artifact requirement, not as a factual authorization conflict. The conflict remains an admission blocker, recorded in `.imd-responses.json`. Restoring a build artifact and passing local tests do not authorize a token launch.

**Outstanding service conflict:** `launch.json` is absent from this revision's working tree. The reviewer-reported manifest selecting LaunchToken and an ETH pool must not be admitted or reused. The supplied `evm_project` mode and `Project.protected.t.sol` require a token and factory-held supply, so they cannot represent this authorized release. Services must provide a supported application-only Sepolia deployment path and corresponding output/protected checks, and the manifest assignment and independent reviewer must verify that only SignalBoard is selected, with no token, pool or allocations, before admission. Alternatively, the requester must explicitly revise the release authorization to permit token creation, minting, deployment, a pool and policy allocations. This source revision supplies neither that authorization nor a service change. Do not substitute a zero-supply token, fabricate a manifest kind or fields, or weaken the supplied protected tests. Those inputs remain unchanged and were inspected, not executed locally. The current release authorization remains token-free; deploying through a token-mandatory mode remains blocked. Policy allocation and signed artifact linkage belong to services, not these constructors.

After attested Sepolia deployment, the separate website stage must consume the actual chain, address, deployment block, and ABI from `imd-deployment.json`, publish its responsive static site to IPFS, and display the contract address and a clear Sepolia test/demo label. It must support read-only access without a wallet, wallet connection, wrong-network detection/switching, transaction pending/confirmed/failed states, and useful errors. No backend, private API, token, faucet, or swap interface is needed. See the [ABI and integration notes](docs/ABI.md) for encoding and bounded event queries.
