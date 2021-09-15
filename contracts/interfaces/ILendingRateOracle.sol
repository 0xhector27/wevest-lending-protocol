// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.6.0;

/**
* Interface for the Wevest borrow rate oracle. Provides the average market borrow rate to be used as a base for the stable borrow rate calculations
**/

interface ILendingRateOracle {
    /**
    @dev returns the market borrow rate in ray
    **/
    function getMarketBorrowRate(address _asset) external view returns (uint256);

    /**
    @dev sets the market borrow rate. Rate value must be in ray
    **/
    function setMarketBorrowRate(address _asset, uint256 _rate) external;
}
