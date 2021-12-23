// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "./interfaces/IERC20.sol";
import "./utils/SafeERC20.sol";
import "./utils/ERC20.sol";
import "./utils/Ownable.sol";
import "./utils/Ownable.sol";
import "./utils/Address.sol";
import "./interfaces/ITreasury.sol";
import "./utils/ContractGuard.sol";
import "./utils/SafeMath.sol";

contract Treasury is ITreasury, ContractGuard, ERC20, Ownable{
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using Address for address;

    bool public initialized;
    IERC20 public _aca;
    uint256 private _totalSupply = 0;
    mapping(address => uint256) public _balances;

    uint256 public acaReward = 16800 ether;
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

    function initialize(IERC20 _aca) public onlyOwner {
        require (initialized == false, "Already initialized");
        aca = _aca;

        initialized = true;

        emit Initialized(msg.sender, block.timestamp, block.number);
    }

    function updateAcaciaReward(uint256 _acaReward) external onlyOwner {
        require (_acaReward > 0 , "Zero aca reward");
        acaReward = _acaReward;
    }

    function setLockUp(uint256 _withdrawLockup) external onlyOwner {
        withdrawLockup = _withdrawLockup;
    }

    function setAdditionalReward(uint256 _additionalPercentage) external onlyOwner {
        require (_additionalPercentage > 0, "Zero percentage");
        additionalPercentage = _additionalPercentage;
    }

    /***************** VIEW FUNCTIONS *****************/
    function canWithdraw(address user) public view returns (bool) {
        return users[user].LatestStaking.add(withdrawLockup) <= block.timestamp;
    }

    function getLatestStaking() public view returns (uint256) {
        return users[msg.sender].LatestStaking;
    }

    function update_RPS() public view returns (uint256) {
        require (totalSupply() > 0, "Divided by 0");
        return acaReward.div(totalSupply()).div(24*60*60);
    }

    function displayReward() external updateReward(msg.sender) view returns (uint256) {
        return users[msg.sender].rewardEarned; //For frontend display. Interval = 10s
    }

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    /***************** MUTABLE FUNCTIONS *****************/
    function _stake(uint256 amount) virtual public onlyOneBlock{ 
        require(amount>0, "Cannot stake 0");
        users[msg.sender].LatestRewardUpdate = block.timestamp;
        users[msg.sender].LatestStaking =block.timestamp;
        stake(amount);
        emit Staked(msg.sender, amount);
    }

    function _withdraw(uint256 amount) virtual public onlyOneBlock userExists updateReward(msg.sender){
        require (amount <= balanceOf(msg.sender) && amount > 0, "Out of Range");
        require (canWithdraw(msg.sender), "Wait for at least 7 days");
        users[msg.sender].LatestStaking = block.timestamp;
        users[user].LatestRewardUpdate =block.timestamp;
        claimReward_To_Wallet();
        withdraw(amount);
        emit Withdrawn(msg.sender, amount);
    }

    function claimReward_To_Wallet() virtual public onlyOneBlock updateReward(msg.sender) {
        require(users[msg.sender].rewardEarned > 0, "Cannot get 0 reward");
        uint256 reward = users[msg.sender].rewardEarned;
        users[msg.sender].rewardEarned = 0;
        users[msg.sender].LatestStaking = block.timestamp;
        users[user].LatestRewardUpdate =block.timestamp;
        aca.safeTransfer(msg.sender, reward);
        emit RewardPaid(msg.sender, reward);
    }

    function claimReward_To_Staking() virtual  public onlyOneBlock userExists updateReward(msg.sender) {
        require(users[msg.sender].rewardEarned > 0, "Cannot get 0 reward");
        uint256 reward = users[msg.sender].rewardEarned;
        users[msg.sender].rewardEarned = 0;
        stake(reward);
        emit RewardPaid(msg.sender, reward);

    }
    
    function stake(uint256 amount) internal {
        _totalSupply = _totalSupply.add(amount);
        _balances[msg.sender] = _balances[msg.sender].add(amount);
        aca.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(uint256 amount) internal {
        uint256 userAcacia = _balances[msg.sender];
        require (userAcacia >= amount, "Not enough Acacia Token");
        _totalSupply = _totalSupply.sub(amount);
        _balances[msg.sender] = _balances[msg.sender].sub(amount);
        aca.safeTransfer(msg.sender, amount);
    }

    function updateAddReward(address user) internal returns (uint256) {
        uint256 _now = block.timestamp;
        updateInterval = _now - users[user].LatestRewardUpdate;

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
        else {
            users[user].additionalReward = 4500;
        }
        
        return update_RPS().mul(updateInterval).mul(balanceOf(user)).mul(1 + (users[user].additionalReward).div(10000)); 
    }

}