// SPDX-License-Identifier: MIT
  
pragma solidity 0.6.12;

interface IOracle {
    function update(address tokenA, address tokenB) external returns (bool);
    function updateBlockInfo() external returns (bool);
    function getQuantity(address token, uint256 amount) external view returns (uint256);
    function getLpTokenPower(address _lpToken, uint256 _amount, uint256 _poolType) external view returns (uint256 value);
    function getDiceTokenPower(address _diceToken, uint256 _amount, uint256 _poolType) external view returns (uint256 value);
}
