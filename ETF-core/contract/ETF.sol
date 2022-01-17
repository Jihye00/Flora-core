// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "./interfaces/IERC20.sol";
import "./interfaces/IKSLP.sol";
import "./interfaces/IERC20.sol";
import "./utils/ERC20.sol";
import "./utils/SafeERC20.sol";
import "./utils/SafeMath.sol";
import "./utils/ReentrancyGuard.sol";
import "./utils/Address.sol";
import "./utils/Ownable.sol";
import "./interfaces/IKSLP.sol";
import "./interfaces/IKSP.sol";
import "./interfaces/IETF.sol";
//This is the code for ETF service in Flora.finance
//V1 : USDT 
//V2 : NFT (Not only for pool)
//V3 : DeFi
contract ETF is IETF, Ownable, ReentrancyGuard {

    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    uint256 public totalAmount;
    uint256 public rebalanceInterval;
    uint256 public additionalProfit;
    uint256 private order = 0;

    address LP_A; //KSP + usdt
    address LP_B; //ETH + usdt
    address LP_C; //Aca + usdt

    uint256 distributionA;
    uint256 distributionB;
    uint256 distributionC;

    address usdt;
    address tokenA; //KSP
    address tokenB; //ETH
    address tokenC; //aca
    address ksp;
    address klaykspPool;

    struct userInfo {
        uint256 amount;
        uint256 depositTime;
        uint256 order;
    }

    mapping(address => userInfo) users;
    mapping(uint256 => address) userOrder;

    constructor(
        address _usdt, 
        address _LP_A, 
        address _LP_B, 
        address _LP_C, 
        uint256 _distA,
        uint256 _distB,
        uint256 _distC,
        address _ksp, 
        uint256 _rebalanceInterval) public {
        usdt = _usdt;
        LP_A = _LP_A;
        LP_B = _LP_B;
        LP_C = _LP_C;
        distributionA = _distA;
        distributionB = _distB;
        distributionC = _distC;
        ksp = _ksp;
        rebalanceInterval = _rebalanceInterval;
        klaykspPool = IKSP(ksp).tokenToPool(address(0), ksp);

        tokenA = IKSLP(LP_A).tokenA();
        tokenB = IKSLP(LP_B).tokenA();
        tokenC = IKSLP(LP_C).tokenA();

        _approveToken();
    }

    receive () payable external {}

    function _approveToken() internal {
        IERC20(tokenA).approve(LP_A, uint256(-1));
        IERC20(tokenB).approve(LP_B, uint256(-1));
        IERC20(tokenC).approve(LP_C, uint256(-1));
        IERC20(usdt).approve(LP_A, uint256(-1));
        IERC20(usdt).approve(LP_B, uint256(-1));
        IERC20(usdt).approve(LP_C, uint256(-1));
        IERC20(ksp).approve(ksp, uint256(-1));
    }

    function changeDistri(uint256 forA, uint256 forB, uint256 forC) public onlyOwner {
        require ((forA + forB + forC) == 10000, "Ratio isn't matched");

        distributionA = forA;
        distributionB = forB;
        distributionC = forC;
    }

    function deposit(uint256 _amount) external virtual override nonReentrant {
        require (_amount > 0, "Cannot deposit 0");

        uint256 before = IERC20(usdt).balanceOf(address(this));

        IERC20(usdt).transferFrom(msg.sender, address(this), _amount);

        uint256 forA = _amount.mul(distributionA).div(20000); //KSP + USDT
        uint256 forB = _amount.mul(distributionB).div(20000);
        uint256 forC = _amount.mul(distributionC).div(20000);

        uint256 beforeA = IERC20(tokenA).balanceOf(address(this));
        uint256 beforeB = IERC20(tokenB).balanceOf(address(this));
        uint256 beforeC = IERC20(tokenC).balanceOf(address(this));

        _swap(forA, forB, forC);

        _addliquidity(forA, forB, forC, IERC20(tokenA).balanceOf(address(this)) - beforeA, IERC20(tokenB).balanceOf(address(this)) - beforeB, IERC20(tokenC).balanceOf(address(this)) - beforeC);   

        if (users[msg.sender].depositTime == 0) {
            users[msg.sender].order = order;
            userOrder[order] = msg.sender;
            order += 1;
        }

        users[msg.sender].depositTime = block.timestamp;
        uint256 _after = IERC20(usdt).balanceOf(address(this)); 

        if ((_after - before) != 0) {
            uint256 give = (_after - before);
            IERC20(usdt).transfer(msg.sender, give);
            users[msg.sender].amount += _amount.sub(give); 
            totalAmount += _amount.sub(give);
        }
        else {
            users[msg.sender].amount += _amount;
            totalAmount += _amount;
        }
    }

    function deposit_rebalance(uint256 _amount) internal {

        uint256 forA = _amount.mul(distributionA).div(20000);
        uint256 forB = _amount.mul(distributionB).div(20000);
        uint256 forC = _amount.mul(distributionC).div(20000);
        
        uint256 beforeA = IERC20(tokenA).balanceOf(address(this));
        uint256 beforeB = IERC20(tokenB).balanceOf(address(this));
        uint256 beforeC = IERC20(tokenC).balanceOf(address(this));

        _swap(forA, forB, forC);

        _addliquidity(forA, forB, forC, IERC20(tokenA).balanceOf(address(this)) - beforeA, IERC20(tokenB).balanceOf(address(this)) - beforeB, IERC20(tokenC).balanceOf(address(this)) - beforeC);
    }

    function withdraw(uint256 _amount) external virtual override nonReentrant {
        require (_amount > 0, "Cannot withdraw 0");
        require (users[msg.sender].amount >= _amount, "More than you have");

        uint256 before_usdt = IERC20(usdt).balanceOf(address(this));
        
        (uint256 beforeA, ) = IKSLP(LP_A).getCurrentPool();
        _removeLiquidity(LP_A, IERC20(LP_A).balanceOf(address(this)).mul(_amount).div(totalAmount));
        (uint256 afterA, ) = IKSLP(LP_A).getCurrentPool();

        (uint256 beforeB, ) = IKSLP(LP_B).getCurrentPool();
        _removeLiquidity(LP_B, IERC20(LP_B).balanceOf(address(this)).mul(_amount).div(totalAmount));
        (uint256 afterB, ) = IKSLP(LP_B).getCurrentPool();

        (uint256 beforeC, ) = IKSLP(LP_C).getCurrentPool();
        _removeLiquidity(LP_C, IERC20(LP_C).balanceOf(address(this)).mul(_amount).div(totalAmount));
        (uint256 afterC, ) = IKSLP(LP_C).getCurrentPool();

        uint256 after_usdt = IERC20(usdt).balanceOf(address(this));

        uint256 withdrawalA = beforeA.sub(afterA);
        uint256 withdrawalB = beforeB.sub(afterB);
        uint256 withdrawalC = beforeC.sub(afterC);

        uint256 withdraw_ = after_usdt.sub(before_usdt);

        users[msg.sender].amount = users[msg.sender].amount.sub(_amount);
        totalAmount = totalAmount.sub(_amount);

        IERC20(tokenA).transfer(msg.sender, withdrawalA);
        IERC20(tokenB).transfer(msg.sender, withdrawalB);
        IERC20(tokenC).transfer(msg.sender, withdrawalC);
        IERC20(usdt).transfer(msg.sender, withdraw_);
    }

    function rebalance() public virtual override onlyOwner {
        IKSLP(LP_A).claimReward();
        IKSLP(LP_B).claimReward();
        IKSLP(LP_C).claimReward();

        uint256 before = IERC20(usdt).balanceOf(address(this));
        swap_from_ksp(usdt);
        swap_from_aca(tokenC, IERC20(tokenC).balanceOf(address(this)));
        additionalProfit += (before - IERC20(usdt).balanceOf(address(this)));

        distReward(before - IERC20(usdt).balanceOf(address(this)));

        deposit_rebalance(IERC20(usdt).balanceOf(address(this)));
    }

    function distReward(uint256 profit) internal {
        for (uint256 i = 0; i < order; i ++){
            if (users[userOrder[i]].amount != 0){
                users[userOrder[i]].amount += profit.mul(users[userOrder[i]].amount).div(totalAmount);
            }
        }
    }

    function swap_from_ksp(address token) internal {
        address[] memory path;
        uint256 kspAmount = IERC20(ksp).balanceOf(msg.sender);
        path = new address[](0);
        address kspTokenPool = IKSP(ksp).tokenToPool(ksp, token);
        uint256 least = IKSLP(kspTokenPool).estimatePos(ksp, kspAmount).mul(9900).div(10000);
        IKSP(ksp).exchangeKctPos(ksp, kspAmount, token, least, path);
    }

    function swap_from_aca(address token, uint256 amount) internal {
        address[] memory path = new address[](0);
        uint256 least = IKSLP(LP_C).estimatePos(token, amount).mul(9900).div(10000);
        IKSP(token).exchangeKctPos(token, amount, usdt, least, path);
    }

    function _removeLiquidity(address lp, uint256 _amount) internal {
        require(_amount <= totalAmount);
        
        IKSLP(lp).removeLiquidity(_amount);
    }

    function _swap(uint256 forA, uint256 forB, uint256 forC) internal {
        address[] memory path = new address[](0); //No routing path

        IKSP(usdt).exchangeKctPos(usdt, forA, tokenA, IKSLP(LP_A).estimatePos(usdt, forA).mul(9900).div(10000), path);
        IKSP(usdt).exchangeKctPos(usdt, forB, tokenB, IKSLP(LP_B).estimatePos(usdt, forB).mul(9900).div(10000), path);
        IKSP(usdt).exchangeKctPos(usdt, forC, tokenC, IKSLP(LP_C).estimatePos(usdt, forC).mul(9900).div(10000), path);

    }

    function _addliquidity(uint256 _forA, uint256 _forB, uint256 _forC, uint256 _amountA, uint256 _amountB, uint256 _amountC) internal {
        
        IKSLP(LP_A).addKctLiquidity(_amountA, _forA);
        IKSLP(LP_B).addKctLiquidity(_amountB, _forB);
        IKSLP(LP_C).addKctLiquidity(_amountC, _forC);

    }

    function _kspTokenPoolExist(address token) internal view returns (bool) {
        try IKSP(ksp).tokenToPool(ksp, token) returns (address pool) {
            return IKSP(ksp).poolExist(pool);
        } catch Error (string memory) {
            return false;
        } catch (bytes memory) {
            return false;
        }
    }

    function userProfit() external override view returns (uint256) {
        return additionalProfit;
    }

}
