// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/math/SignedSafeMath.sol";
import "./lib/IEconomyBond.sol";

contract Endorsement is Context, Ownable {
    using SafeMath for uint8;
    using SafeMath for uint256;
    using SignedSafeMath for int256;

    IEconomyBond internal BOND;
    // address public mscToken;
    // address public lockAddress = 0x0F5dCfEB80A5986cA3AfC17eA7e45a1df8Be4844;
    // address public flagAddress = 0x0F5dCfEB80A5986cA3AfC17eA7e45a1df8Be4844;
    address public rewardAddress = 0x292eC696dEc44222799c4e8D90ffbc1032D1b7AC;

    // uint256 TotalLock;
    // uint256 TotalDownvoteLock;
    // uint256 RewardPerToken;

    struct Vote {
        bool upvoted;
        uint256 amount;
        uint256 date;
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

    // struct Downvote {
    //     bool downvoted;
    //     uint256 amount;
    //     uint256 date;
    // }

    // struct Downvoter {
    //     uint8 totalDownvote;
    //     uint256 totalAmount;
    //     mapping(address => Downvote) downvotes;
    // }

    // struct UserDownvote {
    //     uint8 totalDownvote;
    //     uint256 totalAmount;
    // }

    struct EndorsementDetail {
        uint256 TotalLock;
        // uint256 TotalDownvoteLock;
        uint256 RewardPerToken;
        mapping(address => Voter) _voters;
        mapping(address => UserVote) _votes;
        mapping(address => int256) _rewardTally;
    }

    mapping(address => EndorsementDetail) public endorsements; // Endorsements per economy token
    // mapping(address => Downvoter) public _downvoters;
    // mapping(address => UserDownvote) public _downvotes;

    event Upvoted(
        address tokenAddress,
        address indexed by,
        address indexed user,
        uint256 amount
    );
    event Unvoted(
        address tokenAddress,
        address indexed by,
        address indexed user,
        uint256 amount
    );
    // event Flagged(
    //     address tokenAddress,
    //     address indexed by,
    //     address indexed user,
    //     uint256 amount
    // );
    // event Unflagged(
    //     address tokenAddress,
    //     address indexed by,
    //     address indexed user,
    //     uint256 amount
    // );
    event Claimed(address tokenAddress, address indexed user, uint256 reward);
    event Distributed(address tokenAddress, uint256 reward);

    constructor(address _economyBond) {
        BOND = IEconomyBond(_economyBond);
    }

    modifier _checkEconomyExists(address tokenAddress) {
        require(IEconomyBond(BOND).exists(tokenAddress), "TOKEN_NOT_FOUND");
        _;
    }

    // function updateLockAddress(address _newAddress) external onlyOwner {
    //     lockAddress = _newAddress;
    // }

    function updateRewardAddress(address _newAddress) external onlyOwner {
        rewardAddress = _newAddress;
    }

    // function updateFlagAddress(address _newAddress) external onlyOwner {
    //     flagAddress = _newAddress;
    // }

    // Calculate reward per token based on the current total lock tokens
    function distribute(address tokenAddress, uint256 rewards)
        external
        onlyOwner
        returns (bool)
    {
        uint256 totalLock = endorsements[tokenAddress].TotalLock;
        if (totalLock > 0) {
            endorsements[tokenAddress].RewardPerToken = endorsements[
                tokenAddress
            ].RewardPerToken.add(rewards.div(totalLock.div(10**16)).mul(10**2));
        }

        emit Distributed(tokenAddress, rewards);
        return true;
    }

    // Set reward tally for specific user on upvote
    // This will be used to deduct to the total rewards of the user
    function addRewardTally(
        address tokenAddress,
        address user,
        uint256 amount
    ) private {
        uint256 totalReward = endorsements[tokenAddress].RewardPerToken.mul(
            amount.div(10**18)
        );
        endorsements[tokenAddress]._rewardTally[user] = endorsements[
            tokenAddress
        ]._rewardTally[user].add(int256(totalReward));
    }

    // Set reward tally for specific user on unvote
    // This will be used to deduct to the total rewards of the user
    function subRewardTally(
        address tokenAddress,
        address user,
        uint256 amount
    ) private {
        uint256 totalReward = endorsements[tokenAddress].RewardPerToken.mul(
            amount.div(10**18)
        );
        endorsements[tokenAddress]._rewardTally[user] = endorsements[
            tokenAddress
        ]._rewardTally[user].sub(int256(totalReward));
    }

    function computeReward(address tokenAddress, address user)
        private
        view
        returns (uint256)
    {
        int256 totalReward = int256(
            endorsements[tokenAddress]._votes[user].totalAmount.div(10**18).mul(
                endorsements[tokenAddress].RewardPerToken
            )
        );
        int256 rewardBalance = totalReward.sub(
            endorsements[tokenAddress]._rewardTally[user]
        );
        return rewardBalance >= 0 ? uint256(rewardBalance) : 0;
    }

    function upvote(
        address tokenAddress,
        address user,
        uint256 amount
    ) external _checkEconomyExists(tokenAddress) returns (bool) {
        require(user != address(0x0), "Invalid address");
        require(
            amount > 0 &&
                amount <= IERC20(tokenAddress).balanceOf(_msgSender()),
            "Invalid amount or not enough balance"
        );
        require(
            !endorsements[tokenAddress]
                ._voters[_msgSender()]
                .votes[user]
                .upvoted,
            "Already upvoted to this user"
        );

        _safeTransfer(tokenAddress, _msgSender(), address(this), amount);

        endorsements[tokenAddress]._voters[_msgSender()].totalVote += 1;
        endorsements[tokenAddress]
            ._voters[_msgSender()]
            .totalLock = endorsements[tokenAddress]
            ._voters[_msgSender()]
            .totalLock
            .add(amount);
        endorsements[tokenAddress]
            ._voters[_msgSender()]
            .votes[user]
            .upvoted = true;
        endorsements[tokenAddress]
            ._voters[_msgSender()]
            .votes[user]
            .amount = amount;
        endorsements[tokenAddress]
            ._voters[_msgSender()]
            .votes[user]
            .date = block.timestamp;

        endorsements[tokenAddress]._votes[user].totalVote += 1;
        endorsements[tokenAddress]._votes[user].totalAmount = endorsements[
            tokenAddress
        ]._votes[user].totalAmount.add(amount);

        endorsements[tokenAddress].TotalLock = endorsements[tokenAddress]
            .TotalLock
            .add(amount);
        addRewardTally(tokenAddress, user, amount);

        emit Upvoted(tokenAddress, _msgSender(), user, amount);
        return true;
    }

    function unvote(address tokenAddress, address user)
        external
        _checkEconomyExists(tokenAddress)
        returns (bool)
    {
        require(user != address(0x0), "Invalid address");
        require(
            endorsements[tokenAddress]
                ._voters[_msgSender()]
                .votes[user]
                .upvoted,
            "You did not upvote this user"
        );

        uint256 amount = endorsements[tokenAddress]
            ._voters[_msgSender()]
            .votes[user]
            .amount;
        IERC20(tokenAddress).transfer(_msgSender(), amount);

        endorsements[tokenAddress]._voters[_msgSender()].totalVote -= 1;
        endorsements[tokenAddress]
            ._voters[_msgSender()]
            .totalLock = endorsements[tokenAddress]
            ._voters[_msgSender()]
            .totalLock
            .sub(amount);
        endorsements[tokenAddress]
            ._voters[_msgSender()]
            .votes[user]
            .upvoted = false;
        endorsements[tokenAddress]
            ._voters[_msgSender()]
            .votes[user]
            .date = block.timestamp;

        endorsements[tokenAddress]._votes[user].totalVote -= 1;
        endorsements[tokenAddress]._votes[user].totalAmount = endorsements[
            tokenAddress
        ]._votes[user].totalAmount.sub(amount);

        endorsements[tokenAddress].TotalLock = endorsements[tokenAddress]
            .TotalLock
            .sub(amount);
        subRewardTally(tokenAddress, user, amount);

        emit Unvoted(tokenAddress, _msgSender(), user, amount);
        return true;
    }

    // Get the total upvotes distributed by the user
    function getTotalUpvotedBy(address tokenAddress, address upvotedBy)
        public
        view
        returns (uint8, uint256)
    {
        return (
            endorsements[tokenAddress]._voters[upvotedBy].totalVote,
            endorsements[tokenAddress]._voters[upvotedBy].totalLock
        );
    }

    // Check if user is being endorse by another user
    function checkVote(
        address tokenAddress,
        address upvotedBy,
        address user
    ) public view returns (bool, uint256) {
        return (
            endorsements[tokenAddress]._voters[upvotedBy].votes[user].upvoted,
            endorsements[tokenAddress]._voters[upvotedBy].votes[user].amount
        );
    }

    // Get the total upvotes received by the user
    function checkTotalVotes(address tokenAddress, address user)
        public
        view
        returns (uint8, uint256)
    {
        return (
            endorsements[tokenAddress]._votes[user].totalVote,
            endorsements[tokenAddress]._votes[user].totalAmount
        );
    }

    function checkRewards(address tokenAddress, address user)
        public
        view
        returns (uint256)
    {
        uint256 reward = computeReward(tokenAddress, user);
        return reward;
    }

    function claim(address tokenAddress)
        external
        _checkEconomyExists(tokenAddress)
        returns (bool)
    {
        uint256 reward = computeReward(tokenAddress, _msgSender());
        uint256 rewardBalance = IERC20(tokenAddress).balanceOf(rewardAddress);
        require(reward > 0, "No rewards to claim.");
        require(reward <= rewardBalance, "No available funds.");

        _safeTransfer(tokenAddress, rewardAddress, _msgSender(), reward);

        uint256 newRewardTally = endorsements[tokenAddress]
            ._votes[_msgSender()]
            .totalAmount
            .div(10**18)
            .mul(endorsements[tokenAddress].RewardPerToken);
        endorsements[tokenAddress]._rewardTally[_msgSender()] = int256(
            newRewardTally
        );

        emit Claimed(tokenAddress, _msgSender(), reward);
        return true;
    }

    // function flagUser(address user, uint256 amount) public returns (bool) {
    //     require(user != address(0x0), "Invalid address");
    //     require(
    //         amount > 0 && amount <= IERC20(mscToken).balanceOf(_msgSender()),
    //         "Invalid amount or not enough balance"
    //     );
    //     require(
    //         !_downvoters[_msgSender()].downvotes[user].downvoted,
    //         "Already downvoted to this user"
    //     );

    //     _safeTransfer(_msgSender(), flagAddress, amount);

    //     _downvoters[_msgSender()].totalDownvote += 1;
    //     _downvoters[_msgSender()].totalAmount = _downvoters[_msgSender()]
    //         .totalAmount
    //         .add(amount);
    //     _downvoters[_msgSender()].downvotes[user].downvoted = true;
    //     _downvoters[_msgSender()].downvotes[user].amount = amount;
    //     _downvoters[_msgSender()].downvotes[user].date = block.timestamp;

    //     _downvotes[user].totalDownvote += 1;
    //     _downvotes[user].totalAmount = _downvotes[user].totalAmount.add(amount);
    //     TotalDownvoteLock = TotalDownvoteLock.add(amount);

    //     emit Flagged(_msgSender(), user, amount);
    //     return true;
    // }

    // function unflagUser(address user) public returns (bool) {
    //     require(user != address(0x0), "Invalid address");
    //     require(
    //         _downvoters[_msgSender()].downvotes[user].downvoted,
    //         "You did not flag this user"
    //     );

    //     uint256 amount = _downvoters[_msgSender()].downvotes[user].amount;
    //     _safeTransfer(flagAddress, _msgSender(), amount);

    //     _downvoters[_msgSender()].totalDownvote -= 1;
    //     _downvoters[_msgSender()].totalAmount = _downvoters[_msgSender()]
    //         .totalAmount
    //         .sub(amount);
    //     _downvoters[_msgSender()].downvotes[user].downvoted = false;
    //     _downvoters[_msgSender()].downvotes[user].date = block.timestamp;

    //     _downvotes[user].totalDownvote -= 1;
    //     _downvotes[user].totalAmount = _downvotes[user].totalAmount.sub(amount);
    //     TotalDownvoteLock = TotalDownvoteLock.sub(amount);

    //     emit Unflagged(_msgSender(), user, amount);
    //     return true;
    // }

    // // Get the total upvotes distributed by the user
    // function getTotalDownvotedBy(address downvotedBy)
    //     public
    //     view
    //     returns (uint8, uint256)
    // {
    //     return (
    //         _downvoters[downvotedBy].totalDownvote,
    //         _downvoters[downvotedBy].totalAmount
    //     );
    // }

    // // Check if user is being downvoted by another user
    // function checkDownvote(address downvotedBy, address user)
    //     public
    //     view
    //     returns (bool, uint256)
    // {
    //     return (
    //         _downvoters[downvotedBy].downvotes[user].downvoted,
    //         _downvoters[downvotedBy].downvotes[user].amount
    //     );
    // }

    // // Get the total downvotes received by the user
    // function checkTotalDownvotes(address user)
    //     public
    //     view
    //     returns (uint8, uint256)
    // {
    //     return (_downvotes[user].totalDownvote, _downvotes[user].totalAmount);
    // }

    // Transfer token from one address to another
    function _safeTransfer(
        address tokenAddress,
        address from,
        address to,
        uint256 amount
    ) private {
        require(
            IERC20(tokenAddress).transferFrom(from, to, amount),
            "RESERVE_TOKEN_TRANSFER_FAILED"
        );
    }
}
