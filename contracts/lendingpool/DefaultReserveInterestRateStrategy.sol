// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.6.0;

import "../interfaces/IReserveInterestRateStrategy.sol";
import "../libraries/WadRayMath.sol";
import "../configuration/LendingPoolAddressesProvider.sol";
import "./LendingPoolCore.sol";

import "@openzeppelin/contracts/math/SafeMath.sol";

/**
* @title DefaultReserveInterestRateStrategy contract
* @notice implements the calculation of the interest rates depending on the reserve parameters.
* @dev if there is need to update the calculation of the interest rates for a specific reserve,
* a new version of this contract will be deployed.
**/

contract DefaultReserveInterestRateStrategy is IReserveInterestRateStrategy {
    using WadRayMath for uint256;
    using SafeMath for uint256;



   /**
    * @dev this constant represents the utilization rate at which the pool aims to obtain most competitive borrow rates
    * expressed in ray
    **/
    uint256 public constant OPTIMAL_UTILIZATION_RATE = 0.8 * 1e27;

   /**
    * @dev this constant represents the excess utilization rate above the optimal. It's always equal to
    * 1-optimal utilization rate. Added as a constant here for gas optimizations
    * expressed in ray
    **/

    uint256 public constant EXCESS_UTILIZATION_RATE = 0.2 * 1e27;

    LendingPoolAddressesProvider public addressesProvider;


    //base variable borrow rate when Utilization rate = 0. Expressed in ray
    uint256 public baseVariableBorrowRate;

    //slope of the variable interest curve when utilization rate > 0 and <= OPTIMAL_UTILIZATION_RATE. Expressed in ray
    uint256 public variableRateSlope1;

    //slope of the variable interest curve when utilization rate > OPTIMAL_UTILIZATION_RATE. Expressed in ray
    uint256 public variableRateSlope2;

    //slope of the stable interest curve when utilization rate > 0 and <= OPTIMAL_UTILIZATION_RATE. Expressed in ray
    uint256 public stableRateSlope1;

    //slope of the stable interest curve when utilization rate > OPTIMAL_UTILIZATION_RATE. Expressed in ray
    uint256 public stableRateSlope2;
    address public reserve;

    constructor(
        address _reserve,
        LendingPoolAddressesProvider _provider,
        uint256 _baseVariableBorrowRate,
        uint256 _variableRateSlope1,
        uint256 _variableRateSlope2,
        uint256 _stableRateSlope1,
        uint256 _stableRateSlope2
    ) public {
        addressesProvider = _provider;
        baseVariableBorrowRate = _baseVariableBorrowRate;
        variableRateSlope1 = _variableRateSlope1;
        variableRateSlope2 = _variableRateSlope2;
        stableRateSlope1 = _stableRateSlope1;
        stableRateSlope2 = _stableRateSlope2;
        reserve = _reserve;
    }

    /**
    @dev accessors
     */

    function getBaseVariableBorrowRate() external view override returns (uint256) {
        return baseVariableBorrowRate;
    }

    function getVariableRateSlope1() external view returns (uint256) {
        return variableRateSlope1;
    }

    function getVariableRateSlope2() external view returns (uint256) {
        return variableRateSlope2;
    }

    function getStableRateSlope1() external view returns (uint256) {
        return stableRateSlope1;
    }

    function getStableRateSlope2() external view returns (uint256) {
        return stableRateSlope2;
    }

    /**
    * @dev calculates the interest rates depending on the available liquidity and the total borrowed.
    * @param _reserve the address of the reserve
    * @param _availableLiquidity the liquidity available in the reserve
    * @param _totalBorrows the total borrowed from the reserve
    * return the liquidity rate, stable borrow rate and variable borrow rate calculated from the input parameters
    **/
    function calculateInterestRates(
        address _reserve,
        uint256 _availableLiquidity,
        uint256 _totalBorrows
    ) 
        external
        view
        override
        returns (uint256)
    {
        uint256 totalBorrows = _totalBorrows;

        uint256 utilizationRate = (totalBorrows == 0 && _availableLiquidity == 0)
            ? 0
            : totalBorrows.rayDiv(_availableLiquidity.add(totalBorrows));

        return utilizationRate;
    }
}
