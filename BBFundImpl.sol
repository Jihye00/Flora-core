// SPDX-License-Identifier: MIT
pragma solidity 0.5.6;

import "./utils/Math.sol";
import "./interfaces/IERC20.sol";
import "./utils/SafeERC20.sol";
import "./utils/Address.sol";

import "./interfaces/IKlayswapFactory.sol";

import "./BBFundStorage.sol";
import "./BBFund.sol";

contract BBFundImpl is BBFundStorage{
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    /***************** EVENTS *****************/
    event Initialized(address indexed executor, uint256 time, uint256 at);
    /***************** ADMIN FUNCTIONS *****************/
    function _become(BBFund fund) public {
        require(msg.sender == fund.admin(), "Only fund admin can change brains");
        fund._acceptImplementation();
    }

    /***************** MODIFIERS *****************/
    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin");
        _;    
    }

    modifier onlyStrategist() {
        require(msg.sender == strategist || msg.sender == admin, "Strategist or Admin");
        _;
    }

    modifier checkPublicAllow() {
        require (publicAllowed || msg.sender == admin, "Admin or publicAllowed");
        _;
    }

    /***************** CONTRACTS *****************/
    function initialize(address _proa, address _usdt, address _klayswapFactory) public onlyAdmin {
        require (initialized == false, "Already initalized");
        proa = _proa;
        usdt = _usdt;
        klayswapFactory = _klayswapFactory;
        proaPriceToSell = 5 ether;
        proaPriceToBuy = 3 ether;
        publicAllowed = false;
        strategist = msg.sender;

        maxAmountToTrade[proa] = 2000 ether;
        maxAmountToTrade[usdt] = 2000 ether;
        maxAmountToTrade[address(0)] = 2000 ether;

        initialized = true;

        emit Initialized(msg.sender, block.timestamp, block.number);
    }

    function setStrategist(address _strategist) external onlyAdmin {
        require(_strategist != address(0), "Zero address");
        strategist = _strategist;
    }

    function setPublicAllowed(bool _publicAllowed) external onlyStrategist {
        publicAllowed = _publicAllowed;
    }

    function setPRoAPriceToSell(uint256 _priceToSell) external onlyStrategist {
        require(_priceToSell > 0.0 ether, "Out Of Range");
        proaPriceToSell = _priceToSell;
    }

    function setPRoAPriceToBuy(uint256 _priceToBuy) external onlyStrategist {
        require(_priceToBuy > 0.0 ether, "Out of Range");
        proaPriceToBuy = _priceToBuy;
    }

    function setMaxAmountToTrade(address _token, uint256 _maxAmount) external onlyStrategist {
        require (_maxAmount > 0 ether && _maxAmount < 10000 ether, "Out Of Range");
        maxAmountToTrade[_token] = _maxAmount;
    }

    /***************** MUTABLE FUNCTIONS *****************/
    function forceSell(address _buyingToken, uint256 _amount) external onlyStrategist {
        require(getPRoAUpdatedPrice() >= proaPriceToSell, "price is too low to sell");
        _swapToken(proa, _buyingToken, _amount);
    }

    function forceBuy(address _sellingToken, uint256 _amount) external onlyStrategist {
        require(getPRoAUpdatedPrice() <= proaPriceToBuy, "price is too high to buy");
        _swapToken(_sellingToken, proa, _amount);
    }

    function _swapToken(address _inputToken, address _outputToken, uint256 _amount) internal {
        if (_amount == 0) return;
        uint256 _maxAmount = maxAmountToTrade[_inputToken];

        if (_maxAmount > 0 && _maxAmount < _amount) {
            _amount = _maxAmount;
        }

        address[] memory _path;
        IERC20(_inputToken).safeIncreaseAllowance(address(klayswapFactory), _amount);
        IKlayswapFactory(klayswapFactory).exchangeKctPos(_inputToken, _amount, _outputToken, 1, _path);
    }

    /***************** EMERGENCY FUNCTIONS [If Our Contract is Attacked. GOD BLESS ON US] *****************/
    function forceTransfer(address _token, address _to, uint256 amount) public onlyAdmin() {
        IERC20(_token).safeTransfer(_to, amount);
    }
}