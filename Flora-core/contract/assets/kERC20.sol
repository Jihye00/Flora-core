// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;
import "../utils/SafeMath.sol";
import "../utils/ERC20Burnable.sol";

contract kERC20 is ERC20Burnable {
    string _name;
    string _symbol;

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public pure returns (uint8) {
        return 18;
    }

    constructor(string memory name_, string memory symbol_) public {
        _name = name_;
        _symbol = symbol_;
    }
}
