import chai from 'chai';
import { ethers } from "hardhat";
import { solidity } from "ethereum-waffle";
import { Signer, BigNumberish } from "ethers";
import {
    LendingPool__factory,
    LendingPoolConfigurator__factory,
    WvToken__factory,
    MintableERC20__factory,
    YieldFarmingPool__factory
} from '../types';

chai.use(solidity);
const { expect } = chai;

describe("Lending Pool", () => {
    let signers: Signer[];
    let deployer: Signer;
    let userA: Signer;
    let amountUSDCtoDeposit: BigNumberish;
    const APPROVAL_AMOUNT_LENDING_POOL = '1000000000000000000000000000';
    let wvUsdc: any;

    let allWvTokens: any;
    let usdc: any, aave: any, wvToken: any, lendingPoolProxy: any;
    let wvUSDCAddress: any;
    let lendingPoolAddressesProvider, lendingPoolConfiguratorProxy;
    let debtToken, interestRateStrategy, protocolDataProvider;

    let yfPoolProxy: any;

    before(async () => {
        // get signers array
        signers = await ethers.getSigners();
        // set first signer as deployer
        deployer = signers[0];

        const LendingPoolAddressesProvider = await ethers.getContractFactory("LendingPoolAddressesProvider");
        lendingPoolAddressesProvider = await LendingPoolAddressesProvider.deploy("Main Market");
        await lendingPoolAddressesProvider.deployed();

        console.log("LendingPoolAddressesProvider deployed to:", lendingPoolAddressesProvider.address);

        await lendingPoolAddressesProvider.setPoolAdmin(await deployer.getAddress());
        await lendingPoolAddressesProvider.setEmergencyAdmin(await signers[1].getAddress());

        // deploy logic libraries used by Lending Pool
        const reserveLogicLibFactory = await ethers.getContractFactory("ReserveLogic");
        const reserveLogicLibContract = await reserveLogicLibFactory.deploy();
        await reserveLogicLibContract.deployed();

        const genericLogicLibFactory = await ethers.getContractFactory("GenericLogic");
        const genericLogicLibContract = await genericLogicLibFactory.deploy();
        await genericLogicLibContract.deployed();

        const validationLogicLibFactory = await ethers.getContractFactory("ValidationLogic", {
            libraries: {
                GenericLogic: genericLogicLibContract.address
            }
        });
        const validationLogicLibContract = await validationLogicLibFactory.deploy();
        await validationLogicLibContract.deployed();

        // LendingPool contract
        const LendingPool = await ethers.getContractFactory("LendingPool", {
            libraries: {
                ReserveLogic: reserveLogicLibContract.address,
                ValidationLogic: validationLogicLibContract.address
            },
        });
        const lendingPool = await LendingPool.deploy();
        await lendingPool.deployed();

        // update implementation as proxy contract
        await lendingPoolAddressesProvider.setLendingPoolImpl(lendingPool.address);
        const lendingPoolAddress = await lendingPoolAddressesProvider.getLendingPool();

        // get LendingPoolProxy contract
        lendingPoolProxy = await LendingPool__factory.connect(lendingPoolAddress, deployer);
        console.log("LendingPool deployed to:", lendingPoolProxy.address);
        console.log(await lendingPoolProxy.getAddressesProvider());
        
        const LendingPoolConfigurator = await ethers.getContractFactory("LendingPoolConfigurator");
        const lendingPoolConfigurator  = await LendingPoolConfigurator.deploy();
        await lendingPoolConfigurator.deployed();

        // update as proxy contract
        await lendingPoolAddressesProvider.setLendingPoolConfiguratorImpl(lendingPoolConfigurator.address);
        const lendingPoolConfiguratorAddress = await lendingPoolAddressesProvider.getLendingPoolConfigurator();
        // get LendingPoolConfiguratorProxy contract
        lendingPoolConfiguratorProxy = await LendingPoolConfigurator__factory.connect(lendingPoolConfiguratorAddress, deployer);
        console.log("LendingPoolConfigurator deployed to:", lendingPoolConfiguratorProxy.address);

        // deploy USDC mock contract
        const MintableERC20 = await ethers.getContractFactory("MintableERC20");
        usdc = await MintableERC20.deploy("USD Coin", "USDC", 6);
        await usdc.deployed();
        console.log("USDC deployed to:", usdc.address);

        aave = await MintableERC20.deploy("Aave Token", "AAVE", 18);
        await aave.deployed();

        console.log("AAVE deployed to:", aave.address);

        const WvToken = await ethers.getContractFactory("WvToken");
        wvToken = await WvToken.deploy();
        await wvToken.deployed();

        const treasuryExample = "0x488177c42bD58104618cA771A674Ba7e4D5A2FBB";

        await wvToken.initialize(
            lendingPoolProxy.address,
            treasuryExample,
            usdc.address,
            6,
            'Wevest interest bearing USDC',
            'wvUSDC'
        );

        console.log("wvUSDC deployed to:", wvToken.address);

        const DebtToken = await ethers.getContractFactory("DebtToken");
        debtToken = await DebtToken.deploy();
        await debtToken.deployed();

        await debtToken.initialize(
            lendingPoolProxy.address,
            usdc.address,
            18,
            'Wevest debt bearing AAVE',
            'debtAAVE'
        );

        console.log("debtAAVE deployed to:", debtToken.address);

        const InterestRateStrategy = await ethers.getContractFactory("DefaultReserveInterestRateStrategy");
        interestRateStrategy = await InterestRateStrategy.deploy(lendingPoolAddressesProvider.address);
        await interestRateStrategy.deployed();
        
        console.log("DefaultReserveInterestRateStrategy deployed to:", interestRateStrategy.address);
        
        let initReserveParams: {
            wvTokenImpl: string;
            debtTokenImpl: string;
            underlyingAsset: string;
            underlyingAssetName: string;
            underlyingAssetDecimals: BigNumberish;
            interestRateStrategyAddress: string;
            treasury: string;
            wvTokenName: string;
            wvTokenSymbol: string;
            debtTokenName: string;
            debtTokenSymbol: string;
        }[] = [];

        initReserveParams.push({
            wvTokenImpl: wvToken.address,
            debtTokenImpl: debtToken.address,
            underlyingAsset: usdc.address,
            underlyingAssetName: await usdc.name(),
            underlyingAssetDecimals: await usdc.decimals(),
            interestRateStrategyAddress: interestRateStrategy.address,
            treasury: treasuryExample,
            wvTokenName: await wvToken.name(),
            wvTokenSymbol: await wvToken.symbol(),
            debtTokenName: await debtToken.name(),
            debtTokenSymbol: await debtToken.symbol()
        });

        await lendingPoolConfiguratorProxy.batchInitReserve(initReserveParams);
        // deploy ProtocolDataProvider
        const ProtocolDataProvider = await ethers.getContractFactory("WevestProtocolDataProvider");
        protocolDataProvider  = await ProtocolDataProvider.deploy(lendingPoolAddressesProvider.address);
        await protocolDataProvider.deployed();
        console.log("ProcotolDataProvider deployed to:", protocolDataProvider.address);
        allWvTokens = await protocolDataProvider.getAllWvTokens();
        console.log(allWvTokens);

        amountUSDCtoDeposit = ethers.utils.parseUnits("100", 6);

        // deploy YieldFarmingPool
        const YieldFarmingPool = await ethers.getContractFactory("YieldFarmingPool");
        const yieldFarmingPool  = await YieldFarmingPool.deploy();
        await yieldFarmingPool.deployed();

        // update as proxy contract
        await lendingPoolAddressesProvider.setYieldFarmingPoolImpl(yieldFarmingPool.address);
        const yieldFarmingPoolAddress = await lendingPoolAddressesProvider.getYieldFarmingPool();
        // get yfpool proxy contract
        yfPoolProxy = await YieldFarmingPool__factory.connect(yieldFarmingPoolAddress, deployer);
        console.log("YieldFarmingPool deployed to:", yfPoolProxy.address);
    });

    describe("Deposit", async () => {
        it("UserA deposit 100 USDC to lending pool", async () => {
            userA = signers[2];
            // before start, first create 1000 USDC in userA account
            await usdc.connect(userA).mint(ethers.utils.parseUnits("1000", 6));
            await usdc.connect(userA).approve(lendingPoolProxy.address, APPROVAL_AMOUNT_LENDING_POOL);
            
            await lendingPoolProxy
                .connect(userA)
                .deposit(usdc.address, amountUSDCtoDeposit);
    
        });
    
        it("USDC pool balance after deposit action", async() => {
            /* const usdcBalance = await usdc.balanceOf(await userA.getAddress());
            console.log(usdcBalance.toString()); */
            wvUSDCAddress = allWvTokens.find(
                (wvToken: { symbol: string; }) => wvToken.symbol === 'wvUSDC'
            )?.tokenAddress;
            wvUsdc = await WvToken__factory.connect(wvUSDCAddress, deployer);
            const reserveUsdcBalance = await usdc.balanceOf(wvUSDCAddress);
            console.log("USDC pool balance: ", reserveUsdcBalance.toString());
            expect(reserveUsdcBalance.toString()).to.be.equal(
                amountUSDCtoDeposit.toString(), 
                "Invalid USDC reserve balance"
            );
        });
    
        it("UserA's balance after deposit action", async() => {
            const usdcBalance = await usdc.balanceOf(await userA.getAddress());
            console.log("UserA USDC balance: ", usdcBalance.toString());
            const wvUsdcBalance = await wvUsdc.balanceOf(await userA.getAddress());
            console.log("UserA wvUSDC balance: ", wvUsdcBalance.toString());
            expect(wvUsdcBalance.toString()).to.be.equal(
                amountUSDCtoDeposit.toString(), 
                "Invalid wvUSDC amount"
            );
        });
    });
    
    describe("Withdraw", async () => {
        it("UserA withdraws the whole wvUSDC balance", async() => {
            const reserveUsdcBalance = await usdc.balanceOf(wvUSDCAddress);
            console.log("USDC pool previous balance: ", reserveUsdcBalance.toString());
            const wvUsdcBalance = await wvUsdc.balanceOf(await userA.getAddress());
            await lendingPoolProxy
                .connect(userA)
                .withdraw(usdc.address, wvUsdcBalance);
        });

        it("UserA's wvUSDC balance after withdraw action", async() => {
            const usdcBalance = await usdc.balanceOf(await userA.getAddress());
            console.log("UserA USDC balance: ", usdcBalance.toString());

            const wvUsdcBalance = await wvUsdc.balanceOf(await userA.getAddress());
            console.log("UserA wvUSDC balance: ", wvUsdcBalance.toString());
            expect(wvUsdcBalance.toString()).to.be.equal(
                '0', "Invalid wvUSDC amount"
            );
        });

        it("USDC pool balance after withdraw action", async() => {
            const reserveUsdcBalance = await usdc.balanceOf(wvUSDCAddress);
            console.log("USDC pool current balance: ", reserveUsdcBalance.toString());
        });
    });

    /* describe("Borrow", async () => {
        it("UserA deposit 100 USDC as collateral, and want to borrow AAVE with 3x leverage", async() => {
            await lendingPoolProxy
                .connect(userA)
                .deposit(usdc.address, amountUSDCtoDeposit);

            const amountAaveToBorrow = ethers.utils.parseUnits("10", 18);
            await lendingPoolProxy
                .connect(userA)
                .borrow(aave.address, amountAaveToBorrow, 3);
        });
    }); */
});