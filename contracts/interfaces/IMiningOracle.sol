// SPDX-License-Identifier: MIT
  
pragma solidity 0.6.12;

interface IMiningOracle {
    function update(address tokenA, address tokenB) external returns (bool);
    function updateBlockInfo() external returns (bool);
    function getQuantity(address token, uint256 amount) external view returns (uint256);
}
