// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "./interfaces/IERC20.sol";
import "./utils/SafeERC20.sol";
import "./utils/Ownable.sol";
import "./utils/Address.sol";
import "./interfaces/ILP.sol";
import "./utils/ReentrancyGuard.sol";
import "./utils/SafeMath.sol";
import "./interfaces/IKSP.sol";
import "./interfaces/IKSLP.sol";

//No ksp and airdrop ksp

contract Treasury is ILP, ReentrancyGuard, Ownable{
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using Address for address;

    IERC20 public aca;
    uint256 private _totalSupply = 0;
    uint256 private order = 0;
    mapping(address => uint256) public _balances;

    uint256 public acaReward = 16800 ether;
    address public BBfund;
    address public acaToken;

    address public kslp;
    address public tokenA;
    address public tokenB;
    address public ksp;

    /***************** STRUCTURE *****************/
    struct BoardData {
        uint256 LatestStaking;
        uint256 rewardEarned;
        uint256 rewardLP;
        uint256 LatestRewardUpdate;
        uint256 order;
        uint256 principal;
    }

    mapping(address => BoardData) public users;
    mapping(uint256 => address) public userOrder;

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
        address user_ = user;
        BoardData memory data = users[user_];
        data.rewardEarned = updateAddReward(user_).add(data.rewardEarned);
        users[user_] = data;
        _;
    }


    /***************** CONTRACTS *****************/
    constructor(address _aca, address _kslp, address _ksp, address _BBfund) public {
        aca = IERC20(_aca);
        acaToken = _aca;
        ksp = _ksp;
        kslp = _kslp;
        tokenA = IKSLP(kslp).tokenA(); //if klay + aca, tokenA is klay
        tokenB = IKSLP(kslp).tokenB(); //if aca + usdt, tokenA is aca
        BBfund = _BBfund;
    }

    function updateAcaciaReward(uint256 _acaReward) external onlyOwner {
        require (_acaReward > 0 , "Zero aca reward");
        acaReward = _acaReward;
    }


    /***************** VIEW FUNCTIONS *****************/

    function getLatestStaking(address user_) public view returns (uint256) {
        return users[user_].LatestStaking;
    }

    function update_RPS(address user_) public view returns (uint256) {
        require (totalSupply() > 0, "Divided by 0");
        return acaReward.mul(balanceOf(user_)).div(totalSupply()).div(24*60*60);
    }

    function displayReward() external updateReward(msg.sender) returns (uint256) {
        return users[msg.sender].rewardEarned; //For frontend display. Interval = 10s
    }

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address user_) public view returns (uint256) {
        return _balances[user_];
    }

    function principal(address user_) public view returns (uint256) {
        return users[user_].principal;
    }

    function rewardLP(address user_) public view returns (uint256) {
        return _balances[user_].sub(users[user_].principal);
    }

    /***************** MUTABLE FUNCTIONS *****************/
    function _stake(uint256 amount) virtual override public nonReentrant{ 
        require(amount>0, "Cannot stake 0");
        if (users[msg.sender].LatestStaking == 0) {
            users[msg.sender].order = order;
            userOrder[order] = msg.sender;
            order += 1;
        }
        users[msg.sender].LatestRewardUpdate = block.timestamp;
        users[msg.sender].LatestStaking = block.timestamp;
        users[msg.sender].principal += amount;
        stake(amount);
        emit Staked(msg.sender, amount);
    }

    function _withdraw(uint256 amount) virtual override public nonReentrant userExists updateReward(msg.sender){
        require (amount <= balanceOf(msg.sender) && amount > 0, "Out of Range");
        users[msg.sender].LatestStaking = block.timestamp;
        users[msg.sender].LatestRewardUpdate =block.timestamp;
        claimReward_To_Wallet();
        withdraw(amount);
        emit Withdrawn(msg.sender, amount);
    }

    function claimReward_To_Wallet() virtual override public nonReentrant updateReward(msg.sender){
        require(users[msg.sender].rewardEarned > 0, "Cannot get 0 reward");
        uint256 reward = users[msg.sender].rewardEarned;
        users[msg.sender].rewardEarned = 0;
        users[msg.sender].LatestStaking = block.timestamp;
        users[msg.sender].LatestRewardUpdate =block.timestamp;
        aca.safeTransfer(msg.sender, reward);
        emit RewardPaid(msg.sender, reward);
    }    

    function stake(uint256 amount) internal {
        _totalSupply = _totalSupply.add(amount);
        _balances[msg.sender] = _balances[msg.sender].add(amount);
        IERC20(kslp).safeTransferFrom(msg.sender, address(this), amount);
    }

    function rebalance() public onlyOwner {
        IKSLP(kslp).claimReward();
        address[] memory path = new address[](0);
        uint256 amountToSwap = IERC20(acaToken).balanceOf(address(this)).div(2);

        uint256 before = IERC20(kslp).balanceOf(address(this));

        if (tokenA != address(0)) {
            IKSP(ksp).exchangeKctPos(acaToken, amountToSwap, tokenB, 1, path);
            IKSLP(kslp).addKctLiquidity(IERC20(tokenA).balanceOf(address(this)), IERC20(tokenB).balanceOf(address(this)));
        } else {
            IKSP(ksp).exchangeKctPos(acaToken, amountToSwap, tokenA, 1, path);
            uint256 balanceKlay = (payable(address(this))).balance;
            IKSLP(kslp).addKlayLiquidity{value: balanceKlay}(IERC20(tokenB).balanceOf(address(this)));
        }

        distReward(IERC20(kslp).balanceOf(address(this)).sub(before));
    }

    function distReward(uint256 profit) internal {
        for (uint256 i = 0; i < order; i ++){
            if (_balances[userOrder[i]]!= 0){
                _balances[userOrder[i]] += profit.mul(_balances[userOrder[i]]).div(_totalSupply);
            }
        }
    }

    function withdraw(uint256 amount) internal {
        uint256 userLP = _balances[msg.sender];
        require (userLP >= amount, "Not enough LP Token");
        _totalSupply = _totalSupply.sub(amount);
        _balances[msg.sender] = _balances[msg.sender].sub(amount);
        IERC20(kslp).safeTransfer(msg.sender, amount);
    }

    function updateAddReward(address user) internal view returns (uint256) {
        uint256 _now = block.timestamp;
        uint256 updateInterval = _now - users[user].LatestRewardUpdate;

        return update_RPS(user).mul(updateInterval); 
    }
}