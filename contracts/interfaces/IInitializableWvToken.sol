// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

import {ILendingPool} from './ILendingPool.sol';
// import {IWevestIncentivesController} from './IWevestIncentivesController.sol';

/**
 * @title IInitializableWvToken
 * @notice Interface for the initialize function on WvToken
 **/
interface IInitializableWvToken {
  /**
   * @dev Emitted when an wvToken is initialized
   * @param underlyingAsset The address of the underlying asset
   * @param pool The address of the associated lending pool
   * @param treasury The address of the treasury
   * // param incentivesController The address of the incentives controller for this wvToken
   * @param wvTokenDecimals the decimals of the underlying
   * @param wvTokenName the name of the wvToken
   * @param wvTokenSymbol the symbol of the wvToken
   * // param params A set of encoded parameters for additional initialization
   **/
  /* event Initialized(
    address indexed underlyingAsset,
    address indexed pool,
    address treasury,
    address incentivesController,
    uint8 wvTokenDecimals,
    string wvTokenName,
    string wvTokenSymbol,
    bytes params
  ); */

  event Initialized(
    address indexed underlyingAsset,
    address indexed pool,
    address treasury,
    uint8 wvTokenDecimals,
    string wvTokenName,
    string wvTokenSymbol
  );

  /**
   * @dev Initializes the wvToken
   * @param pool The address of the lending pool where this wvToken will be used
   * @param treasury The address of the Wevest treasury, receiving the fees on this wvToken
   * @param underlyingAsset The address of the underlying asset of this wvToken (E.g. WETH for wvWETH)
   * // param incentivesController The smart contract managing potential incentives distribution
   * @param wvTokenDecimals The decimals of the wvToken, same as the underlying asset's
   * @param wvTokenName The name of the wvToken
   * @param wvTokenSymbol The symbol of the wvToken
   */
  function initialize(
    ILendingPool pool,
    address treasury,
    address underlyingAsset,
    // IWevestIncentivesController incentivesController,
    uint8 wvTokenDecimals,
    string calldata wvTokenName,
    string calldata wvTokenSymbol
    // bytes calldata params
  ) external;
}
