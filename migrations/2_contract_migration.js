const MusingToken = artifacts.require("MusingToken");
const EndorseUser = artifacts.require("EndorseUser");
const UserPost = artifacts.require("UserPost");
const EconomyToken = artifacts.require("EconomyToken");
const EconomyBond = artifacts.require("EconomyBond");
const MusingRewards = artifacts.require("MusingRewards");
const BancorFormula = artifacts.require("BancorFormula");

module.exports = async function (deployer, network, accounts) {
  await deployer.deploy(MusingToken, "20000000000000000000000000");
  await deployer.deploy(EconomyToken);
  await deployer.deploy(MusingRewards, MusingToken.address);
  await deployer.deploy(BancorFormula);
  await deployer.deploy(
    EconomyBond,
    MusingToken.address,
    EconomyToken.address,
    accounts[0],
    BancorFormula.address,
    "20000"
  );
  // await deployer.deploy(EconomyToken, 'ECONOMY', 'ECON', "2000000000000000000000000");
  // await deployer.deploy(EndorseUser, MusingToken.address);
  // await deployer.deploy(UserPost, MusingToken.address);
};
