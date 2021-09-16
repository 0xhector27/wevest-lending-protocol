import { ethers } from "hardhat";
import { Signer } from "ethers";
import chai from "chai";
import { solidity } from "ethereum-waffle";
import { convertToCurrencyDecimals } from './utils/helpers';
import { APPROVAL_AMOUNT_LENDING_POOL } from './utils/constants';
import { 
    LendingPoolAddressesProvider__factory,
    LendingPoolCore__factory,
    LendingPool__factory, 
    MockDAI__factory,
    WvToken__factory 
} from "../typechain";

chai.use(solidity);
const { expect } = chai;

describe("Lending Pool", () => {
    let signers: Signer[];
    let deployer: Signer;

    let lendingPoolContract: any;
    let lendingPoolCoreContract: any;
    let mockDaiContract: any;
    let wvDaiContract: any;

    before(async () => {
        // get signers array
        signers = await ethers.getSigners();
        // set first signer as deployer
        deployer = signers[0];
        const poolAddressesFactory = await ethers.getContractFactory("LendingPoolAddressesProvider");
        const poolAddressesContract = await poolAddressesFactory.deploy();
        await poolAddressesContract.deployed();

        const lendingPoolFactory = await ethers.getContractFactory("LendingPool");
        lendingPoolContract = await lendingPoolFactory.deploy();

        const mockDaiFactory = await ethers.getContractFactory("MockDAI");
        mockDaiContract = await mockDaiFactory.deploy();
        await mockDaiContract.deployed();

        const wvTokenFactory = await ethers.getContractFactory("WvToken");
        wvDaiContract = await wvTokenFactory.deploy(
            poolAddressesContract.address, 
            mockDaiContract.address, 
            18, 
            "wvDai", 
            "wvDai"
        );
        await wvDaiContract.deployed();
        console.log("WvToken deployed to:", wvDaiContract.address);
    });

    describe("Deposit", async () => {
        it('User1 deposits 1000 DAI in an empty reserve', async() => {
            const amountDAItoDeposit = ethers.utils.parseUnits("1000", 18);
            await mockDaiContract.mint(amountDAItoDeposit);
            await mockDaiContract.approve(lendingPoolContract.address, APPROVAL_AMOUNT_LENDING_POOL);
            
            const user1 = await signers[0].getAddress();
            const user2 = await signers[1].getAddress();

            const fromBalance = await wvDaiContract.balanceOf(user1);
            const toBalance = await wvDaiContract.balanceOf(user2);

            expect(fromBalance.toString()).to.be.equal('0', 'Invalid from balance after transfer');
        });
    });

    describe("Withdraw", async () => {
        it('User2 burn 500 wvDAI and get corresponding 500 DAI from Dai reserve', async() => {
            const user2 = await signers[1].getAddress();
            const amountDAItoWithdraw = ethers.utils.parseUnits("500", 18);
            await mockDaiContract.mint(amountDAItoWithdraw);
            const toBalance = await mockDaiContract.balanceOf(mockDaiContract.address);
            expect(toBalance.toString()).to.be.equal('0', 'Invalid from balance after transfer');
        });
    });
});