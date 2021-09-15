// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.6.0;

/************
@notice Interface for the Wevest price oracle.*/

interface IPriceOracle {
    /***********
    @dev returns the asset price in ETH
     */
    function getAssetPrice(address _asset) external view returns (uint256);

    /***********
    @dev sets the asset price, in wei
     */
    function setAssetPrice(address _asset, uint256 _price) external;

}
