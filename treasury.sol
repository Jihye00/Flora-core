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
    uint256 public withdrawLockup = 7 days;
    uint256 public updateInterval;
    uint256 public additionalPercentage = 500; //5%
    address public treasury;
    
    /***************** STRUCTURE *****************/
    struct BoardData {
        uint256 LatestStaking;
        uint256 rewardEarned;
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
        BoardData memory data = users[user];
        data.rewardEarned = updateAddReward(user).add(data.rewardEarned);
        users[user] = data;
        _;
    }

    /***************** CONTRACTS *****************/
    constructor() public {
        withdrawLockup = 7 days;
    }

    function initalize(IERC20 _proa) public onlyOperator {
        require (initialized == false, "Already initialized");
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
    function _stake(uint256 amount) public onlyOneBlock{ 
        require(amount>0, "Cannot stake 0");
        if (balanceOf(msg.sender) == 0) {
            users[msg.sender].LatestRewardUpdate = block.timestamp;
        }
        else {
            if (amount > balanceOf(msg.sender){
                users[msg.sender].LatestStaking = block.timestamp;
            }
        }
        proaWrapper.stake(amount);
        emit Staked(msg.sender, amount);
    }

    function _withdraw(uint256 amount) public onlyOneBlock userExists updateReward(msg.sender){
        require (amount > 0, "Cannot withdraw 0");
        require (canWithdraw(msg.sender), "Wait for 7 days");
        users[msg.sender].LatestStaking = block.timestamp;
        claimReward_To_Wallet();
        proaWrapper.withdraw(amount);
        emit Withdrawn(msg.sender, amount);
    }

    function exit() external {
        _withdraw(balanceOf(msg.sender));
    }

    function claimReward_To_Wallet() public onlyOneBlock updateReward(msg.sender) {
        require(users[msg.sender].rewardEarned > 0, "Cannot get 0 reward");
        uint256 reward = users[msg.sender].rewardEarned;
        users[msg.sender].rewardEarned = 0;
        users[msg.sender].LatestStaking = block.timestamp;
        proa.safeTransfer(msg.sender, reward);
        emit RewardPaid(msg.sender, reward);
    }

    function claimReward_To_Staking() public onlyOneBlock userExists updateReward(msg.sender) {
        require(users[msg.sender].rewardEarned > 0, "Cannot get 0 reward");
        uint256 reward = users[msg.sender].rewardEarned;
        users[msg.sender].rewardEarned = 0;
        proaWrapper.stake(reward);
        emit RewardPaid(msg.sender, reward)

    }

    function updateAddReward(address user) public returns (uint256) {
        uint256 _now = block.timestamp;
        updateInterval = _now - users[user].LatestRewardUpdate;
        if (updateInterval < 30 days) {
            if (updateInterval / 7 days == 0) {
                users[user].additionalReward = 0;
            }
            else if (updateInterval / 7 days == 1) {
                users[user].additionalReward = 500;
            }
            else if (updateInterval / 7 days == 2) {
                users[user].additionalReward = 1000;
            }
            else if (updateInterval / 7 days == 3) {
                users[user].additionalReward = 2000;
            }
            else if (updateInterval / 7 days == 4) {
                users[user].additionalReward = 4500;
            }
        }
        return update_RPS().mul(updateInterval).mul(balanceOf(user)).mul(1 + (users[user].additionalReward).div(10000)); 
    }

    function displayReward(address user) public updateReward(msg.sender) returns (uint256) {
        return users[user].rewardEarned; //For frontend display. Interval = 10s
    }

}