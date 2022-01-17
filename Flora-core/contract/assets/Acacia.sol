// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "../utils/SafeMath.sol";
import "../utils/Ownable.sol";
import "../utils/ERC20Burnable.sol";
import "../utils/ERC20.sol";

contract Acacia is ERC20Burnable, Ownable {
    using SafeMath for uint256;

    uint256 public constant TOTAL_SUPPLY = 110000000 ether;
    uint256 public constant POOL_REWARD_ALLOCATION = 36300000 ether;
    uint256 public constant AIRDROP_ALLOCATION = 42350000 ether;
    uint256 public constant INITIAL_SETTING = 1660000 ether; 
    uint256 public constant DEV_FUND_POOL_ALLOCATION = 24300000 ether; //Include marketing
    uint256 public constant For_Investors = 6050000 ether;

    uint256 public constant DURATION = 1825 days;
    uint256 public startTime = 1; // Need to be fixed
    uint256 public endTime = startTime + DURATION;

    uint256 public devFundRewardRatio = (DEV_FUND_POOL_ALLOCATION).div(DURATION);
    address public devFund;
    uint256 public devFundLastClaimed = startTime;

    bool public poolRewardIsMINTED = false;

    constructor (uint256 _startTime) public ERC20("Acacia Token", "Acacia") {
        startTime = _startTime;
        devFundLastClaimed = startTime;
        endTime = startTime + DURATION;
        _mint(msg.sender, INITIAL_SETTING);
        devFund = msg.sender;
    }

    function mint(address recipient, uint256 amount) public onlyOwner returns (bool) {
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
    function distributeReward(address _farmingFund) external onlyOwner {
        require (!poolRewardIsMINTED, "only once");
        require (_farmingFund != address(0), "Zero address");
        poolRewardIsMINTED = true;
        _mint(_farmingFund, POOL_REWARD_ALLOCATION);
    }
    
    function burn(uint256 amount) public override onlyOwner {
        super.burn(amount);
    }

    function burnFrom(address account, uint256 amount) public override onlyOwner {
        super.burnFrom(account, amount);
    }
}