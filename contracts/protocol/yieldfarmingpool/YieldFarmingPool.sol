// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {VersionedInitializable} from '../libraries/wevest-upgradeability/VersionedInitializable.sol';
import {ILendingPool} from '../../interfaces/ILendingPool.sol';
import {IYieldFarmingPool} from '../../interfaces/IYieldFarmingPool.sol';
import {ILendingPoolAddressesProvider} from '../../interfaces/ILendingPoolAddressesProvider.sol';
import {IVault} from "../../interfaces/IVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "hardhat/console.sol";

contract YieldFarmingPool is VersionedInitializable, IYieldFarmingPool {

    uint256 public constant YIELDFARMING_POOL_REVISION = 0x2;

    ILendingPoolAddressesProvider internal _addressesProvider;

    function initialize(ILendingPoolAddressesProvider provider) public initializer {
        _addressesProvider = provider;
    }

    function getRevision() internal pure override returns (uint256) {
        return YIELDFARMING_POOL_REVISION;
    }

    modifier amountGreaterThanZero(uint256 amount) {
        require(amount > 0, "Invalid amount");
        _;
    }

    function deposit(address vault, address asset, uint256 amount) 
        external 
        override
        amountGreaterThanZero(amount)
        returns(uint256) 
    {
        uint256 assetBalance = IERC20(asset).balanceOf(address(this));
        require(assetBalance >= amount, "Exceeds YF pool asset balance");

        IERC20(asset).approve(address(IVault(vault)), amount);
        return IVault(vault).deposit(amount);
    }

    function withdraw(address vault, uint256 maxShares) 
        external
        override
        amountGreaterThanZero(maxShares)
        returns(uint256) 
    {
        uint256 balanceShares = IVault(vault).balanceOf(address(this));
        require(balanceShares >= maxShares, "Exceeds YF pool shares balance");
        uint256 redeemedAmount = IVault(vault).withdraw(maxShares);
        console.log("redeemed amount %s", redeemedAmount);
        return redeemedAmount;
    }

    function balance(address vault) 
        external
        override
        returns(uint256)
    {
        uint256 price = IVault(vault).pricePerShare();
        uint256 balanceShares = IVault(vault).balanceOf(address(this));
        return balanceShares * price;
    }
}