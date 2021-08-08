const MastefChef = artifacts.require('MasterChef');

module.exports = async function(deployer) {

  await deployer.deploy(MastefChef,
    "0x30998b6283D428a1e85068F416a1992365d9e0Db",
    "0x5dE4C680d3e306eBbd94b5795905f8234B22D803",
    "0xAe79ddf5FDb9fcdeCfEf3377455f64e6F21eEC69",
    "100000000000000000000",
    "11010000",
    '900000',
    '90000',
    '10000'
  );

};

