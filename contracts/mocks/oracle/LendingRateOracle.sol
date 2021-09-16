// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.6.0;

contract LendingRateOracle {

    mapping(address => uint256) borrowRates;
    mapping(address => uint256) liquidityRates;

    function getMarketLiquidityRate(address _asset) external view returns(uint256) {
        return liquidityRates[_asset];
    }

    function setMarketLiquidityRate(address _asset, uint256 _rate) external {
        liquidityRates[_asset] = _rate;
    }
}