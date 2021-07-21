const LCToken = artifacts.require("LCToken")

module.exports = async function(deployer) {
  await deployer.deploy(LCToken);
};
