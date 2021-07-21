const Multicall2 = artifacts.require('Multicall2');

module.exports = async function(deployer) {
  await deployer.deploy(Multicall2);
};

