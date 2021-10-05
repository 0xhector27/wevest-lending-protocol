import hre from "hardhat";
import { ethers } from "hardhat";

import { getIErc20Detailed } from "./contracts-getters";

export const unlockAccount = async (address: string) => {
    await hre.network.provider.send("hardhat_impersonateAccount", [address]);
    return address;
};

export const convertToCurrencyDecimals = async (
    tokenAddress: string, 
    amount: string
) => {
    const signers = await ethers.getSigners();
    const token = await getIErc20Detailed(tokenAddress, signers[0]);
    let decimals = (await token.decimals()).toString();
  
    return ethers.utils.parseUnits(amount, decimals);
};