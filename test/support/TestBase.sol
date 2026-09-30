// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @dev Only the native Foundry cheatcodes needed by the local tests.
interface Vm {
    struct Log {
        bytes32[] topics;
        bytes data;
        address emitter;
    }

    function assume(bool condition) external;
    function prank(address sender) external;
    function startPrank(address sender) external;
    function stopPrank() external;
    function expectRevert(bytes4 revertData) external;
    function recordLogs() external;
    function getRecordedLogs() external returns (Log[] memory logs);
    function deal(address account, uint256 balance) external;
}

abstract contract TestBase {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function assertTrue(bool condition) internal pure {
        require(condition, "assertTrue failed");
    }

    function assertTrue(bool condition, string memory reason) internal pure {
        require(condition, reason);
    }

    function assertFalse(bool condition, string memory reason) internal pure {
        require(!condition, reason);
    }

    function assertEq(uint256 actual, uint256 expected) internal pure {
        require(actual == expected, "uint256 mismatch");
    }

    function assertEq(uint256 actual, uint256 expected, string memory reason) internal pure {
        require(actual == expected, reason);
    }

    function assertEq(bytes32 actual, bytes32 expected) internal pure {
        require(actual == expected, "bytes32 mismatch");
    }

    function assertEq(bytes32 actual, bytes32 expected, string memory reason) internal pure {
        require(actual == expected, reason);
    }

    function assertEq(address actual, address expected, string memory reason) internal pure {
        require(actual == expected, reason);
    }
}
