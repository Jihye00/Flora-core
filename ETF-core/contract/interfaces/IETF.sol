pragma solidity ^0.6.0;

interface ITrust {

    function deposit(uint256 _amount) external;

    function withdraw(uint256 shares) external;

    function userProfit() external view returns (uint256);

    function rebalance() external;

}