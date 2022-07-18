//SPDX-License-Identifier: Bancor LICENSE
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./Power.sol";

contract BancorFormula is Power {
    using SafeMath for uint256;

    uint32 private constant MAX_WEIGHT = 1000000; // ppm

    /**
     * @dev given a token supply, reserve balance and weight
     * calculates the current price
     *
     * Formula:
     * return = reserve_balance / (reserve_weight * total_supply)
     *
     * @param _supply          liquid token supply
     * @param _reserveBalance  reserve balance
     * @param _reserveWeight   reserve weight, represented in ppm (1-1000000)
     *
     * @return target
     */
    function currentPrice(
        uint256 _supply,
        uint256 _reserveBalance,
        uint32 _reserveWeight
    ) public view virtual returns (uint256) {
        return
            uint256(MAX_WEIGHT)
                .mul(uint256(MAX_WEIGHT))
                .mul(_reserveBalance)
                .div(_supply.mul(uint256(_reserveWeight)));
    }

    /**
     * @dev given a token supply, reserve balance, weight and a deposit amount (in the reserve token),
     * calculates the target amount for a given conversion (in the main token)
     *
     * Formula:
     * return = _supply * ((1 + _amount / _reserveBalance) ^ (_reserveWeight / 1000000) - 1)
     *
     * @param _supply          liquid token supply
     * @param _reserveBalance  reserve balance
     * @param _reserveWeight   reserve weight, represented in ppm (1-1000000)
     * @param _amount          amount of reserve tokens to get the target amount for
     *
     * @return target
     */
    function calculatePurchaseAmount(
        uint256 _supply,
        uint256 _reserveBalance,
        uint32 _reserveWeight,
        uint256 _amount
    ) public view virtual returns (uint256) {
        // validate input
        require(_supply > 0, "Invalid Supply");
        require(_reserveBalance > 0, "Invalid Reserve Balance");
        require(
            _reserveWeight > 0 && _reserveWeight <= MAX_WEIGHT,
            "Invalid Reserve Weight"
        );

        // special case for 0 deposit amount
        if (_amount == 0) return 0;

        // special case if the weight is 100%
        if (_reserveWeight == MAX_WEIGHT)
            return _supply.mul(_amount) / _reserveBalance;

        uint256 result;
        uint8 precision;
        uint256 baseN = _amount.add(_reserveBalance);
        (result, precision) = power(
            baseN,
            _reserveBalance,
            _reserveWeight,
            MAX_WEIGHT
        );
        uint256 temp = _supply.mul(result) >> precision;
        return temp - _supply;
    }

    /**
     * @dev given a token supply, reserve balance, weight and a sell amount (in the main token),
     * calculates the target amount for a given conversion (in the reserve token)
     *
     * Formula:
     * return = _reserveBalance * (1 - (1 - _amount / _supply) ^ (1000000 / _reserveWeight))
     *
     * @param _supply          liquid token supply
     * @param _reserveBalance  reserve balance
     * @param _reserveWeight   reserve weight, represented in ppm (1-1000000)
     * @param _amount          amount of liquid tokens to get the target amount for
     *
     * @return reserve token amount
     */
    function calculateSaleAmount(
        uint256 _supply,
        uint256 _reserveBalance,
        uint32 _reserveWeight,
        uint256 _amount
    ) public view virtual returns (uint256) {
        // validate input
        require(_supply > 0, "Invalid Supply");
        require(_reserveBalance > 0, "Invalid Reserve Balance");
        require(
            _reserveWeight > 0 && _reserveWeight <= MAX_WEIGHT,
            "Invalid Reserve Weight"
        );
        require(_amount <= _supply, "Invalid Amount");

        // special case for 0 sell amount
        if (_amount == 0) return 0;

        // special case for selling the entire supply
        if (_amount == _supply) return _reserveBalance;

        // special case if the weight is 100%
        if (_reserveWeight == MAX_WEIGHT)
            return _reserveBalance.mul(_amount) / _supply;

        uint256 result;
        uint8 precision;
        uint256 baseD = _supply - _amount;
        (result, precision) = power(_supply, baseD, MAX_WEIGHT, _reserveWeight);
        uint256 temp1 = _reserveBalance.mul(result);
        uint256 temp2 = _reserveBalance << precision;
        return (temp1 - temp2) / result;
    }
}
