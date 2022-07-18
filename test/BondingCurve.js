const MusingToken = artifacts.require("MusingToken");
const EconomyBond = artifacts.require("EconomyBond");
const EconomyToken = artifacts.require("EconomyToken");

// using MSC as WAVAX
// NOTE: this tests is only for bonding curve excluding TAX,
//       need to update code to remove tax calculations
// TODO: make tests including tax
contract("Bonding Curve using BancorFormula", (accounts) => {
  let newToken = null;
  it("should have 20 Million MSC in first account", async () => {
    const token = await MusingToken.deployed();
    const balance = await token.balanceOf(accounts[0]);

    assert.equal(
      web3.utils.fromWei(balance.toString(), "ether"),
      20000000,
      "20000000 wasn't in the first account"
    );
  });
  it("should initialize bond and bancor formula successfully", async () => {
    const bond = await EconomyBond.deployed();
    let tx = await bond.init();

    assert.isTrue(
      tx.receipt.status,
      "Wasn't able to initialize bancor formula"
    );
  });
  it("created new token with 10000 reward pool and 1 msc reserve pool", async () => {
    const token = await MusingToken.deployed();
    const bond = await EconomyBond.deployed();

    // create new token
    await token.approve(EconomyBond.address, "1000000000000000000");
    let tx = await bond.createEconomy(
      "Smurf",
      "SMU",
      "1000000000000000000000000", // 1m max supply
      "1000000000000000000", // 1 MSC
      "10000000000000000000000" // 10k tokens
    );
    // get new token address
    const log = tx.logs.find((l) => l.event == "TokenCreated");
    newToken = log?.args?.tokenAddress;
    assert.isNotEmpty(newToken, "Error creating token");

    // check if newly created token has a correct balance
    const smu = await EconomyToken.at(newToken);
    const balance = await smu.balanceOf(accounts[0]);
    assert.equal(
      web3.utils.fromWei(balance.toString(), "ether"),
      10000,
      "Incorrect reward pool balance"
    );

    // check reserve pool balance
    const reserve = await bond.reserveBalance(newToken);
    assert.equal(
      web3.utils.fromWei(reserve.toString(), "ether"),
      1,
      "Incorrect reserve balance"
    );

    // check price
    const price = await bond.pricePPM(newToken);
    assert.equal(Number(price.toString()) / 1000000, 0.005, "Incorrect price");
  });
  it("bought tokens for 1 MSC and should have 10139.59 total balance", async () => {
    const token = await MusingToken.deployed();
    const bond = await EconomyBond.deployed();

    // create new token
    await token.approve(EconomyBond.address, "1000000000000000000");
    let tx = await bond.buy(
      newToken,
      "1000000000000000000", // 1 MSC
      "0", // 0 min reward
      "0x0000000000000000000000000000000000000000"
    );

    // get new total supply
    const smu = await EconomyToken.at(newToken);
    const balance = await smu.totalSupply();
    assert.equal(
      +Number(web3.utils.fromWei(balance.toString(), "ether")).toFixed(2),
      10139.59,
      "Incorrect total supply"
    );

    // check reserve pool balance
    const reserve = await bond.reserveBalance(newToken);
    assert.equal(
      web3.utils.fromWei(reserve.toString(), "ether"),
      2,
      "Incorrect reserve balance"
    );

    // check price
    const price = await bond.pricePPM(newToken);
    assert.equal(
      Number(price.toString()) / 1000000,
      0.009862,
      "Incorrect price"
    );
  });
});
