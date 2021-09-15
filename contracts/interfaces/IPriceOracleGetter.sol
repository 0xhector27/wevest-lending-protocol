// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.6.0;

/************
@notice Interface for the Wevest price oracle.
*/

interface IPriceOracleGetter {
    /***********
    @dev returns the asset price in ETH
     */
    function getAssetPrice(address _asset) external view returns (uint256);
}
