const MusingToken = artifacts.require("MusingToken");
const UserUpvote = artifacts.require("UserUpvote");
const UserPost = artifacts.require("UserPost");

module.exports = async function (deployer) {
  await deployer.deploy(MusingToken, "2000000000000000000000000");
  await deployer.deploy(UserUpvote, MusingToken.address);
  await deployer.deploy(UserPost, MusingToken.address);
};
