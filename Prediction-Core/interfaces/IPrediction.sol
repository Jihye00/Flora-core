pragma solidity ^0.6.0;

interface IPrediction {
    function betbear(uint256 epoch, uint256 amount, uint256 _freezer) external;

    function betbull(uint256 epoch, uint256 amount, uint256 _freezer) external;

    function claim(uint256[] epochs) external;

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

    function getUserRounds(address user,uint256 cursor,uint256 size) external;

    function getUserRoundsLength(address user) external;

    function _getPriceFromOracle(uint256 _price) external;    


}