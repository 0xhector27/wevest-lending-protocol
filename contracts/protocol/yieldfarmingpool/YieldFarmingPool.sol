// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {VersionedInitializable} from '../libraries/wevest-upgradeability/VersionedInitializable.sol';
import {ILendingPool} from '../../interfaces/ILendingPool.sol';
// import {IYieldFarmingPool} from '../../interfaces/IYieldFarmingPool.sol';
import {ILendingPoolAddressesProvider} from '../../interfaces/ILendingPoolAddressesProvider.sol';
import {IVault} from "../../interfaces/IVault.sol";
import {IWvToken} from '../../interfaces/IWvToken.sol';
import {ITokenSwap} from '../../interfaces/ITokenSwap.sol';
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPriceOracleGetter} from '../../interfaces/IPriceOracleGetter.sol';
import "hardhat/console.sol";

contract YieldFarmingPool is VersionedInitializable {

    uint256 public constant YIELDFARMING_POOL_REVISION = 0x2;
    // Use mapping variable to save deposit amount from our YF pool to YF protocol.
    mapping(address => uint256) internal depositAmount;
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
        amountGreaterThanZero(amount)
        returns(uint256) 
    {
        uint256 assetBalance = IERC20(asset).balanceOf(address(this));
        require(assetBalance >= amount, "Exceeds YF pool asset balance");
        IERC20(asset).approve(vault, amount);
        uint256 wrappedAmount = IVault(vault).deposit(amount);
        if (wrappedAmount > 0) {
            depositAmount[asset] = amount;
        }
        return wrappedAmount;
    }

    function withdraw(address vault, uint256 maxShares, address asset) 
        external
        amountGreaterThanZero(maxShares)
        returns(uint256) 
    {
        uint256 balanceShares = IVault(vault).balanceOf(address(this));
        require(balanceShares >= maxShares, "Exceeds YF pool shares balance");
        uint256 withdrawAmount = IVault(vault).withdraw(maxShares);
        if (withdrawAmount > 0) {
            depositAmount[asset] -= withdrawAmount;
        }
        return withdrawAmount;
    }

    function currentBalance(address vault) 
        public
        view
        returns(uint256)
    {
        uint256 price = IVault(vault).pricePerShare();
        uint256 balanceShares = IVault(vault).balanceOf(address(this));
        return balanceShares * price / (10**IVault(vault).decimals());
    }

    function totalEarning(address vault, address asset)
        public
        view
        returns(uint256)
    {
        uint256 currentBal = currentBalance(vault);
        uint256 earning = 0;
        if (currentBal >= depositAmount[asset]) {
            earning = currentBal - depositAmount[asset];
        }
        return earning;
    }
    
    function lenderInterest(
        address vault, 
        address asset, 
        address user,
        address wvToken
    )
        external
        view
        returns(uint256)
    {
        uint256 lenderBalance = IWvToken(wvToken).balanceOf(user);
        uint256 poolBalance = IERC20(asset).balanceOf(wvToken);
        return totalEarning(vault, asset) * lenderBalance / poolBalance;
    }

    function swap(
        address _tokenIn,
        address _tokenOut,
        uint _amountIn
    ) external returns(uint) {
        address tokenSwap = _addressesProvider.getTokenSwap();
        IERC20(_tokenIn).approve(tokenSwap, _amountIn);
        return ITokenSwap(tokenSwap).swap(
            _tokenIn,
            _tokenOut,
            _amountIn,
            1,
            address(this)
        );
    }

    function transferUnderlying(
        address _asset,
        address _to,
        uint256 _amount
    ) external {
        IERC20(_asset).approve(_to, _amount);
        IERC20(_asset).transfer(
            _to, _amount
        );
    }
}