// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/math/SignedSafeMath.sol";

contract EndorseUser is Context, Ownable {
  using SafeMath for uint8;
  using SafeMath for uint256;
  using SignedSafeMath for int256;

  address public mscToken;
  address public lockAddress = 0x0F5dCfEB80A5986cA3AfC17eA7e45a1df8Be4844;
  address public flagAddress = 0x0F5dCfEB80A5986cA3AfC17eA7e45a1df8Be4844;
  address public rewardAddress = 0x292eC696dEc44222799c4e8D90ffbc1032D1b7AC;

  uint256 TotalLock;
  uint256 TotalDownvoteLock;
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

  struct Downvote {
    bool downvoted;
    uint256 amount;
  }

  struct Downvoter {
    uint8 totalDownvote;
    uint256 totalAmount;
    mapping(address => Downvote) downvotes;
  }

  struct UserVote {
    uint8 totalVote;
    uint256 totalAmount;
  }

  struct UserDownvote {
    uint8 totalDownvote;
    uint256 totalAmount;
  }

  mapping(address => Voter) public _voters;
  mapping(address => UserVote) public _votes;
  mapping(address => int256) public _rewardTally;

  mapping(address => Downvoter) public _downvoters;
  mapping(address => UserDownvote) public _downvotes;

  event Upvoted(address indexed by, address indexed user, uint256 amount);
  event Unvoted(address indexed by, address indexed user, uint256 amount);
  event Flagged(address indexed by, address indexed user, uint256 amount);
  event Unflagged(address indexed by, address indexed user, uint256 amount);
  event Claimed(address indexed user, uint256 reward);
  event Distributed(uint256 reward);

  constructor (address _mscToken) {
    mscToken = _mscToken;
  }

  function updateLockAddress(address _newAddress) external onlyOwner {
    lockAddress = _newAddress;
  }

  function updateRewardAddress(address _newAddress) external onlyOwner {
    rewardAddress = _newAddress;
  }

  function updateFlagAddress(address _newAddress) external onlyOwner {
    flagAddress = _newAddress;
  }

  // Calculate reward per token based on the current total lock tokens
  function distribute(uint256 rewards) external onlyOwner returns (bool) {
    if (TotalLock > 0) {
      RewardPerToken = RewardPerToken.add(rewards.div(TotalLock.div(10**16)).mul(10**2));
    }

    emit Distributed(rewards);
    return true;
  }

  // Set reward tally for specific user on upvote
  // This will be used to deduct to the total rewards of the user
  function addRewardTally(address user, uint256 amount) private {
    uint256 totalReward = RewardPerToken.mul(amount.div(10**18));
    _rewardTally[user] = _rewardTally[user].add(int(totalReward));
  }

  // Set reward tally for specific user on unvote
  // This will be used to deduct to the total rewards of the user
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

    _safeTransfer(_msgSender(), lockAddress, amount);

    TotalLock = TotalLock.add(amount);
    addRewardTally(user, amount);

    emit Upvoted(_msgSender(), user, amount);
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

    _safeTransfer(lockAddress, _msgSender(), amount);

    TotalLock = TotalLock.sub(amount);
    subRewardTally(user, amount);

    emit Unvoted(_msgSender(), user, amount);
    return true;
  }

  // Get the total upvotes distributed by the user
  function getTotalUpvotedBy(address upvotedBy) public view returns(uint8, uint256){
    return (_voters[upvotedBy].totalVote, _voters[upvotedBy].totalLock);
  }

  // Check if user is being endorse by another user
  function checkVote(address upvotedBy, address user) public view returns(bool, uint256){
    return (_voters[upvotedBy].votes[user].upvoted, _voters[upvotedBy].votes[user].amount);
  }

  // Get the total upvotes received by the user
  function checkTotalVotes(address user) public view returns(uint8, uint256){
    return (_votes[user].totalVote, _votes[user].totalAmount);
  }

  function checkRewards(address user) public view returns(uint256) {
    uint256 reward = computeReward(user);
    return reward;
  }

  function claim() public returns(bool) {
    uint256 reward = computeReward(_msgSender());
    uint256 rewardBalance = IERC20(mscToken).balanceOf(rewardAddress);
    require(reward > 0, "No rewards to claim.");
    require(reward <= rewardBalance, "No available funds.");

    uint256 newRewardTally = _votes[_msgSender()].totalAmount.div(10**18).mul(RewardPerToken);
    _rewardTally[_msgSender()] = int(newRewardTally);

    _safeTransfer(rewardAddress, _msgSender(), reward);

    emit Claimed(_msgSender(), reward);
    return true;
  }

  function flagUser(address user, uint256 amount) public returns(bool) {
    require(user != address(0x0), "Invalid address");
    require(amount > 0 && amount <= IERC20(mscToken).balanceOf(_msgSender()), "Invalid amount or not enough balance");
    require(!_downvoters[_msgSender()].downvotes[user].downvoted, "Already downvoted to this user");

    _downvoters[_msgSender()].totalDownvote += 1;
    _downvoters[_msgSender()].totalAmount = _downvoters[_msgSender()].totalAmount.add(amount);
    _downvoters[_msgSender()].downvotes[user].downvoted = true;
    _downvoters[_msgSender()].downvotes[user].amount = amount;

    _downvotes[user].totalDownvote += 1;
    _downvotes[user].totalAmount = _downvotes[user].totalAmount.add(amount);

    _safeTransfer(_msgSender(), flagAddress, amount);
    TotalDownvoteLock = TotalDownvoteLock.add(amount);

    emit Flagged(_msgSender(), user, amount);
    return true;
  }

  function unflagUser(address user) public returns(bool) {
    require(user != address(0x0), "Invalid address");
    require(_downvoters[_msgSender()].downvotes[user].downvoted, "You did not flag this user");

    uint256 amount = _downvoters[_msgSender()].downvotes[user].amount;
    _downvoters[_msgSender()].totalDownvote -= 1;
    _downvoters[_msgSender()].totalAmount = _downvoters[_msgSender()].totalAmount.sub(amount);
    _downvoters[_msgSender()].downvotes[user].downvoted = false;

    _downvotes[user].totalDownvote -= 1;
    _downvotes[user].totalAmount = _downvotes[user].totalAmount.sub(amount);

    _safeTransfer(flagAddress, _msgSender(), amount);
    TotalDownvoteLock = TotalDownvoteLock.sub(amount);

    emit Unflagged(_msgSender(), user, amount);
    return true;
  }

  // Get the total upvotes distributed by the user
  function getTotalDownvotedBy(address downvotedBy) public view returns(uint8, uint256){
    return (_downvoters[downvotedBy].totalDownvote, _downvoters[downvotedBy].totalAmount);
  }

  // Check if user is being downvoted by another user
  function checkDownvote(address downvotedBy, address user) public view returns(bool, uint256){
    return (_downvoters[downvotedBy].downvotes[user].downvoted, _downvoters[downvotedBy].downvotes[user].amount);
  }

  // Get the total downvotes received by the user
  function checkTotalDownvotes(address user) public view returns(uint8, uint256){
    return (_downvotes[user].totalDownvote, _downvotes[user].totalAmount);
  }

  // Transfer token from one address to another
  function _safeTransfer(address from, address to, uint256 amount) private {
    uint256 allowance = IERC20(mscToken).allowance(address(this), from);
    IERC20(mscToken).approve(from, allowance.add(amount));
    IERC20(mscToken).transferFrom(from, to, amount);
  }

}