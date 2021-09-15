// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.6.0;

/**
Interface for the Wevest fee provider.
*/

interface IFeeProvider {
    function calculateLoanOriginationFee(address _user, uint256 _amount) external view returns (uint256);
    function getLoanOriginationFeePercentage() external view returns (uint256);
}
