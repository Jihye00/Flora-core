// SPDX-License-Identifier: MIT
pragma solidity 0.5.6;

import "./interfaces/IERC20.sol";
import "./utils/SafeERC20.sol";

import "./Owner/Operator.sol";
import "./interfaces/ITreasury.sol";
import "./utils/ContractGuard.sol";

contract proaWrapper {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    
    IERC20 public proa;

    uint256 private _totalSupply = 1;
    mapping(address => uint256) private _balances;

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function stake(uint256 amount) public {
        _totalSupply = _totalSupply.add(amount);
        _balances[msg.sender] = _balances[msg.sender].add(amount);
        proa.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(uint256 amount) public {
        uint256 userPRoA = _balances[msg.sender];
        require (userPRoA >= amount, "Not enough PRoA Token");
        _totalSupply = _totalSupply.sub(amount);
        _balances[msg.sender] = _balances[msg.sender].sub(amount);
        proa.safeTransfer(msg.sender, amount);
    }
}

contract Treasury is proaWrapper, ContractGuard, Operator {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using Address for address;

    bool public initialized;
    
    uint256 public proaReward = 35000 ether;
    uint256 public proaRewardPerSec = proaReward.div(totalSupply()).div(24*60*60);
    uint256 public withdrawLockup = 7 days;
    uint256 public updateInterval;
    uint256 public additionalPercentage = 15; //0.15%
    address public treasury;
    
    /***************** STRUCTURE *****************/
    struct BoardData {
        uint256 LatestStaking;
        uint256 rewardEarned;
        uint256 firstStaking = 0;
        uint256 additionalReward; //100 for 1%, 1000 for 10%
        uint256 LatestRewardUpdate;
    }
    mapping(address => BoardData) public users;

    /***************** EVENTS *****************/
    event Initialized(address indexed executor, uint256 time, uint256 at);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardAdded(address indexed user, uint256 reward);

    /***************** MODIFIERS *****************/
    modifier userExists {
        require(balanceOf(msg.sender) > 0, "User not exists");
        _;
    }

    modifier updateReward(address user) {
        require(user != address(0), "Zero account");
        if (balanceOf(user) == 0) { //For initial users
            uesrs[user].LatestRewardUpdate = block.timestamp;
        }
        BoardData memory data = users[user];
        data.rewardEarned = updateAddReward(user).add(data.rewardEarned);
        data.LatestRewardUpdate = block.timestamp;
        users[user] = data;
        _;
    }

    /***************** CONTRACTS *****************/
    constructor() public {
        withdrawLockup = 7 days;
    }

    function initalize(IERC20 _proa, address _treasury) public onlyOperator {
        require (initialized == false, "Already initialized");
        treasury = _treasury;
        proa = _proa;
        initialized = true;

        emit Initialized(msg.sender, block.timestamp, block.number);
    }

    function updatePRoAReward(uint256 _proaReward) public onlyOperator {
        require (_proaReward > 0 , "Zero proa reward");
        proaReward = _proaReward;
    }

    function setLockUp(uint256 _withdrawLockup) external onlyOperator {
        withdrawLockup = _withdrawLockup;
    }

    function setAdditionalReward(uint256 _additionalPercentage) public onlyOperator {
        require (_additionalPercentage > 0, "Zero percentage");
        additionalPercentage = _additionalPercentage;
    }

    /***************** VIEW FUNCTIONS *****************/
    function canWithdraw(address user) public view returns (bool) {
        return users[user].LatestStaking.add(withdrawLockup) <= block.timestamp;
    }
    
    function canWithdrawOut(address user) external view returns (bool) {
        return users[user].LatestStaking.add(withdrawLockup) <= block.timestamp;
    }

    function getLatestStaking(address user) public view returns (uint256) {
        return users[user].LatestStaking;
    }

    function update_RPS() public view returns (uint256) {
        return proaReward.div(totalSupply()).div(24*60*60);
    }

    /***************** MUTABLE FUNCTIONS *****************/
    function _stake(uint256 amount) public onlyOneBlock updateReward(msg.sender){ 
        require(amount>0, "Cannot stake 0");
        //Store first staking moment for additional reward
        if (users[msg.sender].firstStaking == 0){
            uers[msg.sender].firstStaking = block.timestamp;
        }
        proaWrapper.stake(amount);
        users[msg.sender].LatestStaking = block.timestamp;
        emit Staked(msg.sender, amount);
    }

    function _withdraw(uint256 amount) public onlyOneBlock userExists updateReward(msg.sender){
        require (amount > 0, "Cannot withdraw 0");
        require (canWithdraw(msg.sender), "Wait for 7 days");
        users[msg.sender].firstStaking = 0;
        claimReward();
        proaWrapper.withdraw(amount);
        emit Withdrawn(msg.sender, amount);
    }

    function exit() external {
        _withdraw(balanceOf(msg.sender));
    }

    function claimReward() public updateReward(msg.sender) {
        require(users[msg.sender].rewardEarned > 0, "Cannot get 0 reward");
        uint256 reward = users[msg.sender].rewardEarned;
        users[msg.sender].rewardEarned = 0;
        proa.safeTransfer(msg.sender, reward);
        emit RewardPaid(msg.sender, reward);
    }

    function updateAddReward(address user) public returns (uint256) {
        uint256 _now = block.timestamp;
        updateInterval = _now - users[user].LatestRewardUpdate;
        if (_now - users[user].firstStaking > 7 days && _now - users[user].firstStaking < 60 days) {
            users[user].additionalReward = (_now - users[user].firstStaking).div((1 days)).mul(additionalPercentage); //Max 9% additional reward
        }
        return update_RPS().mul(updateInterval).mul(balanceOf(user)).mul(users[user].additionalReward).div(10000); 
    }

    function displayReward(address user) public updateReward(msg.sender) returns (uint256) {
        return users[user].rewardEarned; //For frontend display. Interval = 10s
    }

}