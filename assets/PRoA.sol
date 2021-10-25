pragma solidity 0.5.6;

import "../utils/SafeMath.sol";

import "../Owner/Operator.sol";
import "./kERC20.sol";

contract PRoA is kERC20, Operator {
    using SafeMath for uint256;

    uint256 public constant TOTAL_SUPPLY = 220000000 ether;
    uint256 public constant POOL_REWARD_ALLOCATION = 73000000 ether;
    uint256 public constant AIRDROP_ALLOCATION = 350000 ether;
    uint256 public constant INITIAL_SETTING = 5001 ether; // 1 for staking initializing
    uint256 public constant DEV_FUND_POOL_ALLOCATION = 22000000 ether;

    uint256 public constant DURATION = 1460 days;
    uint256 public startTime = 1;
    uint256 public endTime = startTime + DURATION;

    uint256 public devFundRewardRatio = DEV_FUND_POOL_ALLOCATION.div(DURATION);
    address public devFund;
    uint256 public devFundLastClaimed = startTime;

    bool public poolRewardIsMINTED = false;

    constructor (uint256 _startTime) public kERC20("PRoA Token", "PRoA") {
        startTime = _startTime;
        devFundLastClaimed = startTime;
        endTime = startTime + DURATION;
        _mint(msg.sender, INITIAL_SETTING);
        devFund = msg.sender;
    }

    function mint(address recipient, uint256 amount) public onlyOperator returns (bool) {
        uint256 balanceBefore = balanceOf(recipient);
        _mint(recipient, amount);
        return balanceOf(recipient) > balanceBefore;
    }

    function setDevFund(address _devFund) external {
        require(msg.sender == devFund, "Not a dev fund");
        require(_devFund != address(0), "0 address");
        devFund = _devFund;
    }

    function unclaimedDevFund() public view returns (uint256 _pending) {
        uint256 _now = block.timestamp;
        if (_now > endTime) _now = endTime;
        if (devFundLastClaimed >= _now) return 0;
        return _pending = _now.sub(devFundLastClaimed).mul(devFundRewardRatio);
    }

    function claimRewards() external {
        require (msg.sender == devFund, "Not a dev fund");
        uint256 _pending = unclaimedDevFund();
        if (_pending > 0 && devFund != address(0)) {
            _mint(devFund, _pending);
            devFundLastClaimed = block.timestamp;
        }
    }

    /* Pool distribution allocation */
    function distributeReward(address _farmingFund) external onlyOperator {
        require (!poolRewardIsMINTED, "only once");
        require (_farmingFund != address(0), "Zero address");
        poolRewardIsMINTED = true;
        _mint(_farmingFund, POOL_REWARD_ALLOCATION);
    }
    
    function burn(uint256 amount) public onlyOperator {
        super.burn(amount);
    }

    function burnFrom(address account, uint256 amount) public onlyOperator {
        super.burnFrom(account, amount);
    }
}