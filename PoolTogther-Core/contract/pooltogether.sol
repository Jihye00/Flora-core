// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "./interfaces/IERC20.sol";
import "./BaseTrust.sol";
import "./interfaces/IKSLP.sol";
import "./interfaces/IPoolTogether.sol";
import "./utils/SafeMath.sol";
import "./utils/Address.sol";
import "./utils/Ownable.sol";
import "./utils/ReentrancyGuard.sol";
import "./utils/ERC20.sol";
import "./utils/SafeERC20.sol";
import "./interfaces/IASSET.sol";

contract poolTogether is BaseTrust, IPoolTogether{

    using SafeMath for uint256;
    using Address for address;
    using SafeERC20 for IERC20;

    uint256 public interval;
    uint256 public drawTime;
    uint256 public _order;
    uint256 public currentId;

    bool private isDraw = true;
    address public aca;

    struct Users {
        uint256 ticketNumber;
        uint256 depositLP;
        uint256 order;
    }

    struct userOrder {
        uint256 ticketNumber;
        address _user;
    }

    enum State {
        open,
        draw,
        end
    }

    struct poolInfo {
        State state;
        uint256 poolStartTime;
        uint256 finalNumber;
        uint256 winnerOrder;
        uint256 totalTicket;
    }


    mapping(address => Users) private user;
    mapping(uint256 => userOrder) private userOrders;
    mapping(uint256 => poolInfo) private pool;

    constructor(
        address _ksp,
        address _kslp,
        address _aca
    ) public BaseTrust(_ksp, _kslp) { 
        interval = 7 days;
        drawTime = 10 minutes;
        _order = 0;
        currentId = 0;
        aca = _aca;
    }

    function deposit(uint256 _amountA, uint256 _amountB) external virtual override nonReentrant {
        require(_amountA > 0 && _amountB > 0, "Deposit must be greater than 0");
        require(pool[currentId].state == State.open, "Can't deposit now");

        (uint256 beforeAInKSLP, uint256 beforeBInKSLP) = IKSLP(kslp).getCurrentPool();
        uint256 beforeLP = _balanceKSLP();

        // Deposit underlying assets and Provide liquidity
        IERC20(tokenA).transferFrom(msg.sender, address(this), _amountA);
        IERC20(tokenB).transferFrom(msg.sender, address(this), _amountB);
        _addLiquidity(_amountA, _amountB);

        (uint256 afterAInKSLP, uint256 afterBInKSLP) = IKSLP(kslp).getCurrentPool();
        uint256 afterLP = _balanceKSLP();

        uint256 depositedA = afterAInKSLP.sub(beforeAInKSLP);
        uint256 depositedB = afterBInKSLP.sub(beforeBInKSLP);

        // Calcualte trust's increased liquidity and account's remaining tokens
        uint256 remainingA = _amountA.sub(depositedA);
        uint256 remainingB = _amountB.sub(depositedB);
        uint256 increasedLP = afterLP.sub(beforeLP);

        uint256 ticketNumber_ = increasedLP.mul(pool[currentId].poolStartTime + interval - block.timestamp).div(100);

        if (user[msg.sender].depositLP != 0){
            user[msg.sender].depositLP += increasedLP;
            user[msg.sender].ticketNumber += ticketNumber_;
            userOrders[user[msg.sender].order].ticketNumber += ticketNumber_;
        } else {
            user[msg.sender].order = _order;
            userOrders[_order]._user = msg.sender;
            _order += 1;
            user[msg.sender].depositLP = increasedLP;
            user[msg.sender].ticketNumber = ticketNumber_;
            userOrders[_order].ticketNumber = ticketNumber_;
        }

        pool[currentId].totalTicket += ticketNumber_;

        // Return change
        if(remainingA > 0)
            IERC20(tokenA).transfer(msg.sender, remainingA);
        if(remainingB > 0)
            IERC20(tokenB).transfer(msg.sender, remainingB);
    }

    function withdraw(uint256 amount) external virtual override nonReentrant {
        require(amount > 0, "Withdraw amount must be greater than 0");
        require(amount <= user[msg.sender].depositLP, "Insufficient balance");
        require(pool[currentId].state == State.open, "Not in proper timimg");

        uint256 beforeLP = user[msg.sender].depositLP;

        user[msg.sender].depositLP -= amount;
        uint256 newTicket= user[msg.sender].ticketNumber.mul(beforeLP - amount).div(beforeLP);
        uint256 discardTicket = user[msg.sender].ticketNumber - newTicket;

        user[msg.sender].ticketNumber = newTicket;
        userOrders[user[msg.sender].order].ticketNumber = newTicket;
        pool[currentId].totalTicket -= discardTicket;
        
        (uint256 beforeAInKSLP, uint256 beforeBInKSLP) = IKSLP(kslp).getCurrentPool();
        _removeLiquidity(amount); 
        (uint256 afterAInKSLP, uint256 afterBInKSLP) = IKSLP(kslp).getCurrentPool();

        uint256 withdrawalA = beforeAInKSLP.sub(afterAInKSLP);
        uint256 withdrawalB = beforeBInKSLP.sub(afterBInKSLP);

        IERC20(tokenA).transfer(msg.sender, withdrawalA);
        IERC20(tokenB).transfer(msg.sender, withdrawalB);
    }

    function openPoolTogether() external virtual override onlyOwner {
        require(isDraw, "Not draw");
        require(currentId == 0 || pool[currentId - 1].poolStartTime + interval <= block.timestamp, "Not yet");
        pool[currentId].state = State.open;
        pool[currentId].poolStartTime = block.timestamp;

        isDraw = false;
    }

    function drawWinner(uint256 randomNumber) external virtual override onlyOwner {
        require(pool[currentId].state == State.open, "Not in proper timimg");
        require(pool[currentId].poolStartTime + interval - drawTime <= block.timestamp, "Not yet");
        pool[currentId].state = State.draw;
        pool[currentId].finalNumber = randomNumber;
        uint256 counter = randomNumber;

        for (uint256 i = 0; i < _order - 1; i++) {
            if (counter >= userOrders[i].ticketNumber) {
                counter = randomNumber.sub(userOrders[i].ticketNumber);
                if (counter <= userOrders[i + 1].ticketNumber) {
                    pool[currentId].winnerOrder = (i + 1);
                    break;
                } else {
                    randomNumber = counter;
                }
            } else {
                pool[currentId].winnerOrder = i;
                break;
            }
        }

        claim();
        uint256 earned = IERC20(aca).balanceOf(address(this));
        IAsset(aca).burn(earned.mul(500).div(10000)); //Burn 5% of total reward
        earned = earned.mul(9500).div(10000);
        IERC20(aca).safeTransfer(userOrders[pool[currentId].winnerOrder]._user, earned);
        pool[currentId].state = State.end;
        currentId += 1;
        isDraw = true;
    }

    function ticketCount() public view onlyOwner returns (uint256){
        return pool[currentId].totalTicket - 1;
    }

    function currentIdCount() public view onlyOwner returns (uint256) {
        return currentId;
    }


    ///////////////// EMERGENCY WITHDRAW /////////////////
    function emergencyCall() public onlyOwner {
        IKSLP(kslp).removeLiquidity(IERC20(kslp).balanceOf(address(this)));
    }

}