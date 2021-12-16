// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/math/SignedSafeMath.sol";

contract UserUpvote is Context, Ownable {
  using SafeMath for uint8;
  using SafeMath for uint256;
  using SignedSafeMath for int256;

  address public mscToken;
  address public lockAddress = 0x0F5dCfEB80A5986cA3AfC17eA7e45a1df8Be4844;
  address public rewardAddress = 0x292eC696dEc44222799c4e8D90ffbc1032D1b7AC;

  uint256 TotalLock;
  uint256 RewardPerToken;

  struct Vote {
    bool upvoted;
    uint256 amount;
  }

  struct Voter {
    uint8 totalVote;
    uint256 totalLock;
    mapping(address => Vote) votes;
  }

  struct UserVote {
    uint8 totalVote;
    uint256 totalAmount;
  }

  mapping(address => Voter) public _voters;
  mapping(address => UserVote) public _votes;
  mapping(address => int256) public _rewardTally;

  event Upvote(address indexed by, address indexed user, uint256 amount);
  event Unvote(address indexed by, address indexed user, uint256 amount);
  event Claim(address indexed user, uint256 reward);
  event Distribute(uint256 reward);

  constructor (address _mscToken) {
    mscToken = _mscToken;
  }

  function addRewardTally(address user, uint256 amount) private {
    uint256 totalReward = RewardPerToken.mul(amount.div(10**18));
    _rewardTally[user] = _rewardTally[user].add(int(totalReward));
  }

  function subRewardTally(address user, uint256 amount) private {
    uint256 totalReward = RewardPerToken.mul(amount.div(10**18));
    _rewardTally[user] = _rewardTally[user].sub(int(totalReward));
  }

  function computeReward(address user) private view returns(uint256) {
    int256 totalReward = int(_votes[user].totalAmount.div(10**18).mul(RewardPerToken));
    int256 rewardBalance = totalReward.sub(_rewardTally[user]);
    return rewardBalance >= 0 ? uint(rewardBalance) : 0;
  }

  function upvote(address user, uint256 amount) public returns(bool) {
    require(user != address(0x0), "Invalid address");
    require(amount > 0 && amount <= IERC20(mscToken).balanceOf(_msgSender()), "Invalid amount or not enough balance");
    require(!_voters[_msgSender()].votes[user].upvoted, "Already upvoted to this user");

    _voters[_msgSender()].totalVote += 1;
    _voters[_msgSender()].totalLock = _voters[_msgSender()].totalLock.add(amount);
    _voters[_msgSender()].votes[user].upvoted = true;
    _voters[_msgSender()].votes[user].amount = amount;

    _votes[user].totalVote += 1;
    _votes[user].totalAmount = _votes[user].totalAmount.add(amount);

    uint256 allowance = IERC20(mscToken).allowance(address(this), _msgSender());
    IERC20(mscToken).approve(_msgSender(), allowance.add(amount));
    IERC20(mscToken).transferFrom(_msgSender(), lockAddress, amount);

    TotalLock = TotalLock.add(amount);
    addRewardTally(user, amount);

    emit Upvote(_msgSender(), user, amount);
    return true;
  }

  function unvote(address user) public returns(bool) {
    require(user != address(0x0), "Invalid address");
    require(_voters[_msgSender()].votes[user].upvoted, "You did not upvote this user");

    uint256 amount = _voters[_msgSender()].votes[user].amount;
    _voters[_msgSender()].totalVote -= 1;
    _voters[_msgSender()].totalLock = _voters[_msgSender()].totalLock.sub(amount);
    _voters[_msgSender()].votes[user].upvoted = false;

    _votes[user].totalVote -= 1;
    _votes[user].totalAmount = _votes[user].totalAmount.sub(amount);

    uint256 allowance = IERC20(mscToken).allowance(address(this), lockAddress);
    IERC20(mscToken).approve(lockAddress, allowance.add(amount));
    IERC20(mscToken).transferFrom(lockAddress, _msgSender(), amount);

    TotalLock = TotalLock.sub(amount);
    subRewardTally(user, amount);

    emit Unvote(_msgSender(), user, amount);
    return true;
  }

  function getTotalUpvotedBy(address upvotedBy) public view returns(uint8, uint256){
    return (_voters[upvotedBy].totalVote, _voters[upvotedBy].totalLock);
  }

  function checkVote(address upvotedBy, address user) public view returns(bool, uint256){
    return (_voters[upvotedBy].votes[user].upvoted, _voters[upvotedBy].votes[user].amount);
  }

  function checkTotalVotes(address user) public view returns(uint8, uint256){
    return (_votes[user].totalVote, _votes[user].totalAmount);
  }

  function updateLockAddress(address _newAddress) external onlyOwner {
    lockAddress = _newAddress;
  }

  function updateRewardAddress(address _newAddress) external onlyOwner {
    rewardAddress = _newAddress;
  }

  function distribute(uint256 rewards) external onlyOwner {
    if (TotalLock > 0) {
      RewardPerToken = RewardPerToken.add(rewards.div(TotalLock.div(10**16)).mul(10**2));
    }

    emit Distribute(rewards);
  }

  function checkRewards(address user) public view returns(uint256) {
    uint256 reward = computeReward(user);
    return reward;
  }

  function claim() public returns(bool) {
    uint256 reward = computeReward(_msgSender());
    // uint256 rewardBalance = IERC20(mscToken).balanceOf(rewardAddress);
    require(reward > 0, "No rewards to claim.");
    // require(reward <= rewardBalance, "No available funds.");

    uint256 newRewardTally = _votes[_msgSender()].totalAmount.div(10**18).mul(RewardPerToken);
    _rewardTally[_msgSender()] = int(newRewardTally);

    // uint256 allowance = IERC20(mscToken).allowance(address(this), _msgSender());
    // IERC20(mscToken).approve(rewardAddress, allowance + reward);
    // IERC20(mscToken).transferFrom(rewardAddress, _msgSender(), reward);

    emit Claim(_msgSender(), reward);
    return true;
  }

}