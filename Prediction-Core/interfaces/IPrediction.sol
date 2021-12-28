// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

interface IPrediction {
    function betBear(uint256 epoch, uint256 amount, uint256 _freezer) external;

    function betBull(uint256 epoch, uint256 amount, uint256 _freezer) external;

    function executeRound() external;

    function genesisLockRound() external;

    function genesisStartRound() external;

    function pause() external;

    function claimBB() external;

    function unpause() external;

    function setBufferAndIntervalSeconds(uint256 buffer, uint256 interval) external;

    function setMinBetAmount(uint256 amount) external;

    function setOperator(address _newOperator) external;

    function setOracleUpdateAllowance(uint256 _oracleUpdateAllowance) external;

    function setBBFee(uint256 _BBFee) external;

    function recoverToken(address _token, uint256 _amount) external;

    function setAdmin(address _adminAddress) external;

    function _getPriceFromOracle(uint256 _price) external;    

}