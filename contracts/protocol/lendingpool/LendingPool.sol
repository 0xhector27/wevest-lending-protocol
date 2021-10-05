// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {SafeMath} from '../../dependencies/openzeppelin/contracts/SafeMath.sol';
import {IERC20} from '../../dependencies/openzeppelin/contracts/IERC20.sol';
import {SafeERC20} from '../../dependencies/openzeppelin/contracts/SafeERC20.sol';
import {Address} from '../../dependencies/openzeppelin/contracts/Address.sol';
import {ILendingPoolAddressesProvider} from '../../interfaces/ILendingPoolAddressesProvider.sol';
import {IWvToken} from '../../interfaces/IWvToken.sol';
import {IDebtToken} from '../../interfaces/IDebtToken.sol';
import {IPriceOracleGetter} from '../../interfaces/IPriceOracleGetter.sol';
import {ILendingPool} from '../../interfaces/ILendingPool.sol';
import {IYieldFarmingPool} from '../../interfaces/IYieldFarmingPool.sol';
import {IVault} from '../../interfaces/IVault.sol';
import {VersionedInitializable} from '../libraries/wevest-upgradeability/VersionedInitializable.sol';
import {Helpers} from '../libraries/helpers/Helpers.sol';
import {Errors} from '../libraries/helpers/Errors.sol';
import {WadRayMath} from '../libraries/math/WadRayMath.sol';
import {PercentageMath} from '../libraries/math/PercentageMath.sol';
import {ReserveLogic} from '../libraries/logic/ReserveLogic.sol';
import {GenericLogic} from '../libraries/logic/GenericLogic.sol';
import {ValidationLogic} from '../libraries/logic/ValidationLogic.sol';
import {ReserveConfiguration} from '../libraries/configuration/ReserveConfiguration.sol';
import {UserConfiguration} from '../libraries/configuration/UserConfiguration.sol';
import {DataTypes} from '../libraries/types/DataTypes.sol';
import {LendingPoolStorage} from './LendingPoolStorage.sol';
import "hardhat/console.sol";

/**
 * @title LendingPool contract
 * @dev Main point of interaction with an Wevest protocol's market
 * - Users can:
 *   # Deposit
 *   # Withdraw
 *   # Borrow
 *   # Repay
 *   # Enable/disable their deposits as collateral rebalance stable rate borrow positions
 *   # Liquidate positions
 * - To be covered by a proxy contract, owned by the LendingPoolAddressesProvider of the specific market
 * - All admin functions are callable by the LendingPoolConfigurator contract defined also in the
 *   LendingPoolAddressesProvider
 * @author Wevest
 **/
