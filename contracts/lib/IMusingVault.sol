// SPDX-License-Identifier: MIT

pragma solidity ^0.8.6;

interface IMusingVault {
    function vest(
        address tokenAddress,
        address beneficiaryAddress,
        uint64 startTimestamp,
        uint64 durationSeconds
    ) external returns (bool);
}
