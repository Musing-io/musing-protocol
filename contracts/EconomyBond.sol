// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./EconomyFactory.sol";
import "./ERC20/EconomyToken.sol";
import "./lib/Math.sol";
import "./lib/BancorFormula.sol";
import "./lib/IWAVAX.sol";
import "./lib/IMusingVault.sol";

/**
 * @title Musing Economy Bond
 *
 * Providing liquidity for Musing tokens with a bonding curve.
 */
contract EconomyBond is EconomyFactory {
    using SafeMath for uint256;
    uint256 private constant BUY_TAX = 5; // 0.5%
    uint256 private constant SELL_TAX = 15; // 1.5%
    uint256 private constant MAX_TAX = 1000;

    // Token => Reserve Balance
    mapping(address => uint256) public _reserveBalance;

    EconomyToken private RESERVE_TOKEN; // Any IERC20
    IMusingVault public MUSING_VAULT; // Musing Vault
    address internal bancorFormula; // BancorFormula contract address
    uint32 internal cw; // Reserve weight
    address public defaultBeneficiary;
    address private constant WAVAX_CONTRACT =
        address(0xd00ae08403B9bbb9124bB305C09058E32C39A48c);

    bool private _initialized = false;
    /*
    - Front-running attacks are currently mitigated by the following mechanisms:
    - gas price limit prevents users from having control over the order of execution
    */
    uint256 public gasPrice = 0 wei; // maximum gas price for bancor transactions

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
    event Burn(address tokenAddress, address account, uint256 amountBurned);

    constructor(
        address baseToken,
        address implementation,
        address _bancorFormula,
        uint32 _cw
    ) EconomyFactory(implementation) {
        RESERVE_TOKEN = EconomyToken(baseToken);
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

    // verifies that the gas price is lower than the universal limit
    modifier validGasPrice() {
        assert(tx.gasprice <= gasPrice);
        _;
    }

    function init(address _musingVault, address _defaultBeneficiary)
        public
        payable
        virtual
    {
        require(!_initialized);
        BancorFormula(bancorFormula).init();
        MUSING_VAULT = IMusingVault(_musingVault);
        defaultBeneficiary = _defaultBeneficiary;
        _initialized = true;
        gasPrice = 27500000000; // 27.5 gwei or navax
    }

    function updateFormula(address _formula) external onlyOwner {
        require(_formula != address(0), "Invalid Address");

        bancorFormula = _formula;
        _initialized = false; // call init after updating bancor formula
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

    function setMusingVaultAddress(address _musingVault) external onlyOwner {
        require(_musingVault != address(0), "MUSING_VAULT_CANNOT_BE_NULL");
        MUSING_VAULT = IMusingVault(_musingVault);
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

    function createEconomy(
        string memory name,
        string memory symbol,
        uint256 maxTokenSupply,
        uint256 initialReserve,
        uint256 initialRewardPool,
        uint64 startTimestamp,
        uint64 durationSeconds
    ) external {
        require(
            initialRewardPool >= 1e18 && initialRewardPool < maxTokenSupply,
            "Invalid Initial Reward Pool"
        );
        require(initialReserve >= 1e18, "Invalid Initial Reserve");
        require(startTimestamp > block.timestamp, "Invalid start timestamp");
        require(durationSeconds > 0, "Invalid duration");

        address newToken = createToken(name, symbol, maxTokenSupply);
        // Mint tokens to reward pool contract
        EconomyToken(newToken).mint(address(MUSING_VAULT), initialRewardPool);
        // Vest tokens
        MUSING_VAULT.vest(
            newToken,
            defaultBeneficiary,
            startTimestamp,
            durationSeconds
        );

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

    function createEconomyInAvax(
        string memory name,
        string memory symbol,
        uint256 maxTokenSupply,
        uint256 initialRewardPool,
        uint64 startTimestamp,
        uint64 durationSeconds
    ) external payable {
        uint256 initialReserve = msg.value;
        require(
            initialRewardPool >= 1e18 && initialRewardPool < maxTokenSupply,
            "Invalid Initial Reward Pool"
        );
        require(initialReserve >= 1e18, "Invalid Initial Reserve");
        require(startTimestamp > block.timestamp, "Invalid start timestamp");
        require(durationSeconds > 0, "Invalid duration");

        address newToken = createToken(name, symbol, maxTokenSupply);
        // Mint tokens to reward pool contract
        EconomyToken(newToken).mint(address(MUSING_VAULT), initialRewardPool);
        // Vest tokens
        MUSING_VAULT.vest(
            newToken,
            defaultBeneficiary,
            startTimestamp,
            durationSeconds
        );

        // Wrap AVAX to WAVAX
        IWAVAX(WAVAX_CONTRACT).deposit{value: initialReserve}();
        _reserveBalance[newToken] = initialReserve;
    }

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
    }

    function buy(
        address tokenAddress,
        uint256 reserveAmount,
        uint256 minReward
    ) public validGasPrice {
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
            ),
            "RESERVE_TOKEN_TRANSFER_FAILED"
        );
        _reserveBalance[tokenAddress] += (reserveAmount - taxAmount);

        // Mint reward tokens to the buyer
        EconomyToken(tokenAddress).mint(_msgSender(), rewardTokens);
        // Pay tax to the beneficiary
        RESERVE_TOKEN.transferFrom(_msgSender(), defaultBeneficiary, taxAmount);

        emit Buy(
            tokenAddress,
            _msgSender(),
            rewardTokens,
            reserveAmount,
            defaultBeneficiary,
            taxAmount
        );
    }

    function sell(
        address tokenAddress,
        uint256 tokenAmount,
        uint256 minRefund
    ) public validGasPrice {
        (uint256 refundAmount, uint256 taxAmount) = getRefund(
            tokenAddress,
            tokenAmount
        );
        require(refundAmount >= minRefund, "SLIPPAGE_LIMIT_EXCEEDED");

        // Burn token first
        EconomyToken(tokenAddress).burnFrom(_msgSender(), tokenAmount);

        // Refund reserve tokens to the seller
        _reserveBalance[tokenAddress] -= (refundAmount + taxAmount);
        require(
            RESERVE_TOKEN.transfer(_msgSender(), refundAmount),
            "RESERVE_TOKEN_TRANSFER_FAILED"
        );

        // Pay tax to the beneficiary
        RESERVE_TOKEN.transfer(defaultBeneficiary, taxAmount);

        emit Sell(
            tokenAddress,
            _msgSender(),
            tokenAmount,
            refundAmount,
            defaultBeneficiary,
            taxAmount
        );
    }

    function burn(address tokenAddress, uint256 tokenAmount)
        public
        _checkBondExists(tokenAddress)
    {
        require(tokenAmount > 0, "Invalid Token Amount");
        EconomyToken(tokenAddress).burnFrom(_msgSender(), tokenAmount);

        emit Burn(tokenAddress, _msgSender(), tokenAmount);
    }

    /**
    @dev Allows the owner to update the gas price limit
    @param _gasPrice The new gas price limit
    */
    function setGasPrice(uint256 _gasPrice) public onlyOwner {
        require(_gasPrice > 0);
        gasPrice = _gasPrice;
    }
}
