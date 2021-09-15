// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.6.0;

import "./MintableERC20.sol";

contract MockLINK is MintableERC20 {
    constructor() public ERC20("ChainLink", "LINK") {}
}