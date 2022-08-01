const MusingToken = artifacts.require("MusingToken");
const EconomyToken = artifacts.require("EconomyToken");
const EconomyBond = artifacts.require("EconomyBond");
const BancorFormula = artifacts.require("BancorFormula");
const MusingVault = artifacts.require("MusingVault");
const MusingRewards = artifacts.require("MusingRewards");

module.exports = async function (deployer, network, accounts) {
  await deployer.deploy(MusingToken, "20000000000000000000000000");
  await deployer.deploy(EconomyToken);
  await deployer.deploy(BancorFormula);
  await deployer.deploy(EconomyBond, MusingToken.address, EconomyToken.address, BancorFormula.address, "150000");
  await deployer.deploy(MusingRewards, EconomyBond.address);
  await deployer.deploy(MusingVault, EconomyBond.address, MusingRewards.address);
};
