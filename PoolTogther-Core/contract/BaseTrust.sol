// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "./interfaces/IERC20.sol";
import "./utils/ERC20.sol";
import "./utils/SafeERC20.sol";
import "./utils/SafeMath.sol";
import "./utils/ReentrancyGuard.sol";
import "./utils/Address.sol";
import "./utils/Ownable.sol";
import "./interfaces/ITrust.sol";
import "./interfaces/IKSLP.sol";
import "./interfaces/IKSP.sol";


abstract contract BaseTrust is ITrust, ERC20, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    address public tokenA;
    address public tokenB;

    address public klayKspPool;

    address public ksp;
    address public kslp;


    constructor(
        string memory _name,
        string memory _symbol,
        address _ksp,
        address _kslp
    ) public ERC20(_name, _symbol) {
        ksp = _ksp;
        kslp = _kslp;
        tokenA = IKSLP(kslp).tokenA();
        tokenB = IKSLP(kslp).tokenB();

        klayKspPool = IKSP(ksp).tokenToPool(address(0), ksp);
       
        _approveToken();
    }

    receive () payable external {}

    function _approveToken() internal {
        if(tokenA != address(0))
            IERC20(tokenA).approve(kslp, uint256(-1));
        
        IERC20(tokenB).approve(kslp, uint256(-1));
        IERC20(ksp).approve(ksp, uint256(-1));
    }

    function estimateSupply(address token, uint256 amount) public view virtual override returns (uint256) {
        require(token == tokenA || token == tokenB);

        uint256 pos = IKSLP(kslp).estimatePos(token, amount);
        uint256 neg = IKSLP(kslp).estimateNeg(token, amount);

        return (pos.add(neg)).div(2);
    }
    
    function estimateRedeem(uint256 shares) public view virtual returns (uint256, uint256) {
        uint256 totalBWTP = totalSupply();
        require(shares <= totalBWTP);

        (uint256 balanceA, uint256 balanceB) = totalValue();

        uint256 estimatedA = (balanceA.mul(shares)).div(totalBWTP);
        uint256 estimatedB = (balanceB.mul(shares)).div(totalBWTP);

        return (estimatedA, estimatedB);
    }

    function totalValue() public view virtual override returns (uint256, uint256) {
        (uint256 balAInTrust, uint256 balBInTrust) = _balanceInTrust();
        (uint256 balAInKSLP, uint256 balBInKSLP) = _balanceInKSLP();

        return (balAInTrust.add(balAInKSLP), balBInTrust.add(balBInKSLP));
    }

    function _tokenABalance() internal view returns (uint256) {
        uint256 balance = (tokenA == address(0))? 
            (payable(address(this))).balance : IERC20(tokenA).balanceOf(address(this));

        return balance;
    }

    function _tokenBBalance() internal view returns (uint256) {
        return IERC20(tokenB).balanceOf(address(this));
    }

    function _balanceInTrust() internal view returns (uint256, uint256){
        uint256 balanceA = _tokenABalance();
        uint256 balanceB = _tokenBBalance();

        return (balanceA, balanceB);
    }

    function _balanceInKSLP() internal view returns (uint256, uint256) {
        uint256 trustLiquidity = _balanceKSLP();
        uint256 totalLiquidity = IERC20(kslp).totalSupply();

        (uint256 poolA, uint256 poolB) = IKSLP(kslp).getCurrentPool();

        uint256 balanceA = (poolA.mul(trustLiquidity)).div(totalLiquidity);
        uint256 balanceB = (poolB.mul(trustLiquidity)).div(totalLiquidity);

        return (balanceA, balanceB);
    }

    function _balanceKSLP() internal view returns (uint256){
        return IERC20(kslp).balanceOf(address(this));
    }

    function _addLiquidity(uint256 _amountA, uint256 _amountB) internal {
        if(tokenA == address(0))
            IKSLP(kslp).addKlayLiquidity{value: _amountA}(_amountB);
        else
            IKSLP(kslp).addKctLiquidity(_amountA, _amountB);
    }

    function _addLiquidityAll() internal {
        uint256 balanceA = _tokenABalance();
        uint256 balanceB = _tokenBBalance();

        if(balanceA > 0 && balanceB > 0){
            uint256 estimatedA = estimateSupply(tokenB, balanceB);
            uint256 estimatedB = estimateSupply(tokenA, balanceA);

            if(balanceB >= estimatedB)
                _addLiquidity(balanceA, estimatedB);
            else
                _addLiquidity(estimatedA, balanceB);
        }
    }

    function _removeLiquidity(uint256 _amount) internal {
        uint256 totalLP = _balanceKSLP();
        require(_amount <= totalLP);
        
        IKSLP(kslp).removeLiquidity(_amount);
    }


    function claim() public onlyOwner {
        _claim();
    }

    function swap() public onlyOwner {
        _swap();
    }

    function addLiquidityAll() public onlyOwner {
        _addLiquidityAll();
    }

    //KSP Claim
    function _claim() internal {
        IKSLP(kslp).claimReward();
    }

    //Swap KSP to underlying Assets
    function _swap() internal {
        uint256 earned = IERC20(ksp).balanceOf(address(this));

        if(earned > 0) {
            uint256 balanceA = _tokenABalance();
            uint256 balanceB = _tokenBBalance();

            uint256 balanceABasedKSP = (tokenA == ksp)? 0 : _estimateBasedKSP(tokenA, balanceA);
            uint256 balanceBBasedKSP = (tokenB == ksp)? 0 : _estimateBasedKSP(tokenB, balanceB);

            uint256 netEarned = earned;

            uint256 swapAmount = ((netEarned.sub(balanceABasedKSP)).sub(balanceBBasedKSP)).div(2);
            
            uint256 swapAmountA = swapAmount.add(balanceBBasedKSP);
            uint256 swapAmountB = swapAmount.add(balanceABasedKSP);

            if(swapAmountA > 0)
                _swapKSPToToken(tokenA, swapAmountA);
            if(swapAmountB > 0)
                _swapKSPToToken(tokenB, swapAmountB);
        }
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

    function _swapKSPToToken(address token, uint256 amount) internal {
        if(token == ksp)
            return;
        
        address[] memory path;
        if(_kspTokenPoolExist(token)){
            path = new address[](0);
        } else {
            path = new address[](1);
            path[0] = address(0);
        }
        
        uint256 least = (_estimateKSPToToken(token, amount).mul(99)).div(100);
        IKSP(ksp).exchangeKctPos(ksp, amount, token, least, path);
    }

    function _estimateBasedKSP(address token, uint256 amount) internal view returns (uint256) {
        require(token == tokenA || token == tokenB);

        if(token == ksp){
            return amount;
        }

        if(token == address(0)){
            return IKSLP(klayKspPool).estimateNeg(token, amount);
        } 
        else if(_kspTokenPoolExist(token)) {
            address kspTokenPool = IKSP(ksp).tokenToPool(ksp, token);
            return IKSLP(kspTokenPool).estimateNeg(token, amount);
        }
        else {
            address klayTokenPool = IKSP(ksp).tokenToPool(address(0), token);

            uint256 estimatedKlay = IKSLP(klayTokenPool).estimateNeg(token, amount);
            uint256 estimatedKSP = IKSLP(klayKspPool).estimateNeg(address(0), estimatedKlay);

            return estimatedKSP;
        }
    }

    function _estimateKSPToToken(address token, uint256 kspAmount) internal view returns (uint256) {
        require(token == tokenA || token == tokenB);

        if(token == ksp){
            return kspAmount;
        }

        if(token == address(0)){
            return IKSLP(klayKspPool).estimatePos(ksp, kspAmount);
        } 
        else if(_kspTokenPoolExist(token)) {
            address kspTokenPool = IKSP(ksp).tokenToPool(ksp, token);
            return IKSLP(kspTokenPool).estimatePos(ksp, kspAmount);
        }
        else {
            address klayTokenPool = IKSP(ksp).tokenToPool(address(0), token);

            uint256 estimatedKlay = IKSLP(klayKspPool).estimatePos(ksp, kspAmount);
            uint256 estimatedToken = IKSLP(klayTokenPool).estimatePos(address(0), estimatedKlay);
            return estimatedToken;
        }
    }

}