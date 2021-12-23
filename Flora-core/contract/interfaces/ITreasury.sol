// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;
interface ITreasury {
    function _stake(uint256 _amount) external;

    function _withdraw(uint256 _amount) external;

    function claimReward_To_Wallet() external;

    function claimReward_To_Staking() external;

}