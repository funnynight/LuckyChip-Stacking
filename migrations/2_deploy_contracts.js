const MastefChef = artifacts.require('MasterChef');

module.exports = async function(deployer) {

  await deployer.deploy(MastefChef,
    "0x8909BbBe374cF5158BEB18b1A8D5e93BC3e2C30F",
    "0x5dE4C680d3e306eBbd94b5795905f8234B22D803",
    "0xAe79ddf5FDb9fcdeCfEf3377455f64e6F21eEC69",
    "0x5dE4C680d3e306eBbd94b5795905f8234B22D803",
    "0x5dE4C680d3e306eBbd94b5795905f8234B22D803",
    "0x5dE4C680d3e306eBbd94b5795905f8234B22D803",
    "100000000000000000000",
    "11010000",
    '900000',
    '32400',
    '24300',
    '24300',
    '10000'
  );

};

