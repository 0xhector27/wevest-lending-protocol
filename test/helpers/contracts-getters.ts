import {
    LendingPool__factory,
    LendingPoolConfigurator__factory,
    IERC20Detailed__factory
} from '../../types';

import { Signer } from "ethers";
import { ContractId, eEthereumNetwork } from "./types";
import { ethers } from 'hardhat';

import { EthereumConfig } from '../markets/ethereum';

export const getLendingPool = async (
    address: string, 
    signer: Signer
) => LendingPool__factory.connect(address, signer);

export const getLendingPoolConfigurator = async (
    address: string, 
    signer: Signer
) => LendingPoolConfigurator__factory.connect(address, signer);

export const getIErc20Detailed = async (
    address: string,
    signer: Signer
) => IERC20Detailed__factory.connect(address, signer);
