// SPDX-License-Identifier: MIT
pragma solidity >= 0.5.0;

interface ITreasury {
    function balanceOf(address _director) external view returns (uint256);

    function updateAddReward(address _director) external returns (uint256);

    function displayReward(address user) external returns (uint256);

    function setLockUp(uint256 _withdrawLockupRounds) external;

    function setAdditionalReward(uint256 _additionalPercentage) public;

    function stake(uint256 _amount) external;

    function _withdraw(uint256 _amount) external;

    function canWithdrawOut(address user) external view returns (bool);

    function exit() external;

    function claimReward() external;
}