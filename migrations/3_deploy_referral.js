const LuckyChipReferral = artifacts.require('LuckyChipReferral');

module.exports = async function(deployer) {
  await deployer.deploy(LuckyChipReferral);
};

