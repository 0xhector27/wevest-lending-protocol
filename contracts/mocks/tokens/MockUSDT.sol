// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.6.0;

import "./MintableERC20.sol";

contract MockUSDT is MintableERC20 {
    constructor() public ERC20("USDT Coin", "USDT") {
        _setupDecimals(6);
    }
}