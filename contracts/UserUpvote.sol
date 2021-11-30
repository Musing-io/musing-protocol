// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract UserUpvote is Context, Ownable {
  using SafeMath for uint8;
  using SafeMath for uint256;

  address public mscToken;
  address public lockAddress = 0x5EF17A1a1fB4Ce357b24011E6378c432C7F6aA6c;

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

  event Upvote(address indexed by, address indexed user, uint256 amount);
  event Unvote(address indexed by, address indexed user, uint256 amount);

  constructor (address _mscToken) {
    mscToken = _mscToken;
  }

  function upvote(address user, uint256 amount) public returns(bool){
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

    emit Upvote(_msgSender(), user, amount);
    return true;
  }

  function unvote(address user) public returns(bool){
    require(user != address(0x0), "Invalid address");
    require(_voters[_msgSender()].votes[user].upvoted, "You did not upvote this user");

    uint256 amount = _voters[_msgSender()].votes[user].amount;
    _voters[_msgSender()].totalVote -= 1;
    _voters[_msgSender()].totalLock = _voters[_msgSender()].totalLock.sub(amount);
    _voters[_msgSender()].votes[user].upvoted = false;

    _votes[user].totalVote -= 1;
    _votes[user].totalAmount = _votes[user].totalAmount.sub(amount);

    uint256 allowance = IERC20(mscToken).allowance(address(this), _msgSender());
    IERC20(mscToken).approve(lockAddress, allowance.add(amount));
    IERC20(mscToken).transferFrom(lockAddress, _msgSender(), amount);

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

  function updateLockAddress(address _newAddress) public returns(bool){
    lockAddress = _newAddress;
    return true;
  }

}