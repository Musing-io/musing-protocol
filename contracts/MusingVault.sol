// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (finance/VestingWallet.sol)
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./lib/IEconomyBond.sol";

/**
 * @title MusingVault
 * @dev Updated contract from OpenZeppelin VestingWallet to handle multiple tokens.
 * This contract handles the vesting of Eth and ERC20 tokens for a given beneficiary. Custody of multiple tokens
 * can be given to this contract, which will release the token to the beneficiary following a given vesting schedule.
 * The vesting schedule is customizable through the {vestedAmount} function.
 *
 * Any token transferred to this contract will follow the vesting schedule as if they were locked from the beginning.
 * Consequently, if the vesting has already started, any amount of tokens sent to this contract will (at least partly)
 * be immediately releasable.
 */
contract MusingVault is Context, Ownable {
    event EtherReleased(uint256 amount);
    event ERC20Released(address indexed token, uint256 amount);

    struct VestingDetail {
        bool _set;
        address _beneficiary;
        uint64 _start;
        uint64 _duration;
    }

    // address private immutable _beneficiary;
    // uint64 private immutable _start;
    // uint64 private immutable _duration;
    mapping(address => uint256) private _erc20Released;
    mapping(address => VestingDetail) private vestings;
    address internal DEFAULT_BENEFICIARY;
    IEconomyBond internal bond; // Economy Bond Contract

    /**
     * @dev Set the beneficiary, start timestamp and vesting duration of the vesting wallet.
     */
    constructor(address _bond, address beneficiaryAddress) {
        require(
            beneficiaryAddress != address(0),
            "VestingWallet: beneficiary is zero address"
        );
        bond = IEconomyBond(_bond);
        DEFAULT_BENEFICIARY = beneficiaryAddress;
    }

    /**
     * @dev Create new token vesting
     */
    function vest(
        address tokenAddress,
        address beneficiaryAddress,
        uint64 startTimestamp,
        uint64 durationSeconds
    ) external returns (bool) {
        require(IEconomyBond(bond).exists(tokenAddress), "TOKEN_NOT_FOUND");
        require(vestings[tokenAddress]._set != true, "TOKEN_ALREADY_SET");
        require(startTimestamp > block.timestamp, "Invalid start timestamp");
        require(durationSeconds > 0, "Invalid duration");

        vestings[tokenAddress]._set = true;
        vestings[tokenAddress]._start = startTimestamp;
        vestings[tokenAddress]._duration = durationSeconds;

        address actualBeneficiary = beneficiaryAddress;
        if (beneficiaryAddress == address(0x0)) {
            actualBeneficiary = DEFAULT_BENEFICIARY;
        }
        vestings[tokenAddress]._beneficiary = actualBeneficiary;

        return true;
    }

    function setBeneficiary(address _tokenAddress, address _beneficiary)
        external
        onlyOwner
    {
        require(IEconomyBond(bond).exists(_tokenAddress), "TOKEN_NOT_FOUND");
        require(
            _beneficiary != address(0),
            "DEFAULT_BENEFICIARY_CANNOT_BE_NULL"
        );
        vestings[_tokenAddress]._beneficiary = _beneficiary;
    }

    /**
     * @dev Getter for the beneficiary address.
     */
    function beneficiary(address tokenAddress)
        public
        view
        virtual
        returns (address)
    {
        return vestings[tokenAddress]._beneficiary;
    }

    /**
     * @dev Getter for the start timestamp.
     */
    function start(address tokenAddress) public view virtual returns (uint256) {
        return vestings[tokenAddress]._start;
    }

    /**
     * @dev Getter for the vesting duration.
     */
    function duration(address tokenAddress)
        public
        view
        virtual
        returns (uint256)
    {
        return vestings[tokenAddress]._duration;
    }

    /**
     * @dev Amount of token already released
     */
    function released(address tokenAddress)
        public
        view
        virtual
        returns (uint256)
    {
        return _erc20Released[tokenAddress];
    }

    /**
     * @dev Release the tokens that have already vested.
     *
     * Emits a {TokensReleased} event.
     */
    function release(address tokenAddress) public virtual {
        uint256 releasable = vestedAmount(
            tokenAddress,
            uint64(block.timestamp)
        ) - released(tokenAddress);
        _erc20Released[tokenAddress] += releasable;
        emit ERC20Released(tokenAddress, releasable);
        SafeERC20.safeTransfer(
            IERC20(tokenAddress),
            beneficiary(tokenAddress),
            releasable
        );
    }

    /**
     * @dev Calculates the amount of tokens that has already vested. Default implementation is a linear vesting curve.
     */
    function vestedAmount(address tokenAddress, uint64 timestamp)
        public
        view
        virtual
        returns (uint256)
    {
        require(vestings[tokenAddress]._set, "TOKEN_NOT_FOUND");
        return
            _vestingSchedule(
                tokenAddress,
                IERC20(tokenAddress).balanceOf(address(this)) +
                    released(tokenAddress),
                timestamp
            );
    }

    /**
     * @dev Virtual implementation of the vesting formula. This returns the amout vested, as a function of time, for
     * an asset given its total historical allocation.
     */
    function _vestingSchedule(
        address tokenAddress,
        uint256 totalAllocation,
        uint64 timestamp
    ) internal view virtual returns (uint256) {
        if (timestamp < start(tokenAddress)) {
            return 0;
        } else if (timestamp > start(tokenAddress) + duration(tokenAddress)) {
            return totalAllocation;
        } else {
            return
                (totalAllocation * (timestamp - start(tokenAddress))) /
                duration(tokenAddress);
        }
    }
}
