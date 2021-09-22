// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

import {DebtTokenBase} from './base/DebtTokenBase.sol';
import {MathUtils} from '../libraries/math/MathUtils.sol';
import {WadRayMath} from '../libraries/math/WadRayMath.sol';
import {IDebtToken} from '../../interfaces/IDebtToken.sol';
import {ILendingPool} from '../../interfaces/ILendingPool.sol';
import {Errors} from '../libraries/helpers/Errors.sol';

/**
 * @title DebtToken
 * @notice Implements a debt token to track the borrowing positions of users
 **/
contract DebtToken is IDebtToken, DebtTokenBase {
  using WadRayMath for uint256;

  uint256 public constant DEBT_TOKEN_REVISION = 0x1;

  // uint256 internal _avgStableRate;
  mapping(address => uint40) internal _timestamps;
  // mapping(address => uint256) internal _usersStableRate;
  uint40 internal _totalSupplyTimestamp;

  ILendingPool internal _pool;
  address internal _underlyingAsset;

  /**
   * @dev Initializes the debt token.
   * @param pool The address of the lending pool where this debtToken will be used
   * @param underlyingAsset The address of the underlying asset of this debtToken (E.g. WETH for debtWETH)
   * @param debtTokenDecimals The decimals of the debtToken, same as the underlying asset's
   * @param debtTokenName The name of the token
   * @param debtTokenSymbol The symbol of the token
   */
  function initialize(
    ILendingPool pool,
    address underlyingAsset,
    uint8 debtTokenDecimals,
    string memory debtTokenName,
    string memory debtTokenSymbol
  ) public override initializer {
    _setName(debtTokenName);
    _setSymbol(debtTokenSymbol);
    _setDecimals(debtTokenDecimals);

    _pool = pool;
    _underlyingAsset = underlyingAsset;

    emit Initialized(
      underlyingAsset,
      address(pool),
      debtTokenDecimals,
      debtTokenName,
      debtTokenSymbol
    );
  }

  /**
   * @dev Gets the revision of the stable debt token implementation
   * @return The debt token implementation revision
   **/
  function getRevision() internal pure virtual override returns (uint256) {
    return DEBT_TOKEN_REVISION;
  }

  /**
   * @dev Returns the timestamp of the last user action
   * @return The last update timestamp
   **/
  function getUserLastUpdated(address user) external view virtual override returns (uint40) {
    return _timestamps[user];
  }

  /**
   * @dev Calculates the current user debt balance
   * @return The debt of the user
   **/
  function balanceOf(address account) public view virtual override returns (uint256) {
    uint256 accountBalance = super.balanceOf(account);
    return accountBalance;
  }

  struct MintLocalVars {
    uint256 previousSupply;
    uint256 nextSupply;
    uint256 amountInRay;
  }

  /**
   * @dev Mints debt token to the `onBehalfOf` address.
   * -  Only callable by the LendingPool
   * - The resulting rate is the weighted average between the rate of the new debt
   * and the rate of the previous debt
   * @param user The address receiving the debt tokens
   * @param amount The amount of debt tokens to mint
   **/
  function mint(
    address user,
    uint256 amount
  ) external override onlyLendingPool returns (bool) {
    MintLocalVars memory vars;

    uint256 currentBalance = super.balanceOf(user);

    vars.previousSupply = totalSupply();
    vars.nextSupply = _totalSupply = vars.previousSupply.add(amount);

    vars.amountInRay = amount.wadToRay();

    //solium-disable-next-line
    _totalSupplyTimestamp = _timestamps[user] = uint40(block.timestamp);

    _mint(user, amount, vars.previousSupply);

    emit Transfer(address(0), user, amount);

    emit Mint(
      user,
      amount,
      currentBalance,
      vars.nextSupply
    );

    return currentBalance == 0;
  }

  /**
   * @dev Burns debt of `user`
   * @param user The address of the user getting his debt burned
   * @param amount The amount of debt tokens getting burned
   **/
  function burn(address user, uint256 amount) external override onlyLendingPool {
    uint256 currentBalance = super.balanceOf(user);

    uint256 previousSupply = totalSupply();
    uint256 nextSupply = 0;

    // Since the total supply and each single user debt accrue separately,
    // there might be accumulation errors so that the last borrower repaying
    // mght actually try to repay more than the available debt supply.
    // In this case we simply set the total supply to 0
    if (previousSupply <= amount) {
      _totalSupply = 0;
    } else {
      nextSupply = _totalSupply = previousSupply.sub(amount);
    }

    if (amount == currentBalance) {
      _timestamps[user] = 0;
    } else {
      //solium-disable-next-line
      _timestamps[user] = uint40(block.timestamp);
    }
    //solium-disable-next-line
    _totalSupplyTimestamp = uint40(block.timestamp);

    uint256 amountToBurn = amount;
    _burn(user, amountToBurn, previousSupply);
    emit Burn(user, amountToBurn, currentBalance, nextSupply);
    
    emit Transfer(user, address(0), amount);
  }

  /**
   * @dev Returns the total supply
   **/
  function totalSupply() public view override returns (uint256) {
    return super.totalSupply();
  }

  /**
   * @dev Returns the timestamp at which the total supply was updated
   **/
  function getTotalSupplyLastUpdated() public view override returns (uint40) {
    return _totalSupplyTimestamp;
  }

  /**
   * @dev Returns the the total supply and the average stable rate
   **/
  function getTotalSupply() public view override returns (uint256) {
    return super.totalSupply();
  }
  
  /**
   * @dev Returns the principal debt balance of the user from
   * @param user The user's address
   * @return The debt balance of the user since the last burn/mint action
   **/
  function principalBalanceOf(address user) external view virtual override returns (uint256) {
    return super.balanceOf(user);
  }

  /**
   * @dev Returns the address of the underlying asset of this aToken (E.g. WETH for aWETH)
   **/
  function UNDERLYING_ASSET_ADDRESS() public view returns (address) {
    return _underlyingAsset;
  }

  /**
   * @dev Returns the address of the lending pool where this aToken is used
   **/
  function POOL() public view returns (ILendingPool) {
    return _pool;
  }

  /**
   * @dev For internal usage in the logic of the parent contracts
   **/
  function _getUnderlyingAssetAddress() internal view override returns (address) {
    return _underlyingAsset;
  }

  /**
   * @dev For internal usage in the logic of the parent contracts
   **/
  function _getLendingPool() internal view override returns (ILendingPool) {
    return _pool;
  }

  /**
   * @dev Mints stable debt tokens to an user
   * @param account The account receiving the debt tokens
   * @param amount The amount being minted
   * @param oldTotalSupply the total supply before the minting event
   **/
  function _mint(
    address account,
    uint256 amount,
    uint256 oldTotalSupply
  ) internal {
    uint256 oldAccountBalance = _balances[account];
    _balances[account] = oldAccountBalance.add(amount);
  }

  /**
   * @dev Burns stable debt tokens of an user
   * @param account The user getting his debt burned
   * @param amount The amount being burned
   * @param oldTotalSupply The total supply before the burning event
   **/
  function _burn(
    address account,
    uint256 amount,
    uint256 oldTotalSupply
  ) internal {
    uint256 oldAccountBalance = _balances[account];
    _balances[account] = oldAccountBalance.sub(amount, Errors.SDT_BURN_EXCEEDS_BALANCE);
  }
}
