// SPDX-License-Identifier: MIT
  
pragma solidity 0.6.12;

interface IMasterChef {
    function bet(address account, address token, uint256 amount) external returns (bool);
    function getPending(address user) external view returns (uint256);
}
