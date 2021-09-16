import { ethers } from "hardhat";
import { Signer } from "ethers";
import { ERC20__factory } from "../../typechain";
import { 
    LendingPool__factory,
    LendingPoolDataProvider__factory, 
    MintableERC20__factory, 
    WvToken__factory, 
} from "../../typechain";
import { eContractid } from './constants';

export const getFirstSigner = async () => (await getEthersSigners())[0];

export const convertToCurrencyDecimals = async (tokenAddress: string, amount: string) => {
    const [deployer, user] = await ethers.getSigners();
    const tokenInstance = new ERC20__factory(deployer).attach(tokenAddress);
    let decimals = (await tokenInstance.decimals()).toString();
  
    return ethers.utils.parseUnits(amount, decimals);
};

export const getEthersSigners = async (): Promise<Signer[]> => {
    const ethersSigners = await Promise.all(await ethers.getSigners());
    return ethersSigners;
};

export const getLendingPoolAddressesProvider = async () => {
    const lendingPoolAddressesFactory = await ethers.getContractFactory(eContractid.LendingPoolAddressesProvider);
    const lendingPoolAddressesContract = await lendingPoolAddressesFactory.deploy();
    return lendingPoolAddressesContract;
};

export const getLendingPool = async () => {
    const lendingPoolFactory = new LendingPool__factory(await getFirstSigner());
    const lendingPoolContract = await lendingPoolFactory.deploy();
    return lendingPoolContract;
};

export const getLendingPoolDataProvider = async () => {
    const lendingPoolDataProviderFactory = new LendingPoolDataProvider__factory(await getFirstSigner());
    return await lendingPoolDataProviderFactory.deploy();
};

export const getMintableERC20 = async (address: string) => {
    return await MintableERC20__factory.connect(address, await getFirstSigner());
};

export const getWvToken = async (address: string) => {
    return await WvToken__factory.connect(address, await getFirstSigner());
};
