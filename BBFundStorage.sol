// SPDX-License-Identifier: MIT
pragma solidity 0.5.6;

contract BBFundAdminStorage {
    /**
    * @notice Administrator for this contract
    */
    address public admin;

    /**
    * @notice Pending administrator for this contract
    */
    address public pendingAdmin;

    /**
    * @notice Active brains of treasury
    */
    address public implementation;

    /**
    * @notice Pending brains of treasury
    */
    address public pendingImplementation;
}

contract BBFundStorage is BBFundAdminStorage {
    // const
    uint256 public constant DAY = 86400;

    // flags
    bool public initialized;
    bool public publicAllowed;

    // price
    uint256 public proaPriceToSell;
    uint256 public proaPriceToBuy;

    mapping(address => uint256) public maxAmountToTrade;

    // core components
    address public strategist;

    address public proa;
    address public usdt;

    address public klayswapFactory;
}
