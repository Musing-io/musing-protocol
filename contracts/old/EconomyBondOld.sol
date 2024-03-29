// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../EconomyFactory.sol";
import "../ERC20/EconomyToken.sol";
import "../lib/Math.sol";

/**
 * @title Musing Economy Bond
 *
 * Providing liquidity for Musing tokens with a bonding curve.
 */
contract EconomyBondOld is EconomyFactory {
    uint256 private constant BUY_TAX = 3; // 0.3%
    uint256 private constant SELL_TAX = 13; // 1.3%
    uint256 private constant MAX_TAX = 1000;

    // Token => Reserve Balance
    mapping(address => uint256) public reserveBalance;

    EconomyToken private RESERVE_TOKEN; // Any IERC20
    address public defaultBeneficiary;

    event Buy(
        address tokenAddress,
        address buyer,
        uint256 amountMinted,
        uint256 reserveAmount,
        address beneficiary,
        uint256 taxAmount
    );
    event Sell(
        address tokenAddress,
        address seller,
        uint256 amountBurned,
        uint256 refundAmount,
        address beneficiary,
        uint256 taxAmount
    );

    constructor(address baseToken, address implementation)
        EconomyFactory(implementation)
    {
        RESERVE_TOKEN = EconomyToken(baseToken);
        defaultBeneficiary = address(
            0x1908eeb25102d1BCd7B6baFE55e84FE6737310c5
        );
    }

    modifier _checkBondExists(address tokenAddress) {
        require(maxSupply[tokenAddress] > 0, "TOKEN_NOT_FOUND");
        _;
    }

    // MARK: - Utility functions for external calls

    function reserveTokenAddress() external view returns (address) {
        return address(RESERVE_TOKEN);
    }

    function setDefaultBeneficiary(address beneficiary) external onlyOwner {
        require(
            beneficiary != address(0),
            "DEFAULT_BENEFICIARY_CANNOT_BE_NULL"
        );
        defaultBeneficiary = beneficiary;
    }

    function currentPrice(address tokenAddress)
        external
        view
        _checkBondExists(tokenAddress)
        returns (uint256)
    {
        return EconomyToken(tokenAddress).totalSupply();
    }

    function createAndBuy(
        string memory name,
        string memory symbol,
        uint256 maxTokenSupply,
        uint256 reserveAmount,
        address beneficiary
    ) external {
        address newToken = createToken(name, symbol, maxTokenSupply);
        buy(newToken, reserveAmount, 0, beneficiary);
    }

    /**
     * @dev Use the simplest bonding curve (y = x) as we can adjust total supply of reserve tokens to adjust slope
     * Price = SLOPE * totalSupply = totalSupply (where slope = 1)
     */
    function getMusingReward(address tokenAddress, uint256 reserveAmount)
        public
        view
        _checkBondExists(tokenAddress)
        returns (uint256, uint256)
    {
        uint256 taxAmount = (reserveAmount * BUY_TAX) / MAX_TAX;
        uint256 newSupply = Math.floorSqrt(
            20 *
                1e18 *
                ((reserveAmount - taxAmount) + reserveBalance[tokenAddress])
        );
        uint256 toMint = newSupply - EconomyToken(tokenAddress).totalSupply();

        require(newSupply <= maxSupply[tokenAddress], "EXCEEDED_MAX_SUPPLY");

        return (toMint, taxAmount);
    }

    function getBurnRefund(address tokenAddress, uint256 tokenAmount)
        public
        view
        _checkBondExists(tokenAddress)
        returns (uint256, uint256)
    {
        uint256 newTokenSupply = EconomyToken(tokenAddress).totalSupply() -
            tokenAmount;

        // Should be the same as: (1/2 * (totalSupply**2 - newTokenSupply**2);
        uint256 reserveAmount = reserveBalance[tokenAddress] -
            (newTokenSupply**2 / (20 * 1e18));
        uint256 taxAmount = (reserveAmount * SELL_TAX) / MAX_TAX;

        return (reserveAmount - taxAmount, taxAmount);
    }

    function buy(
        address tokenAddress,
        uint256 reserveAmount,
        uint256 minReward,
        address beneficiary
    ) public {
        (uint256 rewardTokens, uint256 taxAmount) = getMusingReward(
            tokenAddress,
            reserveAmount
        );
        require(rewardTokens >= minReward, "SLIPPAGE_LIMIT_EXCEEDED");

        // Transfer reserve tokens
        require(
            RESERVE_TOKEN.transferFrom(
                _msgSender(),
                address(this),
                reserveAmount - taxAmount
            ),
            "RESERVE_TOKEN_TRANSFER_FAILED"
        );
        reserveBalance[tokenAddress] += (reserveAmount - taxAmount);

        // Mint reward tokens to the buyer
        EconomyToken(tokenAddress).mint(_msgSender(), rewardTokens);

        // Pay tax to the beneficiary / Send to the default beneficiary if not set (or abused)
        address actualBeneficiary = beneficiary;
        if (beneficiary == address(0) || beneficiary == _msgSender()) {
            actualBeneficiary = defaultBeneficiary;
        }
        RESERVE_TOKEN.transferFrom(_msgSender(), actualBeneficiary, taxAmount);

        emit Buy(
            tokenAddress,
            _msgSender(),
            rewardTokens,
            reserveAmount,
            actualBeneficiary,
            taxAmount
        );
    }

    function sell(
        address tokenAddress,
        uint256 tokenAmount,
        uint256 minRefund,
        address beneficiary
    ) public {
        (uint256 refundAmount, uint256 taxAmount) = getBurnRefund(
            tokenAddress,
            tokenAmount
        );
        require(refundAmount >= minRefund, "SLIPPAGE_LIMIT_EXCEEDED");

        // Burn token first
        EconomyToken(tokenAddress).burnFrom(_msgSender(), tokenAmount);

        // Refund reserve tokens to the seller
        reserveBalance[tokenAddress] -= (refundAmount + taxAmount);
        require(
            RESERVE_TOKEN.transfer(_msgSender(), refundAmount),
            "RESERVE_TOKEN_TRANSFER_FAILED"
        );

        // Pay tax to the beneficiary / Send to the default beneficiary if not set (or abused)
        address actualBeneficiary = beneficiary;
        if (beneficiary == address(0) || beneficiary == _msgSender()) {
            actualBeneficiary = defaultBeneficiary;
        }
        RESERVE_TOKEN.transfer(actualBeneficiary, taxAmount);

        emit Sell(
            tokenAddress,
            _msgSender(),
            tokenAmount,
            refundAmount,
            actualBeneficiary,
            taxAmount
        );
    }
}
