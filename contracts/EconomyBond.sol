// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./EconomyFactory.sol";
import "./ERC20/EconomyToken.sol";
import "./lib/Math.sol";
import "./lib/BancorFormula.sol";

/**
 * @title Musing Economy Bond
 *
 * Providing liquidity for Musing tokens with a bonding curve.
 */
contract EconomyBond is EconomyFactory {
    using SafeMath for uint256;
    uint256 private constant BUY_TAX = 3; // 0.3%
    uint256 private constant SELL_TAX = 13; // 1.3%
    uint256 private constant MAX_TAX = 1000;

    // Token => Reserve Balance
    mapping(address => uint256) public _reserveBalance;

    EconomyToken private RESERVE_TOKEN; // Any IERC20
    address internal immutable bancorFormula; // BancorFormula contract address
    uint32 internal immutable cw; // Reserve weight
    address public musingRewards; // Reward Pool Address
    address public defaultBeneficiary;

    bool private _initialized = false;

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

    constructor(
        address baseToken,
        address implementation,
        address musingRewardPool,
        address _bancorFormula,
        uint32 _cw
    ) EconomyFactory(implementation) {
        RESERVE_TOKEN = EconomyToken(baseToken);
        musingRewards = musingRewardPool;
        defaultBeneficiary = address(
            0x1908eeb25102d1BCd7B6baFE55e84FE6737310c5
        );

        bancorFormula = _bancorFormula;
        cw = _cw;
    }

    modifier initialized() {
        require(_initialized, "BancorFormula is not Initialized");
        _;
    }

    modifier _checkBondExists(address tokenAddress) {
        require(maxSupply[tokenAddress] > 0, "TOKEN_NOT_FOUND");
        _;
    }

    function init() public payable virtual {
        require(!_initialized);
        BancorFormula(bancorFormula).init();
        _initialized = true;
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

    /// @notice Returns reserve balance
    /// @dev calls balanceOf in reserve token contract
    /**
     *  Note Reserve Balance, precision = 6
     *  Reserve balance will be zero initially, but in theory should be 1 reserve token.
     *  We can assume the contract has 1USDC initially, since it cannot be withdrawn anyway.
     */
    function reserveBalance(address tokenAddress)
        public
        view
        virtual
        returns (uint256)
    {
        return _reserveBalance[tokenAddress];
    }

    function reserveWeight() public view virtual returns (uint32) {
        return cw;
    }

    function pricePPM(address tokenAddress)
        public
        view
        initialized
        returns (uint256)
    {
        return
            BancorFormula(bancorFormula).currentPrice(
                EconomyToken(tokenAddress).totalSupply(),
                reserveBalance(tokenAddress),
                reserveWeight()
            );
    }

    // address beneficiary
    function createEconomy(
        string memory name,
        string memory symbol,
        uint256 maxTokenSupply,
        uint256 initialReserve,
        uint256 initialRewardPool
    ) external {
        require(initialReserve >= 1e18, "Invalid Initial Reserve");

        address newToken = createToken(name, symbol, maxTokenSupply);
        // Mint tokens to reward pool contract
        EconomyToken(newToken).mint(musingRewards, initialRewardPool);

        require(
            RESERVE_TOKEN.transferFrom(
                _msgSender(),
                address(this),
                initialReserve
            ),
            "RESERVE_TOKEN_TRANSFER_FAILED"
        );

        _reserveBalance[newToken] = initialReserve;
    }

    /**
     * @dev Use the simplest bonding curve (y = x) as we can adjust total supply of reserve tokens to adjust slope
     * Price = SLOPE * totalSupply = totalSupply (where slope = 1)
     */
    function getReward(address tokenAddress, uint256 reserveAmount)
        public
        view
        _checkBondExists(tokenAddress)
        returns (uint256, uint256)
    {
        uint256 taxAmount = (reserveAmount * BUY_TAX) / MAX_TAX;
        uint256 toMint = BancorFormula(bancorFormula).calculatePurchaseAmount(
            EconomyToken(tokenAddress).totalSupply(),
            reserveBalance(tokenAddress),
            reserveWeight(),
            reserveAmount - taxAmount
            // reserveAmount
        );

        return (toMint, taxAmount);
    }

    function getRefund(address tokenAddress, uint256 tokenAmount)
        public
        view
        _checkBondExists(tokenAddress)
        returns (uint256, uint256)
    {
        uint256 reserveAmount = BancorFormula(bancorFormula)
            .calculateSaleAmount(
                EconomyToken(tokenAddress).totalSupply(),
                reserveBalance(tokenAddress),
                reserveWeight(),
                tokenAmount
            );
        uint256 taxAmount = (reserveAmount * SELL_TAX) / MAX_TAX;

        return (reserveAmount - taxAmount, taxAmount);
        // return (reserveAmount, taxAmount);
    }

    function buy(
        address tokenAddress,
        uint256 reserveAmount,
        uint256 minReward,
        address beneficiary
    ) public {
        (uint256 rewardTokens, uint256 taxAmount) = getReward(
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
                // reserveAmount
            ),
            "RESERVE_TOKEN_TRANSFER_FAILED"
        );
        _reserveBalance[tokenAddress] += (reserveAmount - taxAmount);
        // _reserveBalance[tokenAddress] += reserveAmount;

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
        (uint256 refundAmount, uint256 taxAmount) = getRefund(
            tokenAddress,
            tokenAmount
        );
        require(refundAmount >= minRefund, "SLIPPAGE_LIMIT_EXCEEDED");

        // Burn token first
        EconomyToken(tokenAddress).burnFrom(_msgSender(), tokenAmount);

        // Refund reserve tokens to the seller
        _reserveBalance[tokenAddress] -= (refundAmount + taxAmount);
        // _reserveBalance[tokenAddress] -= refundAmount;
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
