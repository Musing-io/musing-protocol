const MusingToken = artifacts.require("MusingToken");
const EndorseUser = artifacts.require("EndorseUser");
const UserPost = artifacts.require("UserPost");
const EconomyToken = artifacts.require("EconomyToken");
const EconomyBond = artifacts.require("EconomyBond");
const MusingRewards = artifacts.require("MusingRewards");

module.exports = async function (deployer) {
  await deployer.deploy(MusingToken, "20000000000000000000000000");
  await deployer.deploy(EconomyToken);
  await deployer.deploy(EconomyBond, MusingToken.address, EconomyToken.address);
  // await deployer.deploy(EconomyToken, 'ECONOMY', 'ECON', "2000000000000000000000000");
  // await deployer.deploy(EndorseUser, MusingToken.address);
  // await deployer.deploy(UserPost, MusingToken.address);
  // await deployer.deploy(MusingRewards, MusingToken.address);
};
