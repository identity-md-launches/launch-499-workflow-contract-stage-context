# Signal Board — Sepolia demo

SignalBoard lets each account publish one public `bytes32` signal. This contract-stage contribution includes SignalBoard and the required LaunchToken, deterministic unit tests, fuzz and stateful invariant tests, exported ABIs, and integration/deployment documentation. It has no external dependencies. The launch-token requirement conflicts with the token-free product brief; the concrete conflict is recorded below for independent review.

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

`src/LaunchToken.sol:LaunchToken` is a plain ERC-20 named **Signal Board**, symbol **SIGNAL**, with **18 decimals** and a fixed supply of **1,000,000,000 tokens (`10^27` minor units)**. Its argument-free, nonpayable constructor credits the entire supply to `msg.sender` and emits the standard mint `Transfer` event. When deployed through ProjectFactory, the factory receives the supply; neither the application nor the external transaction sender receives a constructor allocation.

Transfers move exactly the specified amount with no fees. Zero-amount transfers and self-transfers are supported; zero-address recipients are rejected, so transfers cannot burn supply. `approve` replaces an allowance (zero revokes it), and `transferFrom` consumes finite allowance. A maximum `uint256` allowance is unlimited and remains unchanged when spent. All successful transfers emit `Transfer`, and approvals emit `Approval`; spending allowance does not emit an additional `Approval` event. Failed calls revert all balance and allowance changes. The standard allowance-replacement ordering risk applies: clients changing an existing nonzero approval should first revoke it and confirm that transaction before approving a new amount.

There is no mint function, burn function, owner, pause, blocklist, fee, upgrade, permit, payable function, or external call. Tokens sent to contracts that cannot transfer them out may be stranded; there is no recovery administrator. SignalBoard neither uses nor requires token holdings, transfers, or approvals. Token tests cover supply, events, transfers, allowances, invalid calls, conservation, and factory deployment.

## Deployment parameters and responsibilities

| Parameter | SignalBoard | LaunchToken |
| --- | --- | --- |
| Network | Ethereum Sepolia, chain ID `11155111` only | Same |
| Artifact | `src/SignalBoard.sol:SignalBoard` | `src/LaunchToken.sol:LaunchToken` |
| Constructor arguments | None (`[]`) | None (`[]`) |
| Deployment ETH | `0` | `0` |
| Initialization | None | None |
| Owner / roles / dependencies | None | None |
| Initial supply recipient | Not applicable | Constructor caller (factory on the launch path) |
| ABI | [`docs/abi/SignalBoard.json`](docs/abi/SignalBoard.json) | [`docs/abi/LaunchToken.json`](docs/abi/LaunchToken.json) |

The bytecode is chain-neutral for local testing; the Sepolia-only restriction must be enforced by the manifest, admission/deployment service, and website. No mainnet deployment is authorized. Constructors grant no administrative roles to their caller, so factory deployment does not strand a privileged role.

The manifest assignment owns `launch.json`. Services own source publication, policy and signed artifact linkage, attestation, admission, deployment, and the resulting `imd-deployment.json`. The independent reviewer checks accepted source and the final manifest before release. These service outcomes are not prerequisites for this contract contribution, and no addresses or deployment attestations are fabricated here. No transactions are broadcast by this project.

**Concrete source/authorization conflict for independent review:** the supplied product brief requests only SignalBoard and explicitly forbids creating, minting, or deploying any token, pool, or allocation. This repair delivers LaunchToken source, tests, and ABI because the current assignment explicitly requires that missing artifact and its fixed-supply launch behavior. It therefore does not implement the brief's token-free preference. The supplied `Project.protected.t.sol` requires a token and preservation of its factory-held supply, while `Token.protected.t.sol` checks token behavior. Delivering this source does not resolve the conflict between the original product authorization and the token-based launch path. The independent review and services must resolve that conflict before deployment; no deployment or pool creation is performed here. Policy allocations belong to the pinned launch policy and services, not either contract's constructor. Supplied protected inputs remain unchanged and are not counted as locally executed tests; their environment-driven harness belongs to the independent verifier.

After attested Sepolia deployment, the separate website stage must consume the actual chain, address, deployment block, and ABI from `imd-deployment.json`, publish its responsive static site to IPFS, and display the contract address and a clear Sepolia test/demo label. It must support read-only access without a wallet, wallet connection, wrong-network detection/switching, transaction pending/confirmed/failed states, and useful errors. No backend, private API, token, faucet, or swap interface is needed. See the [ABI and integration notes](docs/ABI.md) for encoding and bounded event queries.
