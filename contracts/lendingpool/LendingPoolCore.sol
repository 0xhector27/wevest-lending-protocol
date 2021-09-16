// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "../libraries/openzeppelin-upgradeability/VersionedInitializable.sol";
import "../libraries/CoreLibrary.sol";
import "../configuration/LendingPoolAddressesProvider.sol";
import "../interfaces/IReserveInterestRateStrategy.sol";
import "../libraries/WadRayMath.sol";
import "../tokenization/WvToken.sol";
import "../libraries/EthAddressLib.sol";

/**
* @title LendingPoolCore contract
* @notice Holds the state of the lending pool and all the funds deposited
* @dev NOTE: The core does not enforce security checks on the update of the state
* (eg, updateStateOnBorrow() does not enforce that borrowed is enabled on the reserve).
* The check that an action can be performed is a duty of the overlying LendingPool contract.
**/

contract LendingPoolCore is VersionedInitializable {
    using SafeMath for uint256;
    using WadRayMath for uint256;
    using CoreLibrary for CoreLibrary.ReserveData;
    using CoreLibrary for CoreLibrary.UserReserveData;
    using SafeERC20 for ERC20;
    using Address for address payable;

    /**
    * @dev Emitted when the state of a reserve is updated
    * @param reserve the address of the reserve
    * @param liquidityRate the new liquidity rate
    * @param liquidityIndex the new liquidity index
    **/
    event ReserveUpdated(
        address indexed reserve,
        uint256 liquidityRate,
        uint256 liquidityIndex
    );

    address public lendingPoolAddress;

    LendingPoolAddressesProvider public addressesProvider;

    /**
    * @dev only lending pools can use functions affected by this modifier
    **/
    modifier onlyLendingPool {
        require(lendingPoolAddress == msg.sender, "The caller must be a lending pool contract");
        _;
    }

    /**
    * @dev only lending pools configurator can use functions affected by this modifier
    **/
    modifier onlyLendingPoolConfigurator {
        require(
            addressesProvider.getLendingPoolConfigurator() == msg.sender,
            "The caller must be a lending pool configurator contract"
        );
        _;
    }

    mapping(address => CoreLibrary.ReserveData) internal reserves;
    mapping(address => mapping(address => CoreLibrary.UserReserveData)) internal usersReserveData;

    address[] public reservesList;

    uint256 public constant CORE_REVISION = 0x6;

    /**
    * @dev returns the revision number of the contract
    **/
    function getRevision() internal pure virtual override returns (uint256) {
        return CORE_REVISION;
    }

    /**
    * @dev initializes the Core contract, invoked upon registration on the AddressesProvider
    * @param _addressesProvider the addressesProvider contract
    **/

    function initialize(LendingPoolAddressesProvider _addressesProvider) 
        public virtual initializer 
    {
        addressesProvider = _addressesProvider;
        refreshConfigInternal();
    }

    /**
    * @dev updates the state of the core as a result of a deposit action
    * @param _reserve the address of the reserve in which the deposit is happening
    * @param _user the address of the the user depositing
    * @param _amount the amount being deposited
    * @param _isFirstDeposit true if the user is depositing for the first time
    **/

    function updateStateOnDeposit(
        address _reserve,
        address _user,
        uint256 _amount,
        bool _isFirstDeposit
    ) external onlyLendingPool {
        reserves[_reserve].updateCumulativeIndexes();
        updateReserveInterestRatesAndTimestampInternal(_reserve, _amount, 0);

        if (_isFirstDeposit) {
            //if this is the first deposit of the user, we configure the deposit as enabled to be used as collateral
            setUserUseReserveAsCollateral(_reserve, _user, true);
        }
    }

    /**
    * @dev updates the state of the core as a result of a redeem action
    * @param _reserve the address of the reserve in which the redeem is happening
    * @param _user the address of the the user redeeming
    * @param _amountRedeemed the amount being redeemed
    **/
    function updateStateOnWithdraw(
        address _reserve,
        address _user,
        uint256 _amountRedeemed
    ) external onlyLendingPool {
        //compound liquidity and variable borrow interests
        reserves[_reserve].updateCumulativeIndexes();
        updateReserveInterestRatesAndTimestampInternal(_reserve, 0, _amountRedeemed);

        //if user redeemed everything the useReserveAsCollateral flag is reset
        /* if (_userRedeemedEverything) {
            setUserUseReserveAsCollateral(_reserve, _user, false);
        } */
    }

    /**
    * @dev updates the state of the core as a consequence of a borrow action.
    * @param _reserve the address of the reserve on which the user is borrowing
    * @param _user the address of the borrower
    * @param _amountBorrowed the new amount borrowed
    * @param _borrowFee the fee on the amount borrowed
    **/
    function updateStateOnBorrow(
        address _reserve,
        address _user,
        uint256 _amountBorrowed,
        uint256 _borrowFee
    ) external onlyLendingPool {
        // getting the previous borrow balance of the user
        uint256 principalBorrowBalance = getUserBorrowBalance(_reserve, _user);
        updateReserveStateOnBorrowInternal(
            _reserve,
            _user,
            principalBorrowBalance,
            _amountBorrowed
        );

        updateUserStateOnBorrowInternal(
            _reserve,
            _user,
            _amountBorrowed,
            _borrowFee
        );

        updateReserveInterestRatesAndTimestampInternal(_reserve, 0, _amountBorrowed);
    }

    /**
    * @dev updates the state of the core as a consequence of a repay action.
    * @param _reserve the address of the reserve on which the user is repaying
    * @param _user the address of the borrower
    * @param _paybackAmountMinusFees the amount being paid back minus fees
    * @param _originationFeeRepaid the fee on the amount that is being repaid
    **/

    function updateStateOnRepay(
        address _reserve,
        address _user,
        uint256 _paybackAmountMinusFees,
        uint256 _originationFeeRepaid
    ) external onlyLendingPool {
        updateReserveStateOnRepayInternal(
            _reserve,
            _paybackAmountMinusFees
        );
        updateUserStateOnRepayInternal(
            _reserve,
            _user,
            _paybackAmountMinusFees,
            _originationFeeRepaid
        );

        updateReserveInterestRatesAndTimestampInternal(
            _reserve, _paybackAmountMinusFees, 0
        );
    }

    /**
    * @dev updates the state of the core as a consequence of a liquidation action.
    * @param _principalReserve the address of the principal reserve that is being repaid
    * @param _collateralReserve the address of the collateral reserve that is being liquidated
    * @param _user the address of the borrower
    * @param _amountToLiquidate the amount being repaid by the liquidator
    * @param _collateralToLiquidate the amount of collateral being liquidated
    * @param _feeLiquidated the amount of origination fee being liquidated
    * @param _liquidatedCollateralForFee the amount of collateral equivalent to the origination fee + bonus
    * @param _liquidatorReceivesWvToken true if the liquidator will receive aTokens, false otherwise
    **/
    function updateStateOnLiquidation(
        address _principalReserve,
        address _collateralReserve,
        address _user,
        uint256 _amountToLiquidate,
        uint256 _collateralToLiquidate,
        uint256 _feeLiquidated,
        uint256 _liquidatedCollateralForFee,
        bool _liquidatorReceivesWvToken
    ) external onlyLendingPool {
        updatePrincipalReserveStateOnLiquidationInternal(
            _principalReserve,
            _user,
            _amountToLiquidate
        );

        updateCollateralReserveStateOnLiquidationInternal(
            _collateralReserve
        );

        updateUserStateOnLiquidationInternal(
            _principalReserve,
            _user,
            _amountToLiquidate,
            _feeLiquidated
        );

        updateReserveInterestRatesAndTimestampInternal(
            _principalReserve, _amountToLiquidate, 0
        );

        if (!_liquidatorReceivesWvToken) {
            updateReserveInterestRatesAndTimestampInternal(
                _collateralReserve,
                0,
                _collateralToLiquidate.add(_liquidatedCollateralForFee)
            );
        }
    }

    /**
    * @dev enables or disables a reserve as collateral
    * @param _reserve the address of the principal reserve where the user deposited
    * @param _user the address of the depositor
    * @param _useAsCollateral true if the depositor wants to use the reserve as collateral
    **/
    function setUserUseReserveAsCollateral(address _reserve, address _user, bool _useAsCollateral)
        public
        onlyLendingPool
    {
        CoreLibrary.UserReserveData storage user = usersReserveData[_user][_reserve];
        user.useAsCollateral = _useAsCollateral;
    }

    /**
    * @notice ETH/token transfer functions
    **/

    /**
    * @dev fallback function enforces that the caller is a contract, to support flashloan transfers
    **/
    fallback() external payable {
        //only contracts can send ETH to the core
        require(
            msg.sender.isContract(), 
            "Only contracts can send ether to the Lending pool core"
        );
    }

    /**
    * @dev transfers to the user a specific amount from the reserve.
    * @param _reserve the address of the reserve where the transfer is happening
    * @param _user the address of the user receiving the transfer
    * @param _amount the amount being transferred
    **/
    function transferToUser(address _reserve, address payable _user, uint256 _amount)
        external
        onlyLendingPool
    {
        if (_reserve != EthAddressLib.ethAddress()) {
            ERC20(_reserve).safeTransfer(_user, _amount);
        } else {
            //solium-disable-next-line
            (bool result, ) = _user.call{value: _amount, gas: 50000}("");
            require(result, "Transfer of ETH failed");
        }
    }

    /**
    * @dev transfers the protocol fees to the fees collection address
    * @param _token the address of the token being transferred
    * @param _user the address of the user from where the transfer is happening
    * @param _amount the amount being transferred
    * @param _destination the fee receiver address
    **/

    function transferToFeeCollectionAddress(
        address _token,
        address _user,
        uint256 _amount,
        address _destination
    ) external payable onlyLendingPool {
        address payable feeAddress = address(uint160(_destination)); //cast the address to payable

        if (_token != EthAddressLib.ethAddress()) {
            require(
                msg.value == 0,
                "User is sending ETH along with the ERC20 transfer. Check the value attribute of the transaction"
            );
            ERC20(_token).safeTransferFrom(_user, feeAddress, _amount);
        } else {
            require(msg.value >= _amount, "The amount and the value sent to deposit do not match");
            //solium-disable-next-line
            (bool result, ) = feeAddress.call{value: _amount, gas: 50000}("");
            require(result, "Transfer of ETH failed");
        }
    }

    /**
    * @dev transfers the fees to the fees collection address in the case of liquidation
    * @param _token the address of the token being transferred
    * @param _amount the amount being transferred
    * @param _destination the fee receiver address
    **/
    function liquidateFee(
        address _token,
        uint256 _amount,
        address _destination
    ) external payable onlyLendingPool {
        address payable feeAddress = address(uint160(_destination)); //cast the address to payable
        require(
            msg.value == 0,
            "Fee liquidation does not require any transfer of value"
        );

        if (_token != EthAddressLib.ethAddress()) {
            ERC20(_token).safeTransfer(feeAddress, _amount);
        } else {
            //solium-disable-next-line
            (bool result, ) = feeAddress.call{value: _amount, gas: 50000}("");
            require(result, "Transfer of ETH failed");
        }
    }

    /**
    * @dev transfers an amount from a user to the destination reserve
    * @param _reserve the address of the reserve where the amount is being transferred
    * @param _user the address of the user from where the transfer is happening
    * @param _amount the amount being transferred
    **/
    function transferToReserve(address _reserve, address payable _user, uint256 _amount)
        external
        payable
        onlyLendingPool
    {
        if (_reserve != EthAddressLib.ethAddress()) {
            require(msg.value == 0, "User is sending ETH along with the ERC20 transfer.");
            ERC20(_reserve).safeTransferFrom(_user, address(this), _amount);

        } else {
            require(msg.value >= _amount, "The amount and the value sent to deposit do not match");

            if (msg.value > _amount) {
                //send back excess ETH
                uint256 excessAmount = msg.value.sub(_amount);
                //solium-disable-next-line
                (bool result, ) = _user.call{value: excessAmount, gas: 50000}("");
                require(result, "Transfer of ETH failed");
            }
        }
    }

    /**
    * @notice data access functions
    **/

    /**
    * @dev returns the basic data (balances, fee accrued, reserve enabled/disabled as collateral)
    * needed to calculate the global account data in the LendingPoolDataProvider
    * @param _reserve the address of the reserve
    * @param _user the address of the user
    * @return the user deposited balance, the principal borrow balance, the fee, and if the reserve is enabled as collateral or not
    **/
    function getUserBasicReserveData(address _reserve, address _user)
        external
        view
        returns (uint256, uint256, uint256, bool)
    {
        CoreLibrary.UserReserveData storage user = usersReserveData[_user][_reserve];

        uint256 underlyingBalance = getUserUnderlyingAssetBalance(_reserve, _user);

        if (user.borrowBalance == 0) {
            return (underlyingBalance, 0, 0, user.useAsCollateral);
        }

        return (
            underlyingBalance,
            user.borrowBalance,
            user.originationFee,
            user.useAsCollateral
        );
    }

    /**
    * @dev gets the underlying asset balance of a user based on the corresponding wvToken balance.
    * @param _reserve the reserve address
    * @param _user the user address
    * @return the underlying deposit balance of the user
    **/

    function getUserUnderlyingAssetBalance(address _reserve, address _user)
        public
        view
        returns (uint256)
    {
        WvToken wvToken = WvToken(reserves[_reserve].wvTokenAddress);
        return wvToken.balanceOf(_user);

    }

    /**
    * @dev gets the interest rate strategy contract address for the reserve
    * @param _reserve the reserve address
    * @return the address of the interest rate strategy contract
    **/
    function getReserveInterestRateStrategyAddress(address _reserve) public view returns (address) {
        CoreLibrary.ReserveData storage reserve = reserves[_reserve];
        return reserve.interestRateStrategyAddress;
    }

    /**
    * @dev gets the wvToken contract address for the reserve
    * @param _reserve the reserve address
    * @return the address of the wvToken contract
    **/

    function getReserveWvTokenAddress(address _reserve) public view returns (address) {
        CoreLibrary.ReserveData storage reserve = reserves[_reserve];
        return reserve.wvTokenAddress;
    }

    /**
    * @dev gets the available liquidity in the reserve. The available liquidity is the balance of the core contract
    * @param _reserve the reserve address
    * @return the available liquidity
    **/
    function getReserveAvailableLiquidity(address _reserve) public view returns (uint256) {
        uint256 balance = 0;

        if (_reserve == EthAddressLib.ethAddress()) {
            balance = address(this).balance;
        } else {
            balance = IERC20(_reserve).balanceOf(address(this));
        }
        return balance;
    }

    /**
    * @dev gets the total liquidity in the reserve. The total liquidity is the balance of the core contract + total borrows
    * @param _reserve the reserve address
    * @return the total liquidity
    **/
    function getReserveTotalLiquidity(address _reserve) public view returns (uint256) {
        CoreLibrary.ReserveData storage reserve = reserves[_reserve];
        return getReserveAvailableLiquidity(_reserve).add(reserve.getTotalBorrows());
    }

    /**
    * @dev gets the normalized income of the reserve. a value of 1e27 means there is no income. A value of 2e27 means there
    * there has been 100% income.
    * @param _reserve the reserve address
    * @return the reserve normalized income
    **/
    function getReserveNormalizedIncome(address _reserve) external view returns (uint256) {
        CoreLibrary.ReserveData storage reserve = reserves[_reserve];
        return reserve.getNormalizedIncome();
    }

    /**
    * @dev gets the reserve total borrows
    * @param _reserve the reserve address
    * @return the total borrows (stable + variable)
    **/
    function getReserveTotalBorrows(address _reserve) public view returns (uint256) {
        return reserves[_reserve].getTotalBorrows();
    }

    /**
    * @dev gets the reserve liquidation threshold
    * @param _reserve the reserve address
    * @return the reserve liquidation threshold
    **/

    function getReserveLiquidationThreshold(address _reserve) external view returns (uint256) {
        CoreLibrary.ReserveData storage reserve = reserves[_reserve];
        return reserve.liquidationThreshold;
    }

    /**
    * @dev gets the reserve liquidation bonus
    * @param _reserve the reserve address
    * @return the reserve liquidation bonus
    **/

    function getReserveLiquidationBonus(address _reserve) external view returns (uint256) {
        CoreLibrary.ReserveData storage reserve = reserves[_reserve];
        return reserve.liquidationBonus;
    }

    /**
    * @dev gets the reserve liquidity rate
    * @param _reserve the reserve address
    * @return the reserve liquidity rate
    **/
    function getReserveCurrentLiquidityRate(address _reserve) external view returns (uint256) {
        CoreLibrary.ReserveData storage reserve = reserves[_reserve];
        return reserve.currentLiquidityRate;
    }

    /**
    * @dev gets the reserve liquidity cumulative index
    * @param _reserve the reserve address
    * @return the reserve liquidity cumulative index
    **/
    function getReserveLiquidityCumulativeIndex(address _reserve) external view returns (uint256) {
        CoreLibrary.ReserveData storage reserve = reserves[_reserve];
        return reserve.lastLiquidityCumulativeIndex;
    }

    /**
    * @dev this function aggregates the configuration parameters of the reserve.
    * It's used in the LendingPoolDataProvider specifically to save gas, and avoid
    * multiple external contract calls to fetch the same data.
    * @param _reserve the reserve address
    * @return the reserve decimals
    * @return the base ltv as collateral
    * @return the liquidation threshold
    * @return if the reserve is used as collateral or not
    **/
    function getReserveConfiguration(address _reserve)
        external
        view
        returns (uint256, uint256, uint256, bool)
    {
        uint256 decimals;
        uint256 baseLTVasCollateral;
        uint256 liquidationThreshold;
        bool usageAsCollateralEnabled;

        CoreLibrary.ReserveData storage reserve = reserves[_reserve];
        decimals = reserve.decimals;
        baseLTVasCollateral = reserve.baseLTVasCollateral;
        liquidationThreshold = reserve.liquidationThreshold;
        usageAsCollateralEnabled = reserve.usageAsCollateralEnabled;

        return (decimals, baseLTVasCollateral, liquidationThreshold, usageAsCollateralEnabled);
    }

    /**
    * @dev returns the decimals of the reserve
    * @param _reserve the reserve address
    * @return the reserve decimals
    **/
    function getReserveDecimals(address _reserve) external view returns (uint256) {
        return reserves[_reserve].decimals;
    }

    /**
    * @dev returns true if the reserve is enabled for borrowing
    * @param _reserve the reserve address
    * @return true if the reserve is enabled for borrowing, false otherwise
    **/

    function isReserveBorrowingEnabled(address _reserve) external view returns (bool) {
        CoreLibrary.ReserveData storage reserve = reserves[_reserve];
        return reserve.borrowingEnabled;
    }

    /**
    * @dev returns true if the reserve is enabled as collateral
    * @param _reserve the reserve address
    * @return true if the reserve is enabled as collateral, false otherwise
    **/

    function isReserveUsageAsCollateralEnabled(address _reserve) external view returns (bool) {
        CoreLibrary.ReserveData storage reserve = reserves[_reserve];
        return reserve.usageAsCollateralEnabled;
    }

    /**
    * @dev returns true if the reserve is active
    * @param _reserve the reserve address
    * @return true if the reserve is active, false otherwise
    **/
    function getReserveIsActive(address _reserve) external view returns (bool) {
        CoreLibrary.ReserveData storage reserve = reserves[_reserve];
        return reserve.isActive;
    }

    /**
    * @notice returns if a reserve is freezed
    * @param _reserve the reserve for which the information is needed
    * @return true if the reserve is freezed, false otherwise
    **/

    function getReserveIsFreezed(address _reserve) external view returns (bool) {
        CoreLibrary.ReserveData storage reserve = reserves[_reserve];
        return reserve.isFreezed;
    }

    /**
    * @notice returns the timestamp of the last action on the reserve
    * @param _reserve the reserve for which the information is needed
    * return the last updated timestamp of the reserve
    **/

    function getReserveLastUpdate(address _reserve) external view returns (uint40 timestamp) {
        CoreLibrary.ReserveData storage reserve = reserves[_reserve];
        timestamp = reserve.lastUpdateTimestamp;
    }

    /**
    * @dev returns the utilization rate U of a specific reserve
    * @param _reserve the reserve for which the information is needed
    * @return the utilization rate in ray
    **/

    function getReserveUtilizationRate(address _reserve) public view returns (uint256) {
        CoreLibrary.ReserveData storage reserve = reserves[_reserve];

        uint256 totalBorrows = reserve.getTotalBorrows();

        if (totalBorrows == 0) {
            return 0;
        }

        uint256 availableLiquidity = getReserveAvailableLiquidity(_reserve);

        return totalBorrows.rayDiv(availableLiquidity.add(totalBorrows));
    }

    /**
    * @return the array of reserves configured on the core
    **/
    function getReserves() external view returns (address[] memory) {
        return reservesList;
    }

    /**
    * @param _reserve the address of the reserve for which the information is needed
    * @param _user the address of the user for which the information is needed
    * @return true if the user has chosen to use the reserve as collateral, false otherwise
    **/
    function isUserUseReserveAsCollateralEnabled(address _reserve, address _user)
        external
        view
        returns (bool)
    {
        CoreLibrary.UserReserveData storage user = usersReserveData[_user][_reserve];
        return user.useAsCollateral;
    }

    /**
    * @param _reserve the address of the reserve for which the information is needed
    * @param _user the address of the user for which the information is needed
    * @return the origination fee for the user
    **/
    function getUserOriginationFee(address _reserve, address _user)
        external
        view
        returns (uint256)
    {
        CoreLibrary.UserReserveData storage user = usersReserveData[_user][_reserve];
        return user.originationFee;
    }

    /**
    * @dev calculates and returns the borrow balances of the user
    * @param _reserve the address of the reserve
    * @param _user the address of the user
    * @return the principal borrow balance, the compounded balance and the balance increase since the last borrow/repay/swap/rebalance
    **/

    function getUserBorrowBalance(address _reserve, address _user)
        public
        view
        returns (uint256)
    {
        CoreLibrary.UserReserveData storage user = usersReserveData[_user][_reserve];
        return user.borrowBalance;
    }

    /**
    * @dev the variable borrow index of the user is 0 if the user is not borrowing or borrowing at stable
    * @param _reserve the address of the reserve for which the information is needed
    * @param _user the address of the user for which the information is needed
    * return the variable borrow index for the user
    **/

    function getUserLastUpdate(address _reserve, address _user)
        external
        view
        returns (uint256 timestamp)
    {
        CoreLibrary.UserReserveData storage user = usersReserveData[_user][_reserve];
        timestamp = user.lastUpdateTimestamp;
    }

    /**
    * @dev updates the lending pool core configuration
    **/
    function refreshConfiguration() external onlyLendingPoolConfigurator {
        refreshConfigInternal();
    }

    /**
    * @dev initializes a reserve
    * @param _reserve the address of the reserve
    * @param _wvTokenAddress the address of the overlying wvToken contract
    * @param _decimals the decimals of the reserve currency
    * @param _interestRateStrategyAddress the address of the interest rate strategy contract
    **/
    function initReserve(
        address _reserve,
        address _wvTokenAddress,
        uint256 _decimals,
        address _interestRateStrategyAddress
    ) external onlyLendingPoolConfigurator {
        reserves[_reserve].init(_wvTokenAddress, _decimals, _interestRateStrategyAddress);
        addReserveToListInternal(_reserve);

    }

    /**
    * @dev removes the last added reserve in the reservesList array
    * @param _reserveToRemove the address of the reserve
    **/
    function removeLastAddedReserve(address _reserveToRemove)
     external onlyLendingPoolConfigurator {

        address lastReserve = reservesList[reservesList.length-1];

        require(lastReserve == _reserveToRemove, "Reserve being removed is different than the reserve requested");

        //as we can't check if totalLiquidity is 0 (since the reserve added might not be an ERC20) we at least check that there is nothing borrowed
        require(getReserveTotalBorrows(lastReserve) == 0, "Cannot remove a reserve with liquidity deposited");

        reserves[lastReserve].isActive = false;
        reserves[lastReserve].wvTokenAddress = address(0);
        reserves[lastReserve].decimals = 0;
        reserves[lastReserve].lastLiquidityCumulativeIndex = 0;
        reserves[lastReserve].borrowingEnabled = false;
        reserves[lastReserve].usageAsCollateralEnabled = false;
        reserves[lastReserve].baseLTVasCollateral = 0;
        reserves[lastReserve].liquidationThreshold = 0;
        reserves[lastReserve].liquidationBonus = 0;
        reserves[lastReserve].interestRateStrategyAddress = address(0);

        reservesList.pop();
    }

    /**
    * @dev updates the address of the interest rate strategy contract
    * @param _reserve the address of the reserve
    * @param _rateStrategyAddress the address of the interest rate strategy contract
    **/

    function setReserveInterestRateStrategyAddress(address _reserve, address _rateStrategyAddress)
        external
        onlyLendingPoolConfigurator
    {
        reserves[_reserve].interestRateStrategyAddress = _rateStrategyAddress;
    }

    /**
    * @dev enables borrowing on a reserve. Also sets the stable rate borrowing
    * @param _reserve the address of the reserve
    **/

    function enableBorrowingOnReserve(address _reserve)
        external
        onlyLendingPoolConfigurator
    {
        reserves[_reserve].enableBorrowing();
    }

    /**
    * @dev disables borrowing on a reserve
    * @param _reserve the address of the reserve
    **/

    function disableBorrowingOnReserve(address _reserve) external onlyLendingPoolConfigurator {
        reserves[_reserve].disableBorrowing();
    }

    /**
    * @dev enables a reserve to be used as collateral
    * @param _reserve the address of the reserve
    **/
    function enableReserveAsCollateral(
        address _reserve,
        uint256 _baseLTVasCollateral,
        uint256 _liquidationThreshold,
        uint256 _liquidationBonus
    ) external onlyLendingPoolConfigurator {
        reserves[_reserve].enableAsCollateral(
            _baseLTVasCollateral,
            _liquidationThreshold,
            _liquidationBonus
        );
    }

    /**
    * @dev disables a reserve to be used as collateral
    * @param _reserve the address of the reserve
    **/
    function disableReserveAsCollateral(address _reserve) external onlyLendingPoolConfigurator {
        reserves[_reserve].disableAsCollateral();
    }

    /**
    * @dev activates a reserve
    * @param _reserve the address of the reserve
    **/
    function activateReserve(address _reserve) external onlyLendingPoolConfigurator {
        CoreLibrary.ReserveData storage reserve = reserves[_reserve];

        require(
            reserve.lastLiquidityCumulativeIndex > 0,
            "Reserve has not been initialized yet"
        );
        reserve.isActive = true;
    }

    /**
    * @dev deactivates a reserve
    * @param _reserve the address of the reserve
    **/
    function deactivateReserve(address _reserve) external onlyLendingPoolConfigurator {
        CoreLibrary.ReserveData storage reserve = reserves[_reserve];
        reserve.isActive = false;
    }

    /**
    * @notice allows the configurator to freeze the reserve.
    * A freezed reserve does not allow any action apart from repay, redeem, liquidationCall, rebalance.
    * @param _reserve the address of the reserve
    **/
    function freezeReserve(address _reserve) external onlyLendingPoolConfigurator {
        CoreLibrary.ReserveData storage reserve = reserves[_reserve];
        reserve.isFreezed = true;
    }

    /**
    * @notice allows the configurator to unfreeze the reserve. A unfreezed reserve allows any action to be executed.
    * @param _reserve the address of the reserve
    **/
    function unfreezeReserve(address _reserve) external onlyLendingPoolConfigurator {
        CoreLibrary.ReserveData storage reserve = reserves[_reserve];
        reserve.isFreezed = false;
    }

    /**
    * @notice allows the configurator to update the loan to value of a reserve
    * @param _reserve the address of the reserve
    * @param _ltv the new loan to value
    **/
    function setReserveBaseLTVasCollateral(address _reserve, uint256 _ltv)
        external
        onlyLendingPoolConfigurator
    {
        CoreLibrary.ReserveData storage reserve = reserves[_reserve];
        reserve.baseLTVasCollateral = _ltv;
    }

    /**
    * @notice allows the configurator to update the liquidation threshold of a reserve
    * @param _reserve the address of the reserve
    * @param _threshold the new liquidation threshold
    **/
    function setReserveLiquidationThreshold(address _reserve, uint256 _threshold)
        external
        onlyLendingPoolConfigurator
    {
        CoreLibrary.ReserveData storage reserve = reserves[_reserve];
        reserve.liquidationThreshold = _threshold;
    }

    /**
    * @notice allows the configurator to update the liquidation bonus of a reserve
    * @param _reserve the address of the reserve
    * @param _bonus the new liquidation bonus
    **/
    function setReserveLiquidationBonus(address _reserve, uint256 _bonus)
        external
        onlyLendingPoolConfigurator
    {
        CoreLibrary.ReserveData storage reserve = reserves[_reserve];
        reserve.liquidationBonus = _bonus;
    }

    /**
    * @notice allows the configurator to update the reserve decimals
    * @param _reserve the address of the reserve
    * @param _decimals the decimals of the reserve
    **/
    function setReserveDecimals(address _reserve, uint256 _decimals)
        external
        onlyLendingPoolConfigurator
    {
        CoreLibrary.ReserveData storage reserve = reserves[_reserve];
        reserve.decimals = _decimals;
    }

    /**
    * @notice internal functions
    **/

    /**
    * @dev updates the state of a reserve as a consequence of a borrow action.
    * @param _reserve the address of the reserve on which the user is borrowing
    * @param _user the address of the borrower
    * @param _principalBorrowBalance the previous borrow balance of the borrower before the action
    * @param _amountBorrowed the new amount borrowed
    **/

    function updateReserveStateOnBorrowInternal(
        address _reserve,
        address _user,
        uint256 _principalBorrowBalance,
        uint256 _amountBorrowed
    ) internal {
        reserves[_reserve].updateCumulativeIndexes();

        //increasing reserve total borrows to account for the new borrow balance of the user
        //NOTE: Depending on the previous borrow mode, the borrows might need to be switched from variable to stable or vice versa

        updateReserveTotalBorrows(
            _reserve,
            _user,
            _principalBorrowBalance,
            _amountBorrowed
        );
    }

    /**
    * @dev updates the state of a user as a consequence of a borrow action.
    * @param _reserve the address of the reserve on which the user is borrowing
    * @param _user the address of the borrower
    * @param _amountBorrowed the amount borrowed
    * return the final borrow rate for the user. Emitted by the borrow() event
    **/

    function updateUserStateOnBorrowInternal(
        address _reserve,
        address _user,
        uint256 _amountBorrowed,
        uint256 _fee
    ) internal {
        CoreLibrary.UserReserveData storage user = usersReserveData[_user][_reserve];

        //increase the principal borrows and the origination fee
        user.borrowBalance = user.borrowBalance.add(_amountBorrowed);
        user.originationFee = user.originationFee.add(_fee);

        //solium-disable-next-line
        user.lastUpdateTimestamp = uint40(block.timestamp);
    }

    /**
    * @dev updates the state of the reserve as a consequence of a repay action.
    * @param _reserve the address of the reserve on which the user is repaying
    * _user the address of the borrower
    * @param _paybackAmountMinusFees the amount being paid back minus fees
    **/

    function updateReserveStateOnRepayInternal(
        address _reserve,
        uint256 _paybackAmountMinusFees
    ) internal {
        CoreLibrary.ReserveData storage reserve = reserves[_reserve];

        //update the indexes
        reserves[_reserve].updateCumulativeIndexes();

        //subtract the payback amount
        reserve.decreaseTotalBorrows(_paybackAmountMinusFees);
    }

    /**
    * @dev updates the state of the user as a consequence of a repay action.
    * @param _reserve the address of the reserve on which the user is repaying
    * @param _user the address of the borrower
    * @param _paybackAmountMinusFees the amount being paid back minus fees
    * @param _originationFeeRepaid the fee on the amount that is being repaid
    **/
    function updateUserStateOnRepayInternal(
        address _reserve,
        address _user,
        uint256 _paybackAmountMinusFees,
        uint256 _originationFeeRepaid
    ) internal {
        CoreLibrary.UserReserveData storage user = usersReserveData[_user][_reserve];

        //update the user borrow balance, subtracting the payback amount
        user.borrowBalance = user.borrowBalance.sub(_paybackAmountMinusFees);

        user.originationFee = user.originationFee.sub(_originationFeeRepaid);

        //solium-disable-next-line
        user.lastUpdateTimestamp = uint40(block.timestamp);
    }

    /**
    * @dev updates the state of the principal reserve as a consequence of a liquidation action.
    * @param _principalReserve the address of the principal reserve that is being repaid
    * @param _user the address of the borrower
    * @param _amountToLiquidate the amount being repaid by the liquidator
    **/

    function updatePrincipalReserveStateOnLiquidationInternal(
        address _principalReserve,
        address _user,
        uint256 _amountToLiquidate
    ) internal {
        CoreLibrary.ReserveData storage reserve = reserves[_principalReserve];
        // CoreLibrary.UserReserveData storage user = usersReserveData[_user][_principalReserve];

        //update principal reserve data
        reserve.updateCumulativeIndexes();
        
        reserve.decreaseTotalBorrows(_amountToLiquidate);
    }

    /**
    * @dev updates the state of the collateral reserve as a consequence of a liquidation action.
    * @param _collateralReserve the address of the collateral reserve that is being liquidated
    **/
    function updateCollateralReserveStateOnLiquidationInternal(
        address _collateralReserve
    ) internal {
        //update collateral reserve
        reserves[_collateralReserve].updateCumulativeIndexes();

    }

    /**
    * @dev updates the state of the user being liquidated as a consequence of a liquidation action.
    * @param _reserve the address of the principal reserve that is being repaid
    * @param _user the address of the borrower
    * @param _amountToLiquidate the amount being repaid by the liquidator
    * @param _feeLiquidated the amount of origination fee being liquidated
    **/
    function updateUserStateOnLiquidationInternal(
        address _reserve,
        address _user,
        uint256 _amountToLiquidate,
        uint256 _feeLiquidated
    ) internal {
        CoreLibrary.UserReserveData storage user = usersReserveData[_user][_reserve];
        //first increase by the compounded interest, then decrease by the liquidated amount
        user.borrowBalance = user.borrowBalance.sub(_amountToLiquidate);

        if(_feeLiquidated > 0){
            user.originationFee = user.originationFee.sub(_feeLiquidated);
        }

        //solium-disable-next-line
        user.lastUpdateTimestamp = uint40(block.timestamp);
    }

    /**
    * @dev updates the state of the user as a consequence of a stable rate rebalance
    * @param _reserve the address of the principal reserve where the user borrowed
    * @param _user the address of the borrower
    * @param _amountBorrowed the accrued interest on the borrowed amount
    **/
    function updateReserveTotalBorrows(
        address _reserve,
        address _user,
        uint256 _principalBalance,
        uint256 _amountBorrowed
    ) internal {
        CoreLibrary.ReserveData storage reserve = reserves[_reserve];

        uint256 newPrincipalAmount = _principalBalance.add(_amountBorrowed);

        reserve.increaseTotalBorrows(newPrincipalAmount);
    }

    /**
    * @dev Updates the reserve current stable borrow rate Rf, the current variable borrow rate Rv and the current liquidity rate Rl.
    * Also updates the lastUpdateTimestamp value. Please refer to the whitepaper for further information.
    * @param _reserve the address of the reserve to be updated
    * @param _liquidityAdded the amount of liquidity added to the protocol (deposit or repay) in the previous action
    * @param _liquidityTaken the amount of liquidity taken from the protocol (redeem or borrow)
    **/

    function updateReserveInterestRatesAndTimestampInternal(
        address _reserve,
        uint256 _liquidityAdded,
        uint256 _liquidityTaken
    ) internal virtual {
        CoreLibrary.ReserveData storage reserve = reserves[_reserve];
        uint256 newLiquidityRate = IReserveInterestRateStrategy(
            reserve.interestRateStrategyAddress
        ).calculateInterestRates(
            _reserve,
            getReserveAvailableLiquidity(_reserve).add(_liquidityAdded).sub(_liquidityTaken),
            reserve.totalBorrows
        );

        reserve.currentLiquidityRate = newLiquidityRate;

        //solium-disable-next-line
        reserve.lastUpdateTimestamp = uint40(block.timestamp);

        emit ReserveUpdated(
            _reserve,
            newLiquidityRate,
            reserve.lastLiquidityCumulativeIndex
        );
    }

    /**
    * @dev transfers to the protocol fees of a flashloan to the fees collection address
    * @param _token the address of the token being transferred
    * @param _amount the amount being transferred
    **/

    function transferFlashLoanProtocolFeeInternal(address _token, uint256 _amount) internal {
        address payable receiver = address(uint160(addressesProvider.getTokenDistributor()));

        if (_token != EthAddressLib.ethAddress()) {
            ERC20(_token).safeTransfer(receiver, _amount);
        } else {
            //solium-disable-next-line
            (bool result, ) = receiver.call{value: _amount}("");
            require(result, "Transfer to token distributor failed");
        }
    }

    /**
    * @dev updates the internal configuration of the core
    **/
    function refreshConfigInternal() internal {
        lendingPoolAddress = addressesProvider.getLendingPool();
    }

    /**
    * @dev adds a reserve to the array of the reserves address
    **/
    function addReserveToListInternal(address _reserve) internal {
        bool reserveAlreadyAdded = false;
        for (uint256 i = 0; i < reservesList.length; i++)
            if (reservesList[i] == _reserve) {
                reserveAlreadyAdded = true;
            }
        if (!reserveAlreadyAdded) reservesList.push(_reserve);
    }

}
