// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Context.sol";

contract UserPost is Context, Ownable {

  address public mscToken;

  struct Post {
    address creator;
    uint256 timestamp;
    bool hasData;
    uint256 voteCount;
    mapping(address => bool) hasVoted;
  }

  mapping(string => Post) public _posts;

  event PostCreated(address creator, string contentHash);
  event Voted(address voter, string contentHash);
  event Unvoted(address voter, string contentHash);

  constructor (address _mscToken) {
    mscToken = _mscToken;
  }

  modifier validatePost(string memory _postHash) {
    require(_posts[_postHash].hasData == true, "Not a valid post");
    _;
  }

  function publish(string memory _postHash) external returns (string memory) {
    Post storage curPost = _posts[_postHash];
    curPost.creator = _msgSender();
    curPost.timestamp = block.timestamp;
    curPost.hasData = true;

    emit PostCreated(_msgSender(), _postHash);

    return _postHash;
  }

  function checkPost(string memory _postHash) public view returns(bool, address, uint256) {
    return (_posts[_postHash].hasData, _posts[_postHash].creator, _posts[_postHash].timestamp);
  }

  function vote(string memory _postHash) external validatePost(_postHash) {
    require(_posts[_postHash].creator != _msgSender(), "You cannot vote your own post.");
    _posts[_postHash].voteCount++;
    _posts[_postHash].hasVoted[_msgSender()] = true;

    emit Voted(_msgSender(), _postHash);
  }

  function unvote(string memory _postHash) external validatePost(_postHash) {
    require(_posts[_postHash].creator != _msgSender(), "You cannot vote your own post.");
    _posts[_postHash].voteCount--;
    _posts[_postHash].hasVoted[_msgSender()] = false;

    emit Unvoted(_msgSender(), _postHash);
  }

  function hasVoted(string memory _postHash, address voter) public view returns(bool) {
    return _posts[_postHash].hasVoted[voter];
  }

  function countVotes(string memory _postHash) public view returns(uint256) {
    return _posts[_postHash].voteCount;
  }

}