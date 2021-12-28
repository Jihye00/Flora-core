// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

interface ITrust {

    function depositKlay(uint256 amount) external payable;

    function deposit(uint256 amountA, uint256 amountB) external;

    function withdraw(uint256 shares) external;

    function estimateSupply(address token, uint256 amount) external view returns (uint256);

    function totalValue() external view returns (uint256, uint256);

}
