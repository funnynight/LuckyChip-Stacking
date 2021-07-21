const MastefChef = artifacts.require('MasterChef');

module.exports = async function(deployer) {

  await deployer.deploy(MastefChef,
    "0x9C10E684EF7CE6069fb6F90A5e9C8A727a13FbaB",
    "0x5dE4C680d3e306eBbd94b5795905f8234B22D803",
    "0xAe79ddf5FDb9fcdeCfEf3377455f64e6F21eEC69",
    "100000000000000000000",
    "10753100",
    '900000',
    '90000',
    '10000'
  );

};

