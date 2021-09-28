// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

interface IYieldFarmingPool {
    function deposit(address vault, address asset, uint amount) external returns(uint256);

    function withdraw(address vault, uint256 maxShares) external returns(uint256);

    function balance(address vault) external returns(uint256);
}
