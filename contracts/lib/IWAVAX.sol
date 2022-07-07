// SPDX-License-Identifier: MIT

pragma solidity ^0.8.6;

interface IWAVAX {
    function deposit() external payable;
    function withdraw(uint) external;
}