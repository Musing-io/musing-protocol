// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../lib/ERC20Initializable.sol";

contract EconomyToken is ERC20Initializable {
    bool private _initialized; // false by default
    address private _owner; // Ownable is implemented manually to meke it compatible with `initializable`

    mapping(address => bool) public AllowedContract;
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    function init(string memory name_, string memory symbol_) external {
        require(_initialized == false, "CONTRACT_ALREADY_INITIALIZED");

        _name = name_;
        _symbol = symbol_;
        _owner = _msgSender();

        _initialized = true;

        emit OwnershipTransferred(address(0), _owner);
    }

    function owner() public view returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    function renounceOwnership() public onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    // NOTE:
    // Disable direct burn function call because it can affect on bonding curve
    // Users can just send the tokens to the token contract address
    // for the same burning effect without changing the totalSupply
    function burnFrom(address account, uint256 amount) public onlyOwner {
        uint256 currentAllowance = allowance(account, _msgSender());
        require(
            currentAllowance >= amount,
            "ERC20: burn amount exceeds allowance"
        );
        _approve(account, _msgSender(), currentAllowance - amount);
        _burn(account, amount);
    }

    // function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
    //     _transfer(sender, recipient, amount);

    //     if (sender == _msgSender() || AllowedContract[_msgSender()]) {
    //         uint256 currentAllowance = allowance(_msgSender(), sender);
    //         require(currentAllowance >= amount, "ERC20: transfer amount(custom) exceeds allowance");
    //         unchecked {
    //             _approve(sender, _msgSender(), currentAllowance - amount);
    //         }
    //     } else {
    //         uint256 currentAllowance = allowance(sender, _msgSender());
    //         require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
    //         unchecked {
    //             _approve(sender, _msgSender(), currentAllowance - amount);
    //         }
    //     }

    //     return true;
    // }

    // function AllowOperator(address _address, bool isAllowed) external onlyOwner {
    //     AllowedContract[_address] = isAllowed;
    // }
}
