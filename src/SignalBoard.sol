// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title Signal Board
/// @notice A public, per-caller bytes32 signal registry for the Sepolia demo.
/// @dev Deployment requires no arguments, ETH, privileged account, or initialization.
contract SignalBoard {
    /// @notice Zero is reserved for an absent signal; use clearSignal to remove one.
    error ZeroSignal();

    /// @notice The caller has no signal to clear.
    error NoSignal();

    /// @notice Emitted once for each successful set or clear, including same-value sets.
    /// @param account The caller whose signal changed.
    /// @param value The new signal, or zero after clearing.
    /// @param revision The caller's revision after this change.
    event SignalChanged(address indexed account, bytes32 value, uint256 revision);

    /// @notice The current signal for an account, or zero when absent.
    mapping(address => bytes32) public signalOf;

    /// @notice Successful changes by an account; clearing never resets this counter.
    mapping(address => uint256) public revisionOf;

    /// @notice The number of accounts with a nonzero signal.
    uint256 public totalActive;

    /// @notice Set or replace your signal with any nonzero bytes32 value.
    /// @dev The contract accepts raw bytes; text encoding is a frontend concern.
    function setSignal(bytes32 value) external {
        if (value == bytes32(0)) revert ZeroSignal();

        if (signalOf[msg.sender] == bytes32(0)) ++totalActive;
        signalOf[msg.sender] = value;
        uint256 revision = ++revisionOf[msg.sender];

        emit SignalChanged(msg.sender, value, revision);
    }

    /// @notice Clear your active signal, preserving and incrementing your revision.
    function clearSignal() external {
        if (signalOf[msg.sender] == bytes32(0)) revert NoSignal();

        delete signalOf[msg.sender];
        --totalActive;
        uint256 revision = ++revisionOf[msg.sender];

        emit SignalChanged(msg.sender, bytes32(0), revision);
    }
}
