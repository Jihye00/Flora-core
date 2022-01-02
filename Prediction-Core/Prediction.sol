// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "./utils/Pausable.sol";
import "./utils/Address.sol";
import "./utils/ERC20.sol";
import "./utils/Ownable.sol";
import "./utils/ReentrancyGuard.sol";
import "./utils/SafeERC20.sol";
import "./utils/SafeMath.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IPrediction.sol";

/**
 * @title Flora.fianance Prediction Code
 */
contract Prediction is IPrediction, Ownable, Pausable, ReentrancyGuard{
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    bool public genesisLockOnce = false;
    bool public genesisStartOnce = false;
    bool public refundCheck = false;

    address public adminAddress; // address of the admin
    address public operatorAddress; // address of the operator

    uint256 public bufferSeconds; // number of seconds for valid execution of a prediction round
    uint256 public intervalSeconds; // interval in seconds between two prediction rounds

    uint256 public minBetAmount; // minimum betting amount (denominated in wei)
    uint256 public BBFee; // BB rate (e.g. 200 = 2%, 150 = 1.50%)
    uint256 public BBAmount; // BB amount that was not claimed

    uint256 public PendingAmountSpecial; //Pending 1% of every rewards for the special round per day

    uint256 public currentEpoch; // current epoch for prediction round

    uint256 public oracleUpdateAllowance; // round.lockTimestamp - oracleupdateAllowance < update price. In sec.

    uint256 public constant MAX_BB_FEE = 900; // 10%. Usually 5%, which means MAX_BB_FEE == 500

    uint256 internal price_;
    bool internal updated;

    IERC20 public acaToken;

    enum Position {
        Bull, 
        Bear
    } //Bull for Up, Bear for Down

    struct Round {
        uint256 epoch;
        uint256 startTimestamp;
        uint256 lockTimestamp;
        uint256 closeTimestamp;
        uint256 lockPrice;
        uint256 closePrice;
        uint256 lockOracleId;
        uint256 closeOracleId;
        uint256 totalAmount;
        uint256 bullAmount;
        uint256 bearAmount;
        uint256 rewardBaseCalAmount;
        uint256 rewardAmount;
        bool oracleCalled;
    }

    struct BetInfo {
        Position position;
        uint256 amount;
        uint256 freezer;
        bool claimed; // default false
    }

    struct LeaderBoard {
        bool prevWin;
        uint256 playtime;
        uint256 seriesWin;
        uint256 wintime;
    }

    mapping(uint256 => mapping(address => BetInfo)) public ledger;
    mapping(uint256 => Round) public rounds;
    mapping(address => uint256[]) public userRounds;
    mapping(address => LeaderBoard) public userLeader;

    event BetBear(address indexed sender, uint256 indexed epoch, uint256 amount);
    event BetBull(address indexed sender, uint256 indexed epoch, uint256 amount);
    event Claim(address indexed sender, uint256 indexed epoch, uint256 amount);
    event EndRound(uint256 indexed epoch, uint256 indexed roundId, uint256 price);
    event LockRound(uint256 indexed epoch, uint256 indexed roundId, uint256 price);

    event NewAdminAddress(address admin);
    event NewBufferAndIntervalSeconds(uint256 bufferSeconds, uint256 intervalSeconds);
    event NewMinBetAmount(uint256 indexed epoch, uint256 minBetAmount);
    event NewBBFee(uint256 indexed epoch, uint256 BBFee);
    event NewOperatorAddress(address operator);
    event NewOracle(address oracle);
    event NewOracleUpdateAllowance(uint256 oracleUpdateAllowance);
    event updatePrice(uint256 price);


    event Pause(uint256 indexed epoch);
    event RewardsCalculated(
        uint256 indexed epoch,
        uint256 rewardBaseCalAmount,
        uint256 rewardAmount,
        uint256 BBAmount
    );

    event StartRound(uint256 indexed epoch);
    event TokenRecovery(address indexed token, uint256 amount);
    event BBClaim(uint256 amount);
    event Unpause(uint256 indexed epoch);

    modifier onlyAdmin() {
        require(msg.sender == adminAddress, "Not admin");
        _;
    }

    modifier onlyAdminOrOperator() {
        require(msg.sender == adminAddress || msg.sender == operatorAddress, "Not operator/admin");
        _;
    }

    modifier onlyOperator() {
        require(msg.sender == operatorAddress, "Not operator");
        _;
    }

    modifier notContract() {
        require(!_isContract(msg.sender), "Contract not allowed");
        require(msg.sender == msg.sender, "Proxy contract not allowed");
        _;
    }

    /**
     * @notice Constructor
     * @param _adminAddress: admin address
     * @param _operatorAddress: operator address
     * @param _intervalSeconds: number of time within an interval
     * @param _minBetAmount: minimum bet amounts (in wei)
     * @param _BBFee: BB fee (1000 = 10%)
     */
    constructor (
        address _acaToken,
        address _adminAddress,
        address _operatorAddress,
        uint256 _intervalSeconds,
        uint256 _minBetAmount,
        uint256 _BBFee
    ) public{
        require(_BBFee <= MAX_BB_FEE, "BB fee too high");
        acaToken = IERC20(_acaToken);
        adminAddress = _adminAddress;
        operatorAddress = _operatorAddress;
        intervalSeconds = _intervalSeconds;
        bufferSeconds = 10 minutes;
        minBetAmount = _minBetAmount;
        oracleUpdateAllowance = 10 minutes;
        BBFee = _BBFee;
    }

    /**
     * @notice Bet bear position
     * @param epoch: epoch
     */
    function betBear(uint256 epoch, uint256 amount, uint256 _freezer) external virtual override payable whenNotPaused nonReentrant notContract {
        require(epoch == currentEpoch, "Bet is too early/late");
        require(_bettable(epoch), "Round not bettable");
        require(amount >= minBetAmount, "Bet amount must be greater than minBetAmount");
        require(ledger[epoch][msg.sender].amount == 0, "Can only bet once per round");

        if (_freezer != 0) {
            ledger[epoch][msg.sender].freezer = _freezer;
        }
        // Update round data
        acaToken.safeTransferFrom(address(msg.sender), address(this), amount);
        Round storage round = rounds[epoch];
        round.totalAmount = round.totalAmount + amount;
        round.bearAmount = round.bearAmount + amount;
        userLeader[msg.sender].playtime += 1;
        // Update user data
        BetInfo storage betInfo = ledger[epoch][msg.sender];
        betInfo.position = Position.Bear;
        betInfo.amount = amount;
        userRounds[msg.sender].push(epoch);

        emit BetBear(msg.sender, epoch, amount);
    }

    /**
     * @notice Bet bull position
     * @param epoch: epoch
     */
    function betBull(uint256 epoch, uint256 amount, uint256 _freezer) external virtual override payable whenNotPaused nonReentrant notContract {
        require(epoch == currentEpoch, "Bet is too early/late");
        require(_bettable(epoch), "Round not bettable");
        require(amount >= minBetAmount, "Bet amount must be greater than minBetAmount");
        require(ledger[epoch][msg.sender].amount == 0, "Can only bet once per round");

        // Update round data
        if (_freezer != 0) {
            ledger[epoch][msg.sender].freezer = _freezer;
        }
        acaToken.safeTransferFrom(address(msg.sender), address(this), amount);
        Round storage round = rounds[epoch];
        round.totalAmount = round.totalAmount + amount;
        round.bullAmount = round.bullAmount + amount;
        userLeader[msg.sender].playtime += 1;
        // Update user data
        BetInfo storage betInfo = ledger[epoch][msg.sender];
        betInfo.position = Position.Bull;
        betInfo.amount = amount;
        userRounds[msg.sender].push(epoch);

        emit BetBull(msg.sender, epoch, amount);
    }

    /**
     * @notice Claim reward for an array of epochs
     * @param epochs: array of epochs
     */
    function claim(uint256[] calldata epochs) external nonReentrant notContract {
        uint256 reward; // Initializes reward
        uint256 _seriesWin = 0;
        uint256 order = 0;
        for (uint256 i = 0; i < epochs.length; i++) {
            require(rounds[epochs[i]].startTimestamp != 0, "Round has not started");
            require(block.timestamp > rounds[epochs[i]].closeTimestamp, "Round has not ended");

            uint256 addedReward = 0;
            
            // Round valid, claim rewards
            if (rounds[epochs[i]].oracleCalled) {
                if (claimable(epochs[i], msg.sender)){ //Win game
                    Round memory round = rounds[epochs[i]];
                    addedReward = (ledger[epochs[i]][msg.sender].amount.mul(round.rewardAmount)).div(round.rewardBaseCalAmount);
                    userLeader[msg.sender].wintime = userLeader[msg.sender].wintime + 1;

                    if (i == 0 && userLeader[msg.sender].prevWin == true){
                        _seriesWin = (userLeader[msg.sender].seriesWin + 1);
                    }
                    else {
                        _seriesWin += 1;
                    }
                }
                
                else { //Lose game
                    BetInfo memory betInfo = ledger[epochs[i]][msg.sender];
                    if (betInfo.amount != 0) {
                        if (ledger[epochs[i]][msg.sender].freezer == 0){ //No freezer
                            if (userLeader[msg.sender].seriesWin < _seriesWin) {
                                userLeader[msg.sender].seriesWin = _seriesWin;
                            }
                            _seriesWin = 0;
                        }
                        else { //freezer is ON
                            userLeader[msg.sender].wintime = userLeader[msg.sender].wintime + 1;
                            if (i == 0 && userLeader[msg.sender].prevWin == true){
                                _seriesWin = userLeader[msg.sender].seriesWin + 1;
                            }
                            else {
                                _seriesWin += 1;
                            }
                        }
                    }
                }
            }
            // Round invalid, refund bet amount
            else {
                require(refundable(epochs[i], msg.sender), "Not eligible for refund");
                addedReward = ledger[epochs[i]][msg.sender].amount;
                addedReward += ledger[epochs[i]][msg.sender].freezer;
                refundCheck = true;
            }

            order = i;
            ledger[epochs[i]][msg.sender].claimed = true;
            reward += addedReward;

            emit Claim(msg.sender, epochs[i], addedReward);
        }

        if (claimable(epochs[order], msg.sender) || ledger[epochs[order]][msg.sender].freezer != 0) {
            userLeader[msg.sender].prevWin = true;
        }
        else {
            userLeader[msg.sender].prevWin = false;
        }

        if (reward > 0) {
            if (checkSpecialRound()){
                acaToken.safeTransfer(msg.sender, reward);
                refundCheck = false;
            }
            else{
                acaToken.safeTransfer(msg.sender, reward.mul(99).div(100)); 
                PendingAmountSpecial += reward.div(100); //for special round per day
                refundCheck = false;
            }
        }
        if (userLeader[msg.sender].seriesWin < _seriesWin) {
            userLeader[msg.sender].seriesWin = _seriesWin;
        }
    }

    /**
     * @notice Start the next round n, lock price for round n-1, end round n-2
     * @dev Callable by operator
     */
    function executeRound() external virtual override whenNotPaused onlyOperator {
        require(
            genesisStartOnce && genesisLockOnce,
            "Can only run after genesisStartRound and genesisLockRound is triggered"
        );
        require(checkPriceUpdated(), "Price of current round is not updated.");

        uint256 currentRoundId = currentEpoch; 
        uint256 currentPrice = price_;

        // CurrentEpoch refers to previous round (n-1)
        _safeLockRound(currentEpoch, currentRoundId, currentPrice);
        _safeEndRound(currentEpoch - 1, currentRoundId, currentPrice);
        _calculateRewards(currentEpoch - 1);

        // Increment currentEpoch to current round (n)
        currentEpoch = currentEpoch + 1;
        _safeStartRound(currentEpoch);
    }

    /**
     * @notice Lock genesis round
     * @dev Callable by operator
     */
    function genesisLockRound() external virtual override whenNotPaused onlyOperator {
        require(genesisStartOnce, "Can only run after genesisStartRound is triggered");
        require(!genesisLockOnce, "Can only run genesisLockRound once");
        require(checkPriceUpdated(), "Price of current round is not updated.");

        uint256 currentRoundId = currentEpoch;
        uint256 currentPrice = price_;

        _safeLockRound(currentEpoch, currentRoundId, currentPrice);

        currentEpoch = currentEpoch + 1;
        _startRound(currentEpoch);
        genesisLockOnce = true;
    }

    /**
     * @notice Start genesis round
     * @dev Callable by admin or operator
     */
    function genesisStartRound() external virtual override whenNotPaused onlyOperator {
        require(!genesisStartOnce, "Can only run genesisStartRound once");

        currentEpoch = currentEpoch + 1;
        _startRound(currentEpoch);
        genesisStartOnce = true;
    }

   

    /**
     * @notice Get the claimable stats of specific epoch and user account
     * @param epoch: epoch
     * @param user: user address
     */
    function claimable(uint256 epoch, address user) public view returns (bool) {
        BetInfo memory betInfo = ledger[epoch][user];
        Round memory round = rounds[epoch];
        if (round.lockPrice == round.closePrice) {
            return false;
        }
        return
            round.oracleCalled &&
            betInfo.amount != 0 &&
            !betInfo.claimed &&
            ((round.closePrice > round.lockPrice && betInfo.position == Position.Bull) ||
                (round.closePrice < round.lockPrice && betInfo.position == Position.Bear));
    }

    /**
     * @notice Get the refundable stats of specific epoch and user account
     * @param epoch: epoch
     * @param user: user address
     */
    function refundable(uint256 epoch, address user) public view returns (bool) {
        BetInfo memory betInfo = ledger[epoch][user];
        Round memory round = rounds[epoch];
        return
            !round.oracleCalled &&
            !betInfo.claimed &&
            block.timestamp > round.closeTimestamp + bufferSeconds &&
            betInfo.amount != 0;
    }

    /**
     * @notice Calculate rewards for round
     * @param epoch: epoch
     */
    function _calculateRewards(uint256 epoch) internal {
        require(rounds[epoch].rewardBaseCalAmount == 0 && rounds[epoch].rewardAmount == 0, "Rewards calculated");
        Round storage round = rounds[epoch];
        uint256 rewardBaseCalAmount;
        uint256 BBAmt;
        uint256 rewardAmount;

        if (checkSpecialRound()){
            round.totalAmount = round.totalAmount + PendingAmountSpecial;
        }

        // Bull wins
        if (round.closePrice > round.lockPrice) {
            rewardBaseCalAmount = round.bullAmount;
            BBAmt = (round.totalAmount * BBFee) / 10000;
            rewardAmount = round.totalAmount - BBAmt;
        }
        // Bear wins
        else if (round.closePrice < round.lockPrice) {
            rewardBaseCalAmount = round.bearAmount;
            BBAmt = (round.totalAmount * BBFee) / 10000;
            rewardAmount = round.totalAmount - BBAmt;
        }
        // House wins
        else {
            rewardBaseCalAmount = 0;
            rewardAmount = 0;
            BBAmt = round.totalAmount; //Need to be burnt
        }
        round.rewardBaseCalAmount = rewardBaseCalAmount;
        round.rewardAmount = rewardAmount;

        // Add to BB
        BBAmount += BBAmt;

        emit RewardsCalculated(epoch, rewardBaseCalAmount, rewardAmount, BBAmt);
    }

    /**
     * @notice End round
     * @param epoch: epoch
     * @param roundId: roundId
     * @param price: price of the round
     */
    function _safeEndRound(
        uint256 epoch,
        uint256 roundId,
        uint256 price
    ) internal {
        require(rounds[epoch].lockTimestamp != 0, "Can only end round after round has locked");
        require(block.timestamp >= rounds[epoch].closeTimestamp, "Can only end round after closeTimestamp");
        require(
            block.timestamp <= rounds[epoch].closeTimestamp + bufferSeconds,
            "Can only end round within bufferSeconds"
        );
        Round storage round = rounds[epoch];
        round.closePrice = price;
        round.closeOracleId = roundId;
        round.oracleCalled = true;

        emit EndRound(epoch, roundId, round.closePrice);
    }

    /**
     * @notice Lock round
     * @param epoch: epoch
     * @param roundId: roundId
     * @param price: price of the round
     */
    function _safeLockRound(
        uint256 epoch,
        uint256 roundId,
        uint256 price
    ) internal {
        require(rounds[epoch].startTimestamp != 0, "Can only lock round after round has started");
        require(block.timestamp >= rounds[epoch].lockTimestamp, "Can only lock round after lockTimestamp");
        require(
            block.timestamp <= rounds[epoch].lockTimestamp + bufferSeconds,
            "Can only lock round within bufferSeconds"
        );
        Round storage round = rounds[epoch];
        round.closeTimestamp = block.timestamp + intervalSeconds;
        round.lockPrice = price;
        round.lockOracleId = roundId;

        emit LockRound(epoch, roundId, round.lockPrice);
    }

    /**
     * @notice Start round
     * Previous round n-2 must end
     * @param epoch: epoch
     */
    function _safeStartRound(uint256 epoch) internal {
        require(genesisStartOnce, "Can only run after genesisStartRound is triggered");
        require(rounds[epoch - 2].closeTimestamp != 0, "Can only start round after round n-2 has ended");
        require(
            block.timestamp >= rounds[epoch - 2].closeTimestamp,
            "Can only start new round after round n-2 closeTimestamp"
        );
        _startRound(epoch);
    }


    /**
     * @notice Start round
     * Previous round n-2 must end
     * @param epoch: epoch
     */
    function _startRound(uint256 epoch) internal {
        Round storage round = rounds[epoch];
        round.startTimestamp = block.timestamp;
        round.lockTimestamp = block.timestamp + intervalSeconds;
        round.closeTimestamp = block.timestamp + (2 * intervalSeconds);
        round.epoch = epoch;
        round.totalAmount = 0;

        emit StartRound(epoch);
    }

    /**
     * @notice Determine if a round is valid for receiving bets
     * Round must have started and locked
     * Current timestamp must be within startTimestamp and closeTimestamp
     */
    function _bettable(uint256 epoch) internal view returns (bool) {
        return
            rounds[epoch].startTimestamp != 0 &&
            rounds[epoch].lockTimestamp != 0 &&
            block.timestamp > rounds[epoch].startTimestamp &&
            block.timestamp < rounds[epoch].lockTimestamp;
    }


    function _getPriceFromOracle(uint256 _price) external virtual override onlyOwner{
        Round memory round = rounds[currentEpoch];
        require (!updated, "Already updated");
        require(round.lockTimestamp - oracleUpdateAllowance < block.timestamp && block.timestamp < round.lockTimestamp + oracleUpdateAllowance, "Not in proper timing");
        price_ = _price;
        updated = true;
    }

    function checkPriceUpdated() public returns (bool) {
        if (updated == true) {
            updated = false;
            return true;
        } else {
            return false;
        }
    }
    
    function checkSpecialRound() internal view returns(bool) {
        if (currentEpoch%144 == 0 && currentEpoch != 0) {
            return true;
        }
        else {
            return false;
        }
    }

    //For leaderboard

    function win_and_series_number() external view returns(uint256, uint256) {
        return (userLeader[msg.sender].wintime, userLeader[msg.sender].seriesWin);
    }

    function playTime() external view returns(uint256) {
        return userLeader[msg.sender].playtime;
    }

     /**
     * @notice called by the admin to pause, triggers stopped state
     * @dev Callable by admin or operator
     */
    function pause() external virtual override whenNotPaused onlyAdminOrOperator {
        _pause();

        emit Pause(currentEpoch);
    }

    /**
     * @notice Claim all rewards in BB
     * @dev Callable by admin
     */
    function claimBB() external virtual override nonReentrant onlyAdmin {
        uint256 currentBBAmount = BBAmount;
        BBAmount = 0;
        acaToken.safeTransfer(adminAddress, currentBBAmount); //adminAddress will be same as trasury address for easy calculations

        emit BBClaim(currentBBAmount);
    }

    /**
     * @notice called by the admin to unpause, returns to normal state
     * Reset genesis state. Once paused, the rounds would need to be kickstarted by genesis
     */
    function unpause() external virtual override whenPaused onlyAdmin {
        genesisStartOnce = false;
        genesisLockOnce = false;
        _unpause();

        emit Unpause(currentEpoch);
    }

    /**
     * @notice Set buffer and interval (in seconds)
     * @dev Callable by admin
     */
    function setBufferAndIntervalSeconds(uint256 _bufferSeconds, uint256 _intervalSeconds)
        virtual
        override
        external
        whenPaused
        onlyAdmin
    {
        require(_bufferSeconds < _intervalSeconds, "bufferSeconds must be inferior to intervalSeconds");
        bufferSeconds = _bufferSeconds;
        intervalSeconds = _intervalSeconds;

        emit NewBufferAndIntervalSeconds(_bufferSeconds, _intervalSeconds);
    }

    /**
     * @notice Set minBetAmount
     * @dev Callable by admin
     */
    function setMinBetAmount(uint256 _minBetAmount) external virtual override whenPaused onlyAdmin {
        require(_minBetAmount != 0, "Must be superior to 0");
        minBetAmount = _minBetAmount;

        emit NewMinBetAmount(currentEpoch, minBetAmount);
    }

    /**
     * @notice Set operator address
     * @dev Callable by admin
     */
    function setOperator(address _operatorAddress) external virtual override onlyAdmin {
        require(_operatorAddress != address(0), "Cannot be zero address");
        operatorAddress = _operatorAddress;

        emit NewOperatorAddress(_operatorAddress);
    }


    /**
     * @notice Set oracle update allowance
     * @dev Callable by admin
     */
    function setOracleUpdateAllowance(uint256 _oracleUpdateAllowance) external virtual override whenPaused onlyAdmin {
        oracleUpdateAllowance = _oracleUpdateAllowance;

        emit NewOracleUpdateAllowance(_oracleUpdateAllowance);
    }

    /**
     * @notice Set BB fee
     * @dev Callable by admin
     */
    function setBBFee(uint256 _BBFee) external virtual override whenPaused onlyAdmin {
        require(_BBFee <= MAX_BB_FEE, "BB fee too high");
        BBFee = _BBFee;

        emit NewBBFee(currentEpoch, BBFee);
    }

    /**
     * @notice It allows the owner to recover tokens sent to the contract by mistake
     * @param _token: token address
     * @param _amount: token amount
     * @dev Callable by owner
     */
    function recoverToken(address _token, uint256 _amount) external virtual override onlyOwner {
        IERC20(_token).safeTransfer(address(msg.sender), _amount);

        emit TokenRecovery(_token, _amount);
    }

    /**
     * @notice Set admin address
     * @dev Callable by owner
     */
    function setAdmin(address _adminAddress) external virtual override onlyOwner {
        require(_adminAddress != address(0), "Cannot be zero address");
        adminAddress = _adminAddress;

        emit NewAdminAddress(_adminAddress);
    }

    /**
     * @notice Returns round epochs and bet information for a user that has participated
     * @param user: user address
     * @param cursor: cursor
     * @param size: size
     */
    function getUserRounds(
        address user,
        uint256 cursor,
        uint256 size
    )
        external
        virtual
        view
        returns (
            uint256[] memory,
            BetInfo[] memory,
            uint256
        )
    {
        uint256 length = size;

        if (length > userRounds[user].length - cursor) {
            length = userRounds[user].length - cursor;
        }

        uint256[] memory values = new uint256[](length);
        BetInfo[] memory betInfo = new BetInfo[](length);

        for (uint256 i = 0; i < length; i++) {
            values[i] = userRounds[user][cursor + i];
            betInfo[i] = ledger[values[i]][user];
        }

        return (values, betInfo, cursor + length);
    }

    /**
     * @notice Returns round epochs length
     * @param user: user address
     */
    function getUserRoundsLength(address user) external virtual view returns (uint256) {
        return userRounds[user].length;
    }


    /**
     * @notice Returns true if `account` is a contract.
     * @param account: account address
     */
    function _isContract(address account) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }
}