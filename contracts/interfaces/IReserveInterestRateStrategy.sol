// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

/**
 * @title IReserveInterestRateStrategyInterface interface
 * @dev Interface for the calculation of the interest rates
 */
interface IReserveInterestRateStrategy {

  function calculateInterestRates(
    uint256 availableLiquidity,
    uint256 totalDebt,
    uint256 reserveFactor
  )
    external
    view
    returns (uint256);

  function calculateInterestRates(
    address reserve,
    address wvToken,
    uint256 liquidityAdded,
    uint256 liquidityTaken,
    uint256 totalDebt,
    uint256 reserveFactor
  )
    external
    view
    returns (uint256 liquidityRate);
}
