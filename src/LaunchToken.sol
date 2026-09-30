// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title Signal Board launch token
/// @notice Fixed-supply ERC-20; the complete supply belongs to the constructor caller.
/// @dev No privileged roles, external calls, fees, burns, or post-deployment minting.
contract LaunchToken {
    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);
    error ERC20InvalidSender(address sender);
    error ERC20InvalidReceiver(address receiver);
    error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);
    error ERC20InvalidApprover(address approver);
    error ERC20InvalidSpender(address spender);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    string public constant name = "Signal Board";
    string public constant symbol = "SIGNAL";
    uint8 public constant decimals = 18;
    uint256 public constant totalSupply = 1_000_000_000 * 10 ** 18;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    /// @dev Nonpayable and argument-free for factory deployment; no initialization is needed.
    constructor() {
        balanceOf[msg.sender] = totalSupply;
        emit Transfer(address(0), msg.sender, totalSupply);
    }

    /// @notice Move exactly value units from the caller to a nonzero recipient.
    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    /// @notice Replace the caller's allowance for spender. Zero revokes approval.
    /// @dev The maximum uint256 allowance is treated as unlimited by transferFrom.
    function approve(address spender, uint256 value) external returns (bool) {
        if (msg.sender == address(0)) revert ERC20InvalidApprover(address(0));
        if (spender == address(0)) revert ERC20InvalidSpender(address(0));
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    /// @notice Move value units using the caller's allowance, including for self-transfers.
    /// @dev Finite allowance consumption does not emit Approval; query allowance for current state.
    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        uint256 available = allowance[from][msg.sender];
        if (available != type(uint256).max) {
            if (available < value) revert ERC20InsufficientAllowance(msg.sender, available, value);
            allowance[from][msg.sender] = available - value;
        }
        _transfer(from, to, value);
        return true;
    }

    function _transfer(address from, address to, uint256 value) private {
        if (from == address(0)) revert ERC20InvalidSender(address(0));
        if (to == address(0)) revert ERC20InvalidReceiver(address(0));
        uint256 available = balanceOf[from];
        if (available < value) revert ERC20InsufficientBalance(from, available, value);
        balanceOf[from] = available - value;
        balanceOf[to] += value;
        emit Transfer(from, to, value);
    }
}
