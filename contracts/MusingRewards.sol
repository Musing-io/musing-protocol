// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./lib/IEconomyBond.sol";

contract MusingRewards is Context, Ownable {
    using SafeMath for uint256;

    struct Reward {
        uint256 rewards;
        uint256 claimed;
    }

    IEconomyBond internal bond; // Economy Bond Contract

    // token => user => amount
    mapping(address => mapping(address => Reward)) public _rewards;
    // token => amount
    mapping(address => uint256) public distributedRewards;
    mapping(address => uint256) public claimedRewards;

    event Claimed(address indexed user, uint256 reward);
    event RewardsSet();

    constructor(address _bond) {
        bond = IEconomyBond(_bond);
    }

    function distribute(
        address tokenAddress,
        address[] memory users,
        uint256[] memory rewards
    ) external onlyOwner returns (bool) {
        require(IEconomyBond(bond).exists(tokenAddress), "TOKEN_NOT_FOUND");
        require(
            users.length == rewards.length,
            "Length of users and rewards are not the same."
        );

        uint256 i = 0;
        uint256 len = users.length;
        uint256 totalDistributed = 0;
        uint256 rewardPool = IERC20(tokenAddress).balanceOf(address(this)) -
            (distributedRewards[tokenAddress] - claimedRewards[tokenAddress]);

        for (; i < len; i++) {
            require(rewardPool >= rewards[i], "NOT_ENOUGH_REWARD_POOL");
            uint256 reward = rewards[i];
            address user = users[i];
            rewardPool = rewardPool.sub(reward);
            totalDistributed = totalDistributed.add(reward);

            if (reward > 0 && user != address(0x0)) {
                _rewards[tokenAddress][user].rewards = _rewards[tokenAddress][
                    user
                ].rewards.add(reward);
            }
        }

        distributedRewards[tokenAddress] = distributedRewards[tokenAddress].add(
            totalDistributed
        );
        emit RewardsSet();
        return true;
    }

    function getReward(address tokenAddress, address user)
        internal
        view
        virtual
        returns (uint256)
    {
        return
            _rewards[tokenAddress][user].rewards -
            _rewards[tokenAddress][user].claimed;
    }

    function checkRewards(address tokenAddress, address user)
        public
        view
        returns (uint256)
    {
        require(IEconomyBond(bond).exists(tokenAddress), "TOKEN_NOT_FOUND");
        return getReward(tokenAddress, user);
    }

    function distributed(address tokenAddress) public view returns (uint256) {
        return distributedRewards[tokenAddress];
    }

    function claimed(address tokenAddress) public view returns (uint256) {
        return claimedRewards[tokenAddress];
    }

    function claim(address tokenAddress) external returns (bool) {
        require(IEconomyBond(bond).exists(tokenAddress), "TOKEN_NOT_FOUND");

        uint256 reward = getReward(tokenAddress, _msgSender());
        uint256 rewardBalance = IERC20(tokenAddress).balanceOf(address(this));

        require(reward > 0, "No rewards to claim.");
        require(reward <= rewardBalance, "No available funds.");

        _rewards[tokenAddress][_msgSender()].claimed = _rewards[tokenAddress][
            _msgSender()
        ].claimed.add(reward);
        claimedRewards[tokenAddress] = claimedRewards[tokenAddress].add(reward);

        require(
            IERC20(tokenAddress).transfer(_msgSender(), reward),
            "ECONOMY_TOKEN_TRANSFER_FAILED"
        );

        emit Claimed(_msgSender(), reward);
        return true;
    }
}
