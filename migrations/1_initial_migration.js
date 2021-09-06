const LCToken = artifacts.require("LCToken")
const MastefChef = artifacts.require('MasterChef');

module.exports = async function(deployer) {
  await deployer.deploy(LCToken);
  const instanceLCToken = await LCToken.deployed();

  await deployer.deploy(MastefChef,
    instanceLCToken.address,
    "0x5dE4C680d3e306eBbd94b5795905f8234B22D803",
    "0xAe79ddf5FDb9fcdeCfEf3377455f64e6F21eEC69",
    "0x5dE4C680d3e306eBbd94b5795905f8234B22D803",
    "0x5dE4C680d3e306eBbd94b5795905f8234B22D803",
    "0x5dE4C680d3e306eBbd94b5795905f8234B22D803",
    "100000000000000000000",
    "12045000",
    '900000',
    '32400',
    '24300',
    '24300',
    '10000'
  );

  const instanceMasterChef = await MastefChef.deployed();
  await instanceLCToken.transferOwnership(instanceMasterChef.address);
};
