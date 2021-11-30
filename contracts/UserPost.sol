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
  }

  mapping(string => Post) public _posts;

  event PostCreated(address creator, string contentHash);

  constructor (address _mscToken) {
    mscToken = _mscToken;
  }

  function publish(string memory _postHash) external returns (string memory) {
    Post storage curPost = _posts[_postHash];
    curPost.creator = _msgSender();
    curPost.timestamp = block.timestamp;
    curPost.hasData = true;

    emit PostCreated(_msgSender(), _postHash);

    return _postHash;
  }

  function checkPost(string memory _postHash) public view returns(bool, address, uint256){
    return (_posts[_postHash].hasData, _posts[_postHash].creator, _posts[_postHash].timestamp);
  }

  modifier validPost(string memory _postHash) {
    require(_posts[_postHash].hasData == true, "Not a valid post");
    _;
  }

}