// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

import {SafeMath} from '../../dependencies/openzeppelin/contracts/SafeMath.sol';
import {IReserveInterestRateStrategy} from '../../interfaces/IReserveInterestRateStrategy.sol';
import {WadRayMath} from '../libraries/math/WadRayMath.sol';
import {PercentageMath} from '../libraries/math/PercentageMath.sol';
import {ILendingPoolAddressesProvider} from '../../interfaces/ILendingPoolAddressesProvider.sol';
import {IERC20} from '../../dependencies/openzeppelin/contracts/IERC20.sol';

/**
 * @title DefaultReserveInterestRateStrategy contract
 * @notice Implements the calculation of the interest rates depending on the reserve state
 * @dev An instance of this same contract, can't be used across different Wevest markets, due to the caching
 *   of the LendingPoolAddressesProvider
 * @author Wevest
 **/
contract DefaultReserveInterestRateStrategy is IReserveInterestRateStrategy {
  using WadRayMath for uint256;
  using SafeMath for uint256;
  using PercentageMath for uint256;

  /**
   * @dev this constant represents the utilization rate at which the pool aims to obtain most competitive borrow rates.
   * Expressed in ray
   **/
  // uint256 public immutable OPTIMAL_UTILIZATION_RATE;

  /**
   * @dev This constant represents the excess utilization rate above the optimal. It's always equal to
   * 1-optimal utilization rate. Added as a constant here for gas optimizations.
   * Expressed in ray
   **/

  // uint256 public immutable EXCESS_UTILIZATION_RATE;

  ILendingPoolAddressesProvider public immutable addressesProvider;

  constructor(
    ILendingPoolAddressesProvider provider
  ) public {
    // OPTIMAL_UTILIZATION_RATE = optimalUtilizationRate;
    // EXCESS_UTILIZATION_RATE = WadRayMath.ray().sub(optimalUtilizationRate);
    addressesProvider = provider;
  }

  /**
   * @dev Calculates the interest rates depending on the reserve's state and configurations
   * @param reserve The address of the reserve
   * @param liquidityAdded The liquidity added during the operation
   * @param liquidityTaken The liquidity taken during the operation
   * @param totalDebt The total borrowed from the reserve a stable rate
   * @param reserveFactor The reserve portion of the interest that goes to the treasury of the market
   * @return The liquidity rate
   **/
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
    override
    returns (uint256)
  {
    uint256 availableLiquidity = IERC20(reserve).balanceOf(wvToken);
    //avoid stack too deep
    availableLiquidity = availableLiquidity.add(liquidityAdded).sub(liquidityTaken);

    return
      calculateInterestRates(
        availableLiquidity,
        totalDebt,
        reserveFactor
      );
  }

  struct CalcInterestRatesLocalVars {
    uint256 totalDebt;
    uint256 currentLiquidityRate;
    uint256 utilizationRate;
  }

  /**
   * @dev Calculates the interest rates depending on the reserve's state and configurations.
   * NOTE This function is kept for compatibility with the previous DefaultInterestRateStrategy interface.
   * New protocol implementation uses the new calculateInterestRates() interface
   * @param availableLiquidity The liquidity available in the corresponding aToken
   * @param totalDebt The total borrowed from the reserve a stable rate
   * @param reserveFactor The reserve portion of the interest that goes to the treasury of the market
   * @return The liquidity rate
   **/
  
  function calculateInterestRates(
    uint256 availableLiquidity,
    uint256 totalDebt,
    uint256 reserveFactor
  )
    public
    view
    override
    returns (uint256)
  {
    CalcInterestRatesLocalVars memory vars;

    vars.totalDebt = totalDebt;
    vars.currentLiquidityRate = 0;

    vars.utilizationRate = vars.totalDebt == 0
      ? 0
      : vars.totalDebt.rayDiv(availableLiquidity.add(vars.totalDebt));

    vars.currentLiquidityRate = vars.utilizationRate
      .percentMul(PercentageMath.PERCENTAGE_FACTOR.sub(reserveFactor));

    return vars.currentLiquidityRate;
  }
}
