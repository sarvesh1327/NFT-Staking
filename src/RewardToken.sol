
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.21;

import {ERC20} from  "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract RewardToken is ERC20 {
    constructor() ERC20("RewardToken", "RT") {
        _mint(msg.sender, 10**10 * 10 ** 18);
    }
}