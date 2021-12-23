pragma solidity ^0.6.0;

interface IPoolTogether {
    function deposit(uint256 _amountA, uint256 _amountB) external;

    function withdraw(uint256 _amount) external;

    function openPoolTogether() external;

    function drawWinner(uint256 randomNumber) external;
    

}