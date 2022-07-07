// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "./lib/IUniswapV2Router02.sol";
import "./lib/IUniswapV2Factory.sol";
import "./lib/IEconomyBond.sol";
import "./lib/IWAVAX.sol";
import "./lib/Math.sol";

/**
 * @title MusingZap v1.0.0
 */

contract MusingZap is Context {
    using SafeERC20 for IERC20;

    uint256 private constant BUY_TAX = 3;
    uint256 private constant SELL_TAX = 13;
    uint256 private constant MAX_TAX = 1000;

    address private constant DEFAULT_BENEFICIARY =
        0x1908eeb25102d1BCd7B6baFE55e84FE6737310c5;

    // MARK: - Mainnet configs

    // IUniswapV2Factory private constant PANCAKE_FACTORY = IUniswapV2Factory(0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73);
    // IUniswapV2Router02 private constant PANCAKE_ROUTER = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);
    // IEconomyBond private constant BOND = IEconomyBond(0x8BBac0C7583Cc146244a18863E708bFFbbF19975);
    // uint256 private constant DEAD_LINE = 0xf000000000000000000000000000000000000000000000000000000000000000;
    // address private constant WAVAX_CONTRACT = address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);

    // MARK: - Testnet configs

    IUniswapV2Factory private constant PANCAKE_FACTORY =
        IUniswapV2Factory(0x6725F303b657a9451d8BA641348b6761A6CC7a17);
    IUniswapV2Router02 private constant PANCAKE_ROUTER =
        IUniswapV2Router02(0xD99D1c33F9fC3444f8101754aBC46c52416550D1);
    IEconomyBond private constant BOND =
        IEconomyBond(0x38B587718a076A9fF60ef8253cEb1022db4a3137);
    uint256 private constant DEAD_LINE =
        0xf000000000000000000000000000000000000000000000000000000000000000;
    address private constant WAVAX_CONTRACT =
        address(0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd);

    constructor() {}

    receive() external payable {}

    // Other tokens -> Economy Tokens
    function estimateZapIn(
        address from,
        address to,
        uint256 fromAmount
    )
        external
        view
        returns (uint256 tokensToReceive, uint256 mintTokenTaxAmount)
    {
        uint256 mintAmount;

        if (from == WAVAX_CONTRACT) {
            mintAmount = fromAmount;
        } else {
            address[] memory path = _getPathToWavax(from);

            mintAmount = PANCAKE_ROUTER.getAmountsOut(fromAmount, path)[
                path.length - 1
            ];
        }

        return BOND.getMusingReward(to, mintAmount);
    }

    function estimateZapInInitial(address from, uint256 fromAmount)
        external
        view
        returns (uint256 tokensToReceive, uint256 mintTokenTaxAmount)
    {
        uint256 mintAmount;

        if (from == WAVAX_CONTRACT) {
            mintAmount = fromAmount;
        } else {
            address[] memory path = _getPathToWavax(from);

            mintAmount = PANCAKE_ROUTER.getAmountsOut(fromAmount, path)[
                path.length - 1
            ];
        }

        uint256 taxAmount = (mintAmount * BUY_TAX) / MAX_TAX;
        uint256 newSupply = Math.floorSqrt(2 * 1e18 * (mintAmount - taxAmount));

        return (newSupply, taxAmount);
    }

    // Get required WAVAX token amount to buy X amount of Economy tokens
    function getReserveAmountToBuy(address tokenAddress, uint256 tokensToBuy)
        public
        view
        returns (uint256)
    {
        IERC20 token = IERC20(tokenAddress);

        uint256 newTokenSupply = token.totalSupply() + tokensToBuy;
        uint256 reserveRequired = (newTokenSupply**2 - token.totalSupply()**2) /
            (20 * 1e18);
        reserveRequired = (reserveRequired * MAX_TAX) / (MAX_TAX - BUY_TAX); // Deduct tax amount

        return reserveRequired;
    }

    // WAVAX and others -> Economy Tokens (parameter)
    function estimateZapInReverse(
        address from,
        address to,
        uint256 tokensToReceive
    )
        external
        view
        returns (uint256 fromAmountRequired, uint256 wavaxTokenTaxAmount)
    {
        uint256 reserveRequired = getReserveAmountToBuy(to, tokensToReceive);

        if (from == WAVAX_CONTRACT) {
            fromAmountRequired = reserveRequired;
        } else {
            address[] memory path = _getPathToWavax(from);

            fromAmountRequired = PANCAKE_ROUTER.getAmountsIn(
                reserveRequired,
                path
            )[0];
        }

        wavaxTokenTaxAmount = (reserveRequired * BUY_TAX) / MAX_TAX;
    }

    function estimateZapInReverseInitial(address from, uint256 tokensToReceive)
        external
        view
        returns (uint256 fromAmountRequired, uint256 wavaxTokenTaxAmount)
    {
        uint256 reserveRequired = tokensToReceive**2 / 20e18;

        if (from == WAVAX_CONTRACT) {
            fromAmountRequired = reserveRequired;
        } else {
            address[] memory path = _getPathToWavax(from);

            fromAmountRequired = PANCAKE_ROUTER.getAmountsIn(
                reserveRequired,
                path
            )[0];
        }

        wavaxTokenTaxAmount = (reserveRequired * BUY_TAX) / MAX_TAX;
    }

    // Economy Tokens (parameter) -> WAVAX and others
    function estimateZapOut(
        address from,
        address to,
        uint256 fromAmount
    )
        external
        view
        returns (uint256 toAmountToReceive, uint256 wavaxTokenTaxAmount)
    {
        uint256 wavaxToRefund;
        (wavaxToRefund, wavaxTokenTaxAmount) = BOND.getBurnRefund(
            from,
            fromAmount
        );

        if (to == WAVAX_CONTRACT) {
            toAmountToReceive = wavaxToRefund;
        } else {
            address[] memory path = _getPathFromWavax(to);

            toAmountToReceive = PANCAKE_ROUTER.getAmountsOut(
                wavaxToRefund,
                path
            )[path.length - 1];
        }
    }

    // Get amount of Economy tokens to receive X amount of WAVAX tokens
    function getTokenAmountFor(address tokenAddress, uint256 wavaxTokenAmount)
        public
        view
        returns (uint256)
    {
        IERC20 token = IERC20(tokenAddress);

        uint256 reserveAfterSell = BOND.reserveBalance(tokenAddress) -
            wavaxTokenAmount;
        uint256 supplyAfterSell = Math.floorSqrt(20 * 1e18 * reserveAfterSell);

        return token.totalSupply() - supplyAfterSell;
    }

    // Economy Tokens -> WAVAX and others (parameter)
    function estimateZapOutReverse(
        address from,
        address to,
        uint256 toAmount
    )
        external
        view
        returns (uint256 tokensRequired, uint256 wavaxTokenTaxAmount)
    {
        uint256 wavaxTokenAmount;
        if (to == WAVAX_CONTRACT) {
            wavaxTokenAmount = toAmount;
        } else {
            address[] memory path = _getPathFromWavax(to);
            wavaxTokenAmount = PANCAKE_ROUTER.getAmountsIn(toAmount, path)[0];
        }

        wavaxTokenTaxAmount = (wavaxTokenAmount * SELL_TAX) / MAX_TAX;
        tokensRequired = getTokenAmountFor(
            from,
            wavaxTokenAmount + wavaxTokenTaxAmount
        );
    }

    function zapInAVAX(
        address to,
        uint256 minAmountOut,
        address beneficiary
    ) public payable {
        uint256 mintAmount = msg.value;
        // Wrap AVAX to WAVAX
        IWAVAX(WAVAX_CONTRACT).deposit{value: mintAmount}();

        // Buy target tokens with swapped WAVAX
        _buyWavaxTokenAndSend(
            to,
            mintAmount,
            minAmountOut,
            _getBeneficiary(beneficiary)
        );
    }

    function zapIn(
        address from,
        address to,
        uint256 amountIn,
        uint256 minAmountOut,
        address beneficiary
    ) public {
        // First, pull tokens to this contract
        IERC20 token = IERC20(from);
        require(
            token.allowance(_msgSender(), address(this)) >= amountIn,
            "NOT_ENOUGH_ALLOWANCE"
        );
        IERC20(from).safeTransferFrom(_msgSender(), address(this), amountIn);

        // Swap to WAVAX if necessary
        uint256 mintAmount;
        if (from == WAVAX_CONTRACT) {
            mintAmount = amountIn;
        } else {
            mintAmount = _swap(from, WAVAX_CONTRACT, amountIn);
        }

        // Finally, buy target tokens with swapped WAVAX
        _buyWavaxTokenAndSend(
            to,
            mintAmount,
            minAmountOut,
            _getBeneficiary(beneficiary)
        );
    }

    function createAndZapIn(
        string memory name,
        string memory symbol,
        uint256 maxTokenSupply,
        address token,
        uint256 tokenAmount,
        uint256 minAmountOut,
        address beneficiary
    ) external {
        address newToken = BOND.createToken(name, symbol, maxTokenSupply);

        // We need `minAmountOut` here token->WAVAX can be front ran and slippage may happen
        zapIn(
            token,
            newToken,
            tokenAmount,
            minAmountOut,
            _getBeneficiary(beneficiary)
        );
    }

    function createAndZapInAVAX(
        string memory name,
        string memory symbol,
        uint256 maxTokenSupply,
        uint256 minAmountOut,
        address beneficiary
    ) external payable {
        address newToken = BOND.createToken(name, symbol, maxTokenSupply);

        zapInAVAX(newToken, minAmountOut, _getBeneficiary(beneficiary));
    }

    function zapOut(
        address from,
        address to,
        uint256 amountIn,
        uint256 minAmountOut,
        address beneficiary
    ) external {
        uint256 mintAmount = _receiveAndSwapToWavax(
            from,
            amountIn,
            _getBeneficiary(beneficiary)
        );

        // Swap to WAVAX if necessary
        IERC20 toToken;
        uint256 amountOut;
        if (to == WAVAX_CONTRACT) {
            toToken = IERC20(WAVAX_CONTRACT);
            amountOut = mintAmount;
        } else {
            toToken = IERC20(to);
            amountOut = _swap(WAVAX_CONTRACT, to, mintAmount);
        }

        // Check slippage limit
        require(amountOut >= minAmountOut, "ZAP_SLIPPAGE_LIMIT_EXCEEDED");

        // Send the token to the user
        require(
            toToken.transfer(_msgSender(), amountOut),
            "BALANCE_TRANSFER_FAILED"
        );
    }

    function zapOutAVAX(
        address from,
        uint256 amountIn,
        uint256 minAmountOut,
        address beneficiary
    ) external {
        uint256 amountOut = _receiveAndSwapToWavax(
            from,
            amountIn,
            _getBeneficiary(beneficiary)
        );

        // Unwrap wavax to avax
        IWAVAX(WAVAX_CONTRACT).withdraw(amountOut);

        // Check slippage limit
        require(amountOut >= minAmountOut, "ZAP_SLIPPAGE_LIMIT_EXCEEDED");

        // TODO: FIXME!!!!!

        // Send AVAX to user
        (bool sent, ) = _msgSender().call{value: amountOut}("");
        require(sent, "AVAX_TRANSFER_FAILED");
    }

    function _buyWavaxTokenAndSend(
        address tokenAddress,
        uint256 mintAmount,
        uint256 minAmountOut,
        address beneficiary
    ) internal {
        // Finally, buy target tokens with swapped WAVX (can be reverted due to slippage limit)
        BOND.buy(
            tokenAddress,
            mintAmount,
            minAmountOut,
            _getBeneficiary(beneficiary)
        );

        // BOND.buy doesn't return any value, so we need to calculate the purchased amount
        IERC20 token = IERC20(tokenAddress);
        require(
            token.transfer(_msgSender(), token.balanceOf(address(this))),
            "BALANCE_TRANSFER_FAILED"
        );
    }

    function _receiveAndSwapToWavax(
        address from,
        uint256 amountIn,
        address beneficiary
    ) internal returns (uint256) {
        // First, pull tokens to this contract
        IERC20 token = IERC20(from);
        require(
            token.allowance(_msgSender(), address(this)) >= amountIn,
            "NOT_ENOUGH_ALLOWANCE"
        );
        IERC20(from).safeTransferFrom(_msgSender(), address(this), amountIn);

        // Approve infinitely to this contract
        if (token.allowance(address(this), address(BOND)) < amountIn) {
            require(
                token.approve(
                    address(BOND),
                    0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
                ),
                "APPROVE_FAILED"
            );
        }

        // Sell tokens to WAVAX
        // NOTE: ignore minRefund (set as 0) for now, we should check it later on zapOut
        BOND.sell(from, amountIn, 0, _getBeneficiary(beneficiary));
        IERC20 wavaxToken = IERC20(WAVAX_CONTRACT);

        return wavaxToken.balanceOf(address(this));
    }

    function _getPathToWavax(address from)
        internal
        pure
        returns (address[] memory path)
    {
        path = new address[](2);
        path[0] = from;
        path[1] = WAVAX_CONTRACT;
    }

    function _getPathFromWavax(address to)
        internal
        pure
        returns (address[] memory path)
    {
        path = new address[](2);
        path[0] = WAVAX_CONTRACT;
        path[1] = to;
    }

    function _approveToken(address tokenAddress, address spender) internal {
        IERC20 token = IERC20(tokenAddress);
        if (token.allowance(address(this), spender) > 0) {
            return;
        } else {
            token.safeApprove(spender, type(uint256).max);
        }
    }

    /**
        @notice This function is used to swap ERC20 <> ERC20
        @param from The token address to swap from.
        @param to The token address to swap to.
        @param amount The amount of tokens to swap
        @return boughtAmount The quantity of tokens bought
    */
    function _swap(
        address from,
        address to,
        uint256 amount
    ) internal returns (uint256 boughtAmount) {
        if (from == to) {
            return amount;
        }

        _approveToken(from, address(PANCAKE_ROUTER));

        address[] memory path;

        if (to == WAVAX_CONTRACT) {
            path = _getPathToWavax(from);
        } else if (from == WAVAX_CONTRACT) {
            path = _getPathFromWavax(to);
        } else {
            revert("INVALID_PATH");
        }

        // Check if there's a liquidity pool for paths
        // path.length is always 2 or 3
        for (uint8 i = 0; i < path.length - 1; i++) {
            address pair = PANCAKE_FACTORY.getPair(path[i], path[i + 1]);
            require(pair != address(0), "INVALID_SWAP_PATH");
        }

        boughtAmount = PANCAKE_ROUTER.swapExactTokensForTokens(
            amount,
            1, // amountOutMin
            path,
            address(this), // to: Recipient of the output tokens
            DEAD_LINE
        )[path.length - 1];

        require(boughtAmount > 0, "SWAP_ERROR");
    }

    // Prevent self referral
    function _getBeneficiary(address beneficiary)
        internal
        view
        returns (address)
    {
        if (beneficiary == address(0) || beneficiary == _msgSender()) {
            return DEFAULT_BENEFICIARY;
        } else {
            return beneficiary;
        }
    }
}
