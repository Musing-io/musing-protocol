const MusingToken = artifacts.require("MusingToken");
const EndorseUser = artifacts.require("EndorseUser");
const UserPost = artifacts.require("UserPost");
const EconomyToken = artifacts.require("EconomyToken");

module.exports = async function (deployer) {
  await deployer.deploy(MusingToken, "2000000000000000000000000");
  await deployer.deploy(EconomyToken, 'ECONOMY', 'ECON', "2000000000000000000000000");
  await deployer.deploy(EndorseUser, MusingToken.address);
  await deployer.deploy(UserPost, MusingToken.address);
};
