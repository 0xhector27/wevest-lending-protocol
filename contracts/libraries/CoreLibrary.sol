// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "./WadRayMath.sol";

/**
* @title CoreLibrary library
* @notice Defines the data structures of the reserves and the user data
**/

library CoreLibrary {
    using SafeMath for uint256;
    using WadRayMath for uint256;

    enum LeverageRatioMode {
        ONE, 
        TWO, 
        THREE
    }

    uint256 internal constant SECONDS_PER_YEAR = 365 days;

    struct UserReserveData {
        //amount borrowed by the user.
        uint256 borrowBalance;
        //origination fee cumulated by the user
        uint256 originationFee;
        uint40 lastUpdateTimestamp;
        //defines if a specific deposit should or not be used as a collateral in borrows
        bool useAsCollateral;
    }

    struct ReserveData {
        //the liquidity index. Expressed in ray
        uint256 lastLiquidityCumulativeIndex;
        //the current supply rate. Expressed in ray
        uint256 currentLiquidityRate;
        //the total borrows of the reserve. Expressed in the currency decimals
        uint256 totalBorrows;
        //the ltv of the reserve. Expressed in percentage (0-100)
        uint256 baseLTVasCollateral;
        //the liquidation threshold of the reserve. Expressed in percentage (0-100)
        uint256 liquidationThreshold;
        //the liquidation bonus of the reserve. Expressed in percentage
        uint256 liquidationBonus;
        //the decimals of the reserve asset
        uint256 decimals;
        //address of the wvToken representing the asset
        address wvTokenAddress;
        // address of the interest rate strategy contract
        address interestRateStrategyAddress;

        uint40 lastUpdateTimestamp;
        // borrowingEnabled = true means users can borrow from this reserve
        bool borrowingEnabled;
        // usageAsCollateralEnabled = true means users can use this reserve as collateral
        bool usageAsCollateralEnabled;
        // isActive = true means the reserve has been activated and properly configured
        bool isActive;
        // isFreezed = true means the reserve only allows repays and redeems, but not deposits, new borrowings or rate swap
        bool isFreezed;
    }

    /**
    * @dev returns the ongoing normalized income for the reserve.
    * a value of 1e27 means there is no income. As time passes, the income is accrued.
    * A value of 2*1e27 means that the income of the reserve is double the initial amount.
    * @param _reserve the reserve object
    * @return the normalized income. expressed in ray
    **/
    function getNormalizedIncome(CoreLibrary.ReserveData storage _reserve)
        internal
        view
        returns (uint256)
    {
        uint256 cumulated = calculateLinearInterest(
            _reserve.currentLiquidityRate, _reserve.lastUpdateTimestamp
        ).rayMul(_reserve.lastLiquidityCumulativeIndex);

        return cumulated;
    }

    /**
    * @dev Updates the liquidity cumulative index Ci
    * @param _self the reserve object
    **/
    function updateCumulativeIndexes(ReserveData storage _self) internal {
        uint256 totalBorrows = _self.totalBorrows;

        if (totalBorrows > 0) {
            //only cumulating if there is any income being produced
            uint256 cumulatedLiquidityInterest = calculateLinearInterest(
                _self.currentLiquidityRate,
                _self.lastUpdateTimestamp
            );

            _self.lastLiquidityCumulativeIndex = cumulatedLiquidityInterest.rayMul(
                _self.lastLiquidityCumulativeIndex
            );
        }
    }

    /**
    * @dev initializes a reserve
    * @param _self the reserve object
    * @param _wvTokenAddress the address of the overlying atoken contract
    * @param _decimals the number of decimals of the underlying asset
    * @param _interestRateStrategyAddress the address of the interest rate strategy contract
    **/
    function init(
        ReserveData storage _self,
        address _wvTokenAddress,
        uint256 _decimals,
        address _interestRateStrategyAddress
    ) external {
        require(_self.wvTokenAddress == address(0), "Reserve has already been initialized");

        if (_self.lastLiquidityCumulativeIndex == 0) {
            //if the reserve has not been initialized yet
            _self.lastLiquidityCumulativeIndex = WadRayMath.ray();
        }

        _self.wvTokenAddress = _wvTokenAddress;
        _self.decimals = _decimals;
        _self.interestRateStrategyAddress = _interestRateStrategyAddress;
        _self.isActive = true;
        _self.isFreezed = false;
    }

    /**
    * @dev enables borrowing on a reserve
    * @param _self the reserve object
    **/
    function enableBorrowing(ReserveData storage _self) external {
        require(_self.borrowingEnabled == false, "Reserve is already enabled");
        _self.borrowingEnabled = true;
    }

    /**
    * @dev disables borrowing on a reserve
    * @param _self the reserve object
    **/
    function disableBorrowing(ReserveData storage _self) external {
        _self.borrowingEnabled = false;
    }

    /**
    * @dev enables a reserve to be used as collateral
    * @param _self the reserve object
    * @param _baseLTVasCollateral the loan to value of the asset when used as collateral
    * @param _liquidationThreshold the threshold at which loans using this asset as collateral will be considered undercollateralized
    * @param _liquidationBonus the bonus liquidators receive to liquidate this asset
    **/

    function enableAsCollateral(
        ReserveData storage _self,
        uint256 _baseLTVasCollateral,
        uint256 _liquidationThreshold,
        uint256 _liquidationBonus
    ) external {
        require(
            _self.usageAsCollateralEnabled == false,
            "Reserve is already enabled as collateral"
        );

        _self.usageAsCollateralEnabled = true;
        _self.baseLTVasCollateral = _baseLTVasCollateral;
        _self.liquidationThreshold = _liquidationThreshold;
        _self.liquidationBonus = _liquidationBonus;

        if (_self.lastLiquidityCumulativeIndex == 0)
            _self.lastLiquidityCumulativeIndex = WadRayMath.ray();

    }

    /**
    * @dev disables a reserve as collateral
    * @param _self the reserve object
    **/
    function disableAsCollateral(ReserveData storage _self) external {
        _self.usageAsCollateralEnabled = false;
    }

    /**
    * @dev increases the total borrows
    * @param _reserve the reserve object
    * @param _amount the amount to add to the total borrows
    **/
    function increaseTotalBorrows(ReserveData storage _reserve, uint256 _amount) internal {
        _reserve.totalBorrows = _reserve.totalBorrows.add(_amount);
    }

    /**
    * @dev decreases the total borrows
    * @param _reserve the reserve object
    * @param _amount the amount to substract to the total borrows
    **/
    function decreaseTotalBorrows(ReserveData storage _reserve, uint256 _amount) internal {
        require(
            _reserve.totalBorrows >= _amount,
            "The amount that is being subtracted from the total borrows is incorrect"
        );
        _reserve.totalBorrows = _reserve.totalBorrows.sub(_amount);
    }

    /**
    * @dev function to calculate the interest using a linear interest rate formula
    * @param _rate the interest rate, in ray
    * @param _lastUpdateTimestamp the timestamp of the last update of the interest
    * @return the interest rate linearly accumulated during the timeDelta, in ray
    **/

    function calculateLinearInterest(uint256 _rate, uint40 _lastUpdateTimestamp)
        internal
        view
        returns (uint256)
    {
        //solium-disable-next-line
        uint256 timeDifference = block.timestamp.sub(uint256(_lastUpdateTimestamp));

        uint256 timeDelta = timeDifference.wadToRay().rayDiv(SECONDS_PER_YEAR.wadToRay());

        return _rate.rayMul(timeDelta).add(WadRayMath.ray());
    }

    /**
    * @dev function to calculate the interest using a compounded interest rate formula
    * @param _rate the interest rate, in ray
    * @param _lastUpdateTimestamp the timestamp of the last update of the interest
    * @return the interest rate compounded during the timeDelta, in ray
    **/
    function calculateCompoundedInterest(uint256 _rate, uint40 _lastUpdateTimestamp)
        internal
        view
        returns (uint256)
    {
        //solium-disable-next-line
        uint256 timeDifference = block.timestamp.sub(uint256(_lastUpdateTimestamp));

        uint256 ratePerSecond = _rate.div(SECONDS_PER_YEAR);

        return ratePerSecond.add(WadRayMath.ray()).rayPow(timeDifference);
    }

    /**
    * @dev returns the total borrows on the reserve
    * @param _reserve the reserve object
    * @return the total borrows
    **/
    function getTotalBorrows(CoreLibrary.ReserveData storage _reserve)
        internal
        view
        returns (uint256)
    {
        return _reserve.totalBorrows;
    }
}
