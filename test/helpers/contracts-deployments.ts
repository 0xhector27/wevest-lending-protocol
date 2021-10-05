import { ethers } from "hardhat";
import { Contract} from 'ethers';
import { ContractId } from "./types";

import { EthereumConfig } from "../markets/ethereum";

export const deployLendingPoolAddressesProvider = async (): Promise<Contract> => {
    const addressesProvider = await (
        await ethers.getContractFactory(ContractId.LendingPoolAddressesProvider)
    ).deploy(EthereumConfig.MarketId);
    return await addressesProvider.deployed();
}

export const deployLendingPoolAddressesProviderRegistry = async (): Promise<Contract> => {
    const lendingPoolAddressesProviderRegistry = await (
        await ethers.getContractFactory(ContractId.LendingPoolAddressesProviderRegistry)
    ).deploy();
    return await lendingPoolAddressesProviderRegistry.deployed();
}

export const deployReserveLogic = async (): Promise<Contract> => {
    const reserveLogic = await (
        await ethers.getContractFactory(ContractId.ReserveLogic)
    ).deploy();
    return await reserveLogic.deployed();
}

export const deployGenericLogic = async (): Promise<Contract> => {
    const genericLogic = await (
        await ethers.getContractFactory(ContractId.GenericLogic)
    ).deploy();
    return await genericLogic.deployed();
}

export const deployValidationLogic = async (): Promise<Contract> => {
    const genericLogic = await deployGenericLogic();
    const validationLogic = await (
        await ethers.getContractFactory(ContractId.ValidationLogic, {
            libraries: {
                GenericLogic: genericLogic.address
            }
        })
    ).deploy();
    return await validationLogic.deployed();
}

export const deployLendingPool = async (): Promise<Contract> => {
    const reserveLogic = await deployReserveLogic();
    const validationLogic = await deployValidationLogic();

    const lendingPoolImpl = await (
        await ethers.getContractFactory(ContractId.LendingPool, {
            libraries: {
                ReserveLogic: reserveLogic.address,
                ValidationLogic: validationLogic.address
            },
        })
    ).deploy();

    return await lendingPoolImpl.deployed();
}

export const deployLendingPoolConfigurator = async (): Promise<Contract> => {
    const lendingPoolConfiguratorImpl = await (
        await ethers.getContractFactory(ContractId.LendingPoolConfigurator)
    ).deploy();
    return await lendingPoolConfiguratorImpl.deployed();
}

export const deployPriceOracle = async (): Promise<Contract> => {
    const priceOracle = await (
        await ethers.getContractFactory(ContractId.PriceOracle)
    ).deploy();
    return await priceOracle.deployed();
}

export const deployProtocolDataProvider = async (addressesProvider: string): Promise<Contract> => {
    const protocolDataProvider = await (
        await ethers.getContractFactory(ContractId.WevestProtocolDataProvider)
    ).deploy(addressesProvider);
    return await protocolDataProvider.deployed();
}