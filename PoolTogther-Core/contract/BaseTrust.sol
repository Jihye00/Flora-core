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


contract BaseTrust is ITrust, ERC20, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    address public tokenA;
    address public tokenB;

    address public klayKspPool;

    address public ksp;
    address public kslp;
    address public aca;

    constructor(
        string memory _name,
        string memory _symbol,
        address _ksp,
        address _kslp,
        address _aca
    ) public ERC20(_name, _symbol, ERC20(_kslp).decimals()) {
        ksp = _ksp;
        kslp = _kslp;
        aca = _aca;
        tokenA = IKSLP(kslp).tokenA();
        tokenB = IKSLP(kslp).tokenB();
        require (tokenA == aca || tokenB == aca, "Wrong token address");
        klayKspPool = IKSP(ksp).tokenToPool(address(0), ksp);

        _approveToken();
    }

    receive () payable external {}

    function _approveToken() internal {
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

    function totalValue() public view virtual override returns (uint256, uint256) {
        (uint256 balAInTrust, uint256 balBInTrust) = _balanceInTrust();
        (uint256 balAInKSLP, uint256 balBInKSLP) = _balanceInKSLP();

        return (balAInTrust.add(balAInKSLP), balBInTrust.add(balBInKSLP));
    }

    function _tokenABalance() internal view returns (uint256) {
        return IERC20(tokenA).balanceOf(address(this));
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
        IKSLP(kslp).addKctLiquidity(_amountA, _amountB);
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

    //Claim
    function _claim() internal {
        IKSLP(kslp).claimReward();
    }

    function deposit(uint256 amountA, uint256 amountB) external virtual override { }

    function depositKlay(uint256 _amount) external payable virtual override { }

    function withdraw(uint256 _shares) external virtual override { }
}