contract LendingPool is VersionedInitializable, ILendingPool, LendingPoolStorage {
  using SafeMath for uint256;
  using WadRayMath for uint256;
  using PercentageMath for uint256;
  using SafeERC20 for IERC20;

  uint256 public constant LENDINGPOOL_REVISION = 0x2;

  modifier whenNotPaused() {
    require(!_paused, Errors.LP_IS_PAUSED);
    _;
  }

  modifier onlyLendingPoolConfigurator() {
    require(
      _addressesProvider.getLendingPoolConfigurator() == msg.sender,
      Errors.LP_CALLER_NOT_LENDING_POOL_CONFIGURATOR
    );
    _;
  }

  function getRevision() internal pure override returns (uint256) {
    return LENDINGPOOL_REVISION;
  }

  /**
   * @dev Function is invoked by the proxy contract when the LendingPool contract is added to the
   * LendingPoolAddressesProvider of the market.
   * - Caching the address of the LendingPoolAddressesProvider in order to reduce gas consumption
   *   on subsequent operations
   * @param provider The address of the LendingPoolAddressesProvider
   **/
  function initialize(ILendingPoolAddressesProvider provider) public initializer {
    _addressesProvider = provider;
    _maxNumberOfReserves = 128;
  }

  /**
   * @dev Deposits an `amount` of underlying asset into the reserve, receiving in return overlying wvTokens.
   * - E.g. User deposits 100 USDC and gets in return 100 wvUSDC
   * @param asset The address of the underlying asset to deposit
   * @param amount The amount to be deposited
   **/
  function deposit(
    address asset,
    uint256 amount
  ) public override whenNotPaused {
    DataTypes.ReserveData storage reserve = _reserves[asset];

    ValidationLogic.validateDeposit(reserve, amount);

    address wvToken = reserve.wvTokenAddress;

    IERC20(asset).safeTransferFrom(msg.sender, wvToken, amount);

    IWvToken(wvToken).mint(msg.sender, amount);

    emit Deposit(asset, msg.sender, amount);
  }

  /**
   * @dev Withdraws an `amount` of underlying asset from the reserve, burning the equivalent wvTokens owned
   * E.g. User has 100 wvUSDC, calls withdraw() and receives 100 USDC, burning the 100 wvUSDC
   * @param asset The address of the underlying asset to withdraw
   * @param amount The underlying amount to be withdrawn
   *   - Send the value type(uint256).max in order to withdraw the whole wvToken balance
   * // param to Address that will receive the underlying, same as msg.sender if the user
   *   wants to receive it on his own wallet, or a different address if the beneficiary is a
   *   different wallet
   * @return The final amount withdrawn
   **/
  function withdraw(
    address asset,
    uint256 amount
  ) external override whenNotPaused returns (uint256) {
    DataTypes.ReserveData storage reserve = _reserves[asset];

    address wvToken = reserve.wvTokenAddress;

    uint256 userBalance = IWvToken(wvToken).balanceOf(msg.sender);

    uint256 amountToWithdraw = amount;

    if (amount == type(uint256).max) {
      amountToWithdraw = userBalance;
    }
    
    ValidationLogic.validateWithdraw(
      asset,
      amountToWithdraw,
      userBalance,
      _reserves,
      _usersConfig[msg.sender],
      _reservesList,
      _reservesCount,
      _addressesProvider.getPriceOracle()
    );

    /* added by SC */
    address yfpool = _addressesProvider.getYieldFarmingPool();
    // calcuate interest for deposit
    require (reserve.vaultTokenAddress != address(0), "Unsupported assets for vaults");
    uint256 userInterest = IYieldFarmingPool(yfpool).lenderInterest(
      reserve.vaultTokenAddress, 
      asset,
      msg.sender,
      wvToken
    );
    console.log("userA interest %s", userInterest);
    // total withdraw = request withdraw + user interest
    amountToWithdraw += userInterest;
    console.log("total withdraw %s", amountToWithdraw);
    // check current lending pool balance
    uint256 lendingPoolBalance = IWvToken(wvToken).totalSupply();

    uint256 yfPoolBalance = IERC20(asset).balanceOf(yfpool);
    // if not enough balance, transfer required asset from yf pool
    uint256 extraAmount = 0;
    if (lendingPoolBalance < amountToWithdraw) {
      extraAmount = amountToWithdraw.sub(lendingPoolBalance);
      if (yfPoolBalance < extraAmount) {
        yfPoolBalance = IYieldFarmingPool(yfpool).withdraw(
          reserve.vaultTokenAddress, type(uint256).max, asset
        );
      }
      require(yfPoolBalance >= extraAmount, "Currently, YF pool doesnt have enough balance");
      IYieldFarmingPool(yfpool).transferUnderlying(asset, wvToken, extraAmount);
    }

    reserve.updateInterestRates(asset, wvToken, 0, amountToWithdraw);

    if (amountToWithdraw == userBalance) {
      _usersConfig[msg.sender].setUsingAsCollateral(reserve.id, false);
      emit ReserveUsedAsCollateralDisabled(asset, msg.sender);
    }
    // burns wvToken and transfer underlying asset to user wallet
    IWvToken(wvToken).burn(msg.sender, amountToWithdraw);

    emit Withdraw(asset, msg.sender, amountToWithdraw);

    return amountToWithdraw;
  }

  /**
   * @dev Allows users to borrow a specific `amount` of the reserve underlying asset, provided that the borrower
   * already deposited enough collateral, or he was given enough allowance by a credit delegator on the
   * corresponding debt token 
   * - E.g. User borrows 100 USDC and 100 debt tokens
   * @param assetToBorrow The address of the underlying asset to borrow
   * param amount The amount to be borrowed
   * @param leverageRatioMode
   **/

  /* function borrow(
    address asset,
    uint256 amount,
    uint256 interestRateMode,
    uint16 referralCode,
    address onBehalfOf
  ) external override whenNotPaused {
    DataTypes.ReserveData storage reserve = _reserves[asset];

    _executeBorrow(
      ExecuteBorrowParams(
        asset,
        msg.sender,
        onBehalfOf,
        amount,
        interestRateMode,
        reserve.wvTokenAddress,
        referralCode,
        true
      )
    );
  } */

  function borrow(
    address collateralAsset,
    uint256 collateralAmount,
    address assetToBorrow,
    uint256 leverageRatioMode
  ) external override whenNotPaused {
    DataTypes.ReserveData storage reserve = _reserves[assetToBorrow];

    _executeBorrow(
      ExecuteBorrowParams(
        collateralAsset,
        collateralAmount,
        assetToBorrow,
        msg.sender,
        leverageRatioMode,
        reserve.wvTokenAddress,
        true
      )
    );
  }

  function redeem(
    address assetBorrowed,
    address collateralAsset,
    uint256 amount
  ) external override whenNotPaused {
    DataTypes.ReserveData storage reserve = _reserves[assetBorrowed];
    DataTypes.ReserveData storage collateralReserve = _reserves[collateralAsset];
    uint256 userDebt = Helpers.getUserCurrentDebt(msg.sender, collateralReserve);
    console.log("userDebt %s", userDebt);

    ValidationLogic.validateRedeem(collateralReserve, amount, userDebt);

    address yfpool = _addressesProvider.getYieldFarmingPool();
    uint withdrawAmount = IYieldFarmingPool(yfpool).withdraw(
      reserve.vaultTokenAddress,
      IVault(reserve.vaultTokenAddress).balanceOf(yfpool),
      assetBorrowed
    );

    console.log("withdrawAmount %s", withdrawAmount);
    uint256 swappedAmount = IYieldFarmingPool(yfpool).swap(
      assetBorrowed,
      collateralAsset,
      withdrawAmount
    );
    console.log("swappedAmount %s", swappedAmount);
    console.log("redeemAmount %s", amount);
    if (swappedAmount >= amount) { // price up
      IYieldFarmingPool(yfpool).transferUnderlying(
        collateralAsset,
        collateralReserve.wvTokenAddress, 
        amount
      );

      // transfer the rest amount including interest to borrower account
      IYieldFarmingPool(yfpool).transferUnderlying(
        collateralAsset,
        msg.sender,
        swappedAmount - amount
      );
    } else { // price down
      IYieldFarmingPool(yfpool).transferUnderlying(
        collateralAsset,
        collateralReserve.wvTokenAddress, 
        swappedAmount
      );

      // get user collateral balance
      uint userCollateralBalance = 0;
      (userCollateralBalance, ) = 
        IWvToken(collateralReserve.wvTokenAddress).getUserBalanceAndSupply(msg.sender);
      // transfer borrower account
      uint receiveAmount = userCollateralBalance - (amount - swappedAmount);
      IWvToken(collateralReserve.wvTokenAddress).transferUnderlyingTo(
        msg.sender, 
        receiveAmount
      );
    }

    // burns the debt token
    IDebtToken(collateralReserve.debtTokenAddress).burn(msg.sender, amount);
  }

  /**
   * @notice Repays a borrowed `amount` on a specific reserve, burning the equivalent debt tokens owned
   * - E.g. User repays 100 USDC, burning 100 debt tokens
   * @param asset The address of the borrowed underlying asset previously borrowed
   * @param amount The amount to repay
   * - Send the value type(uint256).max in order to repay the whole debt for `asset` on the specific `debtMode`
   * // param rateMode The interest rate mode at of the debt the user wants to repay: 1 for Stable, 2 for Variable
   * // param onBehalfOf Address of the user who will get his debt reduced/removed. Should be the address of the
   * user calling the function if he wants to reduce/remove his own debt, or the address of any other
   * other borrower whose debt should be removed
   * @return The final amount repaid
   **/

  function repay(
    address asset,
    uint256 amount
  ) external override whenNotPaused returns (uint256) {
    DataTypes.ReserveData storage reserve = _reserves[asset];

    uint256 userDebt = Helpers.getUserCurrentDebt(msg.sender, reserve);
    console.log("currentDebt %s", userDebt);
    ValidationLogic.validateRepay(
      reserve,
      amount,
      msg.sender
    );

    uint256 paybackAmount = userDebt;

    if (amount < paybackAmount) {
      paybackAmount = amount;
    }

    // reserve.updateState();

    IDebtToken(reserve.debtTokenAddress).burn(msg.sender, paybackAmount);

    address wvToken = reserve.wvTokenAddress;
    // reserve.updateInterestRates(asset, wvToken, paybackAmount, 0);

    if (userDebt.sub(paybackAmount) == 0) {
      _usersConfig[msg.sender].setBorrowing(reserve.id, false);
    }

    IERC20(asset).safeTransferFrom(msg.sender, wvToken, paybackAmount);

    // IWvToken(wvToken).handleRepayment(msg.sender, paybackAmount);

    emit Repay(asset, msg.sender, paybackAmount);

    return paybackAmount;
  }

  /**
   * @dev Allows depositors to enable/disable a specific deposited asset as collateral
   * @param asset The address of the underlying asset deposited
   * @param useAsCollateral `true` if the user wants to use the deposit as collateral, `false` otherwise
   **/
  function setUserUseReserveAsCollateral(address asset, bool useAsCollateral)
    external
    override
    whenNotPaused
  {
    DataTypes.ReserveData storage reserve = _reserves[asset];

    ValidationLogic.validateSetUseReserveAsCollateral(
      reserve,
      asset,
      useAsCollateral,
      _reserves,
      _usersConfig[msg.sender],
      _reservesList,
      _reservesCount,
      _addressesProvider.getPriceOracle()
    );

    _usersConfig[msg.sender].setUsingAsCollateral(reserve.id, useAsCollateral);

    if (useAsCollateral) {
      emit ReserveUsedAsCollateralEnabled(asset, msg.sender);
    } else {
      emit ReserveUsedAsCollateralDisabled(asset, msg.sender);
    }
  }

  /**
   * @dev Function to liquidate a non-healthy position collateral-wise, with Health Factor below 1
   * - The caller (liquidator) covers `debtToCover` amount of debt of the user getting liquidated, and receives
   *   a proportionally amount of the `collateralAsset` plus a bonus to cover market risk
   * @param collateralAsset The address of the underlying asset used as collateral, to receive as result of the liquidation
   * @param debtAsset The address of the underlying borrowed asset to be repaid with the liquidation
   * @param user The address of the borrower getting liquidated
   * @param debtToCover The debt amount of borrowed `asset` the liquidator wants to cover
   * @param receiveAToken `true` if the liquidators wants to receive the collateral wvTokens, `false` if he wants
   * to receive the underlying collateral asset directly
   **/
  function liquidationCall(
    address collateralAsset,
    address debtAsset,
    address user,
    uint256 debtToCover,
    bool receiveAToken
  ) external override whenNotPaused {
    address collateralManager = _addressesProvider.getLendingPoolCollateralManager();

    //solium-disable-next-line
    (bool success, bytes memory result) =
      collateralManager.delegatecall(
        abi.encodeWithSignature(
          'liquidationCall(address,address,address,uint256,bool)',
          collateralAsset,
          debtAsset,
          user,
          debtToCover,
          receiveAToken
        )
      );

    require(success, Errors.LP_LIQUIDATION_CALL_FAILED);

    (uint256 returnCode, string memory returnMessage) = abi.decode(result, (uint256, string));

    require(returnCode == 0, string(abi.encodePacked(returnMessage)));
  }

  /**
   * @dev Returns the state and configuration of the reserve
   * @param asset The address of the underlying asset of the reserve
   * @return The state of the reserve
   **/
  function getReserveData(address asset)
    external
    view
    override
    returns (DataTypes.ReserveData memory)
  {
    return _reserves[asset];
  }

  /**
   * @dev Returns the user account data across all the reserves
   * @param user The address of the user
   * @return totalCollateralETH the total collateral in ETH of the user
   * @return totalDebtETH the total debt in ETH of the user
   * @return availableBorrowsETH the borrowing power left of the user
   * @return currentLiquidationThreshold the liquidation threshold of the user
   * @return ltv the loan to value of the user
   * @return healthFactor the current health factor of the user
   **/
  function getUserAccountData(address user)
    external
    view
    override
    returns (
      uint256 totalCollateralETH,
      uint256 totalDebtETH,
      uint256 availableBorrowsETH,
      uint256 currentLiquidationThreshold,
      uint256 ltv,
      uint256 healthFactor
    )
  {
    (
      totalCollateralETH,
      totalDebtETH,
      ltv,
      currentLiquidationThreshold,
      healthFactor
    ) = GenericLogic.calculateUserAccountData(
      user,
      _reserves,
      _usersConfig[user],
      _reservesList,
      _reservesCount,
      _addressesProvider.getPriceOracle()
    );

    availableBorrowsETH = GenericLogic.calculateAvailableBorrowsETH(
      totalCollateralETH,
      totalDebtETH,
      ltv
    );
  }

  /**
   * @dev Returns the configuration of the reserve
   * @param asset The address of the underlying asset of the reserve
   * @return The configuration of the reserve
   **/
  function getConfiguration(address asset)
    external
    view
    override
    returns (DataTypes.ReserveConfigurationMap memory)
  {
    return _reserves[asset].configuration;
  }

  /**
   * @dev Returns the configuration of the user across all the reserves
   * @param user The user address
   * @return The configuration of the user
   **/
  function getUserConfiguration(address user)
    external
    view
    override
    returns (DataTypes.UserConfigurationMap memory)
  {
    return _usersConfig[user];
  }

  /**
   * @dev Returns the normalized income per unit of asset
   * @param asset The address of the underlying asset of the reserve
   * @return The reserve's normalized income
   */
  function getReserveNormalizedIncome(address asset)
    external
    view
    virtual
    override
    returns (uint256)
  {
    return _reserves[asset].getNormalizedIncome();
  }

  /**
   * dev Returns the normalized variable debt per unit of asset
   * param asset The address of the underlying asset of the reserve
   * return The reserve normalized variable debt
   */
  /* function getReserveNormalizedVariableDebt(address asset)
    external
    view
    override
    returns (uint256)
  {
    return _reserves[asset].getNormalizedDebt();
  } */

  /**
   * @dev Returns if the LendingPool is paused
   */
  function paused() external view override returns (bool) {
    return _paused;
  }

  /**
   * @dev Returns the list of the initialized reserves
   **/
  function getReservesList() external view override returns (address[] memory) {
    address[] memory _activeReserves = new address[](_reservesCount);

    for (uint256 i = 0; i < _reservesCount; i++) {
      _activeReserves[i] = _reservesList[i];
    }
    return _activeReserves;
  }

  /**
   * @dev Returns the cached LendingPoolAddressesProvider connected to this contract
   **/
  function getAddressesProvider() external view override returns (ILendingPoolAddressesProvider) {
    return _addressesProvider;
  }

  /**
   * @dev Returns the maximum number of reserves supported to be listed in this LendingPool
   */
  function MAX_NUMBER_RESERVES() public view returns (uint256) {
    return _maxNumberOfReserves;
  }

  /**
   * @dev Validates and finalizes an wvToken transfer
   * - Only callable by the overlying wvToken of the `asset`
   * @param asset The address of the underlying asset of the wvToken
   * @param from The user from which the wvTokens are transferred
   * @param to The user receiving the wvTokens
   * @param amount The amount being transferred/withdrawn
   * @param balanceFromBefore The wvToken balance of the `from` user before the transfer
   * @param balanceToBefore The wvToken balance of the `to` user before the transfer
   */
  function finalizeTransfer(
    address asset,
    address from,
    address to,
    uint256 amount,
    uint256 balanceFromBefore,
    uint256 balanceToBefore
  ) external override whenNotPaused {
    require(msg.sender == _reserves[asset].wvTokenAddress, Errors.LP_CALLER_MUST_BE_AN_ATOKEN);

    ValidationLogic.validateTransfer(
      from,
      _reserves,
      _usersConfig[from],
      _reservesList,
      _reservesCount,
      _addressesProvider.getPriceOracle()
    );

    uint256 reserveId = _reserves[asset].id;

    if (from != to) {
      if (balanceFromBefore.sub(amount) == 0) {
        DataTypes.UserConfigurationMap storage fromConfig = _usersConfig[from];
        fromConfig.setUsingAsCollateral(reserveId, false);
        emit ReserveUsedAsCollateralDisabled(asset, from);
      }

      if (balanceToBefore == 0 && amount != 0) {
        DataTypes.UserConfigurationMap storage toConfig = _usersConfig[to];
        toConfig.setUsingAsCollateral(reserveId, true);
        emit ReserveUsedAsCollateralEnabled(asset, to);
      }
    }
  }

  /**
   * @dev Initializes a reserve, activating it, assigning an wvToken and debt tokens and an
   * interest rate strategy
   * - Only callable by the LendingPoolConfigurator contract
   * @param asset The address of the underlying asset of the reserve
   * @param wvTokenAddress The address of the wvToken that will be assigned to the reserve
   * @param debtTokenAddress The address of the DebtToken that will be assigned to the reserve
   * @param vaultTokenAddress The address of the vaultToken that will be assigned to the reserve
   * @param interestRateStrategyAddress The address of the interest rate strategy contract
   **/
  function initReserve(
    address asset,
    address wvTokenAddress,
    address debtTokenAddress,
    address vaultTokenAddress,
    address interestRateStrategyAddress
  ) external override onlyLendingPoolConfigurator {
    require(Address.isContract(asset), Errors.LP_NOT_CONTRACT);
    _reserves[asset].init(
      wvTokenAddress,
      debtTokenAddress,
      vaultTokenAddress,
      interestRateStrategyAddress
    );
    _addReserveToList(asset);
  }

  /**
   * @dev Updates the address of the interest rate strategy contract
   * - Only callable by the LendingPoolConfigurator contract
   * @param asset The address of the underlying asset of the reserve
   * @param rateStrategyAddress The address of the interest rate strategy contract
   **/
  function setReserveInterestRateStrategyAddress(address asset, address rateStrategyAddress)
    external
    override
    onlyLendingPoolConfigurator
  {
    _reserves[asset].interestRateStrategyAddress = rateStrategyAddress;
  }

  /**
   * @dev Sets the configuration bitmap of the reserve as a whole
   * - Only callable by the LendingPoolConfigurator contract
   * @param asset The address of the underlying asset of the reserve
   * @param configuration The new configuration bitmap
   **/
  function setConfiguration(address asset, uint256 configuration)
    external
    override
    onlyLendingPoolConfigurator
  {
    _reserves[asset].configuration.data = configuration;
  }

  /**
   * @dev Set the _pause state of a reserve
   * - Only callable by the LendingPoolConfigurator contract
   * @param val `true` to pause the reserve, `false` to un-pause it
   */
  function setPause(bool val) external override onlyLendingPoolConfigurator {
    _paused = val;
    if (_paused) {
      emit Paused();
    } else {
      emit Unpaused();
    }
  }

  /* struct ExecuteBorrowParams {
    address asset;
    address user;
    address onBehalfOf;
    uint256 amount;
    uint256 interestRateMode;
    address wvTokenAddress;
    uint16 referralCode;
    bool releaseUnderlying;
  } */
  struct ExecuteBorrowParams {
    address collateralAsset;
    uint256 collateralAmount;
    address assetToBorrow;
    address user;
    uint256 leverageRatioMode;
    address wvTokenAddress;
    bool releaseUnderlying;
  }

  function _executeBorrow(ExecuteBorrowParams memory vars) internal {
    DataTypes.ReserveData storage reserve = _reserves[vars.assetToBorrow];
    DataTypes.UserConfigurationMap storage userConfig = _usersConfig[vars.user];

    DataTypes.ReserveData storage collateralReserve = _reserves[vars.collateralAsset];
    
    // deposit collateral asset
    if (vars.collateralAmount > 0) {
      deposit(vars.collateralAsset, vars.collateralAmount);
      _usersConfig[vars.user].setUsingAsCollateral(collateralReserve.id, true);
      emit ReserveUsedAsCollateralEnabled(vars.collateralAsset, vars.user);
    }

    address oracle = _addressesProvider.getPriceOracle();
    
    // validate borrow conditions
    ValidationLogic.validateBorrow(
      vars.assetToBorrow,
      reserve,
      vars.user,
      vars.leverageRatioMode,
      _reserves,
      userConfig,
      _reservesList,
      _reservesCount,
      oracle
    );

    // check user pool balance
    uint256 poolBalance;
    (, poolBalance) = 
      IWvToken(collateralReserve.wvTokenAddress).getUserBalanceAndSupply(vars.user);

    console.log("poolBalance %s", poolBalance);

    /* uint256 poolBalanceInETH = 
      IPriceOracleGetter(oracle).getAssetPrice(vars.assetToBorrow)
      .mul(IERC20(vars.assetToBorrow).balanceOf(vars.wvTokenAddress))
      .div(10**reserve.configuration.getDecimals());
    console.log("poolBalanceETH %s", poolBalanceInETH); */

    require(poolBalance >= vars.collateralAmount.mul(vars.leverageRatioMode), 
      "Lending Pool does not have enough balance");

    uint256 borrowAmount = vars.collateralAmount
      .mul(vars.leverageRatioMode)
      .sub(vars.collateralAmount);
      
    console.log("Borrow amount from lending pool %s", borrowAmount);

    // transfer from reserve pool to YF pool
    address yfpool = _addressesProvider.getYieldFarmingPool();

    IWvToken(collateralReserve.wvTokenAddress).transferUnderlyingTo(
      yfpool, 
      borrowAmount
    );

    uint256 swappedAmount = IYieldFarmingPool(yfpool).swap(
        vars.collateralAsset,
        vars.assetToBorrow,
        borrowAmount
    );
    console.log("swappedAmount %s", swappedAmount);
    // reserve.updateState();

    bool isFirstBorrowing = false;

    // issue debt token with leverage amount
    isFirstBorrowing = IDebtToken(collateralReserve.debtTokenAddress).mint(
      vars.user,
      borrowAmount
    );

    if (isFirstBorrowing) {
      userConfig.setBorrowing(reserve.id, true);
    }

    emit Borrow(
      vars.assetToBorrow,
      vars.user,
      vars.leverageRatioMode
    );
  }

  function _addReserveToList(address asset) internal {
    uint256 reservesCount = _reservesCount;

    require(reservesCount < _maxNumberOfReserves, Errors.LP_NO_MORE_RESERVES_ALLOWED);

    bool reserveAlreadyAdded = _reserves[asset].id != 0 || _reservesList[0] == asset;

    if (!reserveAlreadyAdded) {
      _reserves[asset].id = uint8(reservesCount);
      _reservesList[reservesCount] = asset;

      _reservesCount = reservesCount + 1;
    }
  }
}
