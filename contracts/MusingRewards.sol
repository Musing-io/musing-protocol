// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract MusingRewards is Context, Ownable {
  using SafeMath for uint256;

  address public mscToken;
  address public rewardAddress = 0x292eC696dEc44222799c4e8D90ffbc1032D1b7AC;

  mapping(address => uint256) public _rewards;

  event Claimed(address indexed user, uint256 reward);
  event RewardsSet();

  constructor (address _mscToken) {
    mscToken = _mscToken;
  }

  function updateRewardAddress(address _newAddress) external onlyOwner {
    rewardAddress = _newAddress;
  }

  function distribute(address[] memory users, uint256[] memory rewards) external onlyOwner returns (bool) {
    require(users.length == rewards.length, "Length of users and rewards are not the same.");

    uint i=0;
    uint len = users.length;

    for (; i < len; i++) {
      uint256 reward = rewards[i];
      address user = users[i];

      if (reward > 0 && user != address(0x0)) {
        _rewards[user] = _rewards[user].add(reward);
      }
    }

    emit RewardsSet();
    return true;
  }

  function checkRewards(address user) public view returns(uint256) {
    uint256 reward = _rewards[user];
    return reward;
  }

  function claim() public returns(bool) {
    uint256 reward = _rewards[_msgSender()];
    uint256 rewardBalance = IERC20(mscToken).balanceOf(rewardAddress);
    require(reward > 0, "No rewards to claim.");
    require(reward <= rewardBalance, "No available funds.");

    _rewards[_msgSender()] = 0;
    _safeTransfer(rewardAddress, _msgSender(), reward);

    emit Claimed(_msgSender(), reward);
    return true;
  }

  // Transfer token from one address to another
  function _safeTransfer(address from, address to, uint256 amount) private {
    uint256 allowance = IERC20(mscToken).allowance(address(this), from);
    IERC20(mscToken).approve(from, allowance.add(amount));
    IERC20(mscToken).transferFrom(from, to, amount);
  }

}