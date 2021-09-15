// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.6.0;

import "./MintableERC20.sol";

contract MockMANA is MintableERC20 {
    constructor() public ERC20("Decentraland", "MANA") {}
}