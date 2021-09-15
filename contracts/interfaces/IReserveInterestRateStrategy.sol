// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.6.0;

/**
@notice Interface for the calculation of the interest rates.
*/

interface IReserveInterestRateStrategy {

    /**
    * @dev returns the base variable borrow rate, in rays
    */

    function getBaseVariableBorrowRate() external view returns (uint256);
    /**
    * @dev calculates the liquidity, stable, and variable rates depending on the current utilization rate
    *      and the base parameters
    *
    */
    function calculateInterestRates(
        address _reserve,
        uint256 _utilizationRate,
        uint256 _totalBorrows
    )
    external
    view
    returns (uint256);
}
