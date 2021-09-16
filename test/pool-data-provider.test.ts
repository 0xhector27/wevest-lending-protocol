import { ethers, upgrades } from "hardhat";
import { Signer } from "ethers";
import chai from "chai";
import { solidity } from "ethereum-waffle";

chai.use(solidity);
const { expect } = chai;

describe("Lending Pool Data Provider", () => {
    let signers: Signer[];
    let deployer: Signer;

    let poolDataProviderContract: any;

    beforeEach(async () => {
        // get signers array
        signers = await ethers.getSigners();
        // set first signer as deployer
        deployer = signers[0];

        const poolAddressesFactory = await ethers.getContractFactory("LendingPoolAddressesProvider");
        const poolAddressesContract = await poolAddressesFactory.deploy();
        await poolAddressesContract.deployed();
        console.log("Addresses provider deployed to:", poolAddressesContract.address);
        
        /* const poolDataProviderFactory = await ethers.getContractFactory("LendingPoolDataProvider");
        poolDataProviderContract = await upgrades.deployProxy(poolDataProviderFactory, [poolAddressesContract.address]);
        await poolDataProviderContract.deployed();
        console.log("Data provider deployed to:", poolDataProviderContract.address); */
    });

    it("Get Revision", async () => {
        // console.log(await poolDataProviderContract.getRevision());
    });
});
