pragma solidity ^0.6.0;
import "./utils/SafeMath.sol";
import "./interfaces/IKlayExchange.sol";
import "./interfaces/IgetPrice.sol";

contract getPRoAPrice{
    using SafeMath for uint256;

    uint256 public proaPrice;
    uint256 public usdtPrice;
    uint256 public amountPRoA;
    uint256 public amountUsdt;

    bool public Init = false;
    address public pair = address(0);
    address public banker;

    constructor() public {
        banker = msg.sender;
        usdtPrice = 1;
    }

    modifier onlybanker() {
        require(msg.sender == banker, "You are not banker");
        _;
    }

    function setBanker(address _banker) public onlybanker {
        require (_banker != address(0), "Zero address");
        banker = _banker;
    }
    
    function initialize(address _pair) public onlybanker {
        require (_pair != address(0), "Zero address");
        require (Init == false, "Already initialized");
        Init = true;
        pair = _pair;
    }

    function setUsdtPrice(uint256 _usdtPrice) public onlybanker {
        require(_usdtPrice > 0.0, "Out of Range");
        usdtPrice = _usdtPrice;
    }

    function setPair(address _pair) public onlybanker {
        require (_pair != address(0), "Zero address");
        pair = _pair;
    }

    function getPRoAUpdatedPrice() public returns (uint256) {
        require (pair != address(0), "Not initialized");
        (amountPRoA, amountUsdt) = IKlayExchange(pair).getCurrentPool();
        proaPrice = amountUsdt.mul(usdtPrice).div(amountPRoA);
        return proaPrice;
    }
}