// SPDX-License-Identifier: MIT

pragma solidity ^0.8.6;

interface IEconomyBond {
    function reserveBalance(address tokenAddress)
        external
        view
        returns (uint256 reserveBalance);

    function getReward(address tokenAddress, uint256 reserveAmount)
        external
        view
        returns (
            uint256 toMint, // token amount to be minted
            uint256 taxAmount
        );

    function getRefund(address tokenAddress, uint256 tokenAmount)
        external
        view
        returns (uint256 mintToRefund, uint256 mintTokenTaxAmount);

    function buy(
        address tokenAddress,
        uint256 reserveAmount,
        uint256 minReward
    ) external returns (uint256);

    function sell(
        address tokenAddress,
        uint256 tokenAmount,
        uint256 minRefund
    ) external returns (uint256);

    function createToken(
        string memory name,
        string memory symbol,
        uint256 maxTokenSupply
    ) external returns (address tokenAddress);

    function exists(address tokenAddress) external view returns (bool);
}
