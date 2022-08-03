// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

// This contract is used for local testing
contract WAVAX is ERC20, ERC20Burnable {
    event Deposit(address indexed account, uint256 amount);
    event Withdraw(address indexed account, uint256 amount);

    constructor() ERC20("Wrapped AVAX", "WAVAX") {}

    fallback() external payable {
        deposit();
    }

    receive() external payable {
        deposit();
    }

    function deposit() public payable {
        _mint(msg.sender, msg.value);
        emit Deposit(msg.sender, msg.value);
    }

    function withdraw(uint256 _amount) public {
        burn(_amount);
        payable(msg.sender).transfer(_amount);
        emit Withdraw(msg.sender, _amount);
    }
}